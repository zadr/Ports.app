import Foundation
import Synchronization

public enum Shell {
    public static func run(
        _ command: Command,
        privilege: Privilege = .direct
    ) async throws -> CommandOutput {
        switch privilege {
        case .direct: try await runDirect(command)
        case .administrator: try await runElevated(command)
        }
    }

    /// Runs `command` and discards output unless it fails.
    @discardableResult
    public static func check(
        _ command: Command,
        privilege: Privilege = .direct
    ) async throws -> CommandOutput {
        let output = try await run(command, privilege: privilege)
        guard output.succeeded else {
            throw ShellError.nonZeroExit(code: output.exitCode, standardError: output.standardError)
        }
        return output
    }

    public static func stream(
        _ command: Command,
        privilege: Privilege = .direct
    ) -> AsyncThrowingStream<ProcessEvent, any Error> {
        switch privilege {
        case .direct: streamDirect(command)
        case .administrator: streamElevated(command)
        }
    }

    public static func which(_ name: String) -> String? {
        let searchPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let directories = searchPath.split(separator: ":").map(String.init)
            + defaultSearchPath.split(separator: ":").map(String.init)
        for directory in directories {
            let candidate = URL(filePath: directory).appending(path: name).path(percentEncoded: false)
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// A bundled app inherits no login shell, so the usual install prefixes are
    /// appended to whatever PATH the app was launched with.
    public static let defaultSearchPath =
        "/opt/local/bin:/opt/local/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    static func processEnvironment(_ command: Command) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let path = environment["PATH"] ?? ""
        environment["PATH"] = path.isEmpty ? defaultSearchPath : "\(path):\(defaultSearchPath)"
        for (key, value) in command.environment { environment[key] = value }
        return environment
    }
}

// MARK: - Direct execution

extension Shell {
    private static func runDirect(_ command: Command) async throws -> CommandOutput {
        var standardOutput = ""
        var standardError = ""
        for try await event in streamDirect(command) {
            switch event {
            case .output(let line):
                switch line.channel {
                case .standardOutput: standardOutput += line.text + "\n"
                case .standardError: standardError += line.text + "\n"
                }
            case .exit(let code):
                return CommandOutput(
                    standardOutput: standardOutput,
                    standardError: standardError,
                    exitCode: code
                )
            }
        }
        throw ShellError.launchFailed(command.executable)
    }

    private static func streamDirect(_ command: Command) -> AsyncThrowingStream<ProcessEvent, any Error> {
        AsyncThrowingStream { continuation in
            guard FileManager.default.isExecutableFile(atPath: command.executable) else {
                continuation.finish(throwing: ShellError.executableMissing(command.executable))
                return
            }

            let process = Process()
            let outPipe = Pipe()
            let errPipe = Pipe()

            process.executableURL = URL(filePath: command.executable)
            process.arguments = command.arguments
            process.environment = processEnvironment(command)
            if let directory = command.currentDirectory {
                process.currentDirectoryURL = URL(filePath: directory)
            }
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.standardInput = FileHandle.nullDevice

            let counter = LineCounter()
            let outReader = LineReader(channel: .standardOutput, counter: counter, continuation: continuation)
            let errReader = LineReader(channel: .standardError, counter: counter, continuation: continuation)
            outPipe.fileHandleForReading.readabilityHandler = { outReader.consume($0.availableData) }
            errPipe.fileHandleForReading.readabilityHandler = { errReader.consume($0.availableData) }

            process.terminationHandler = { finished in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                outReader.consume(outPipe.fileHandleForReading.availableData)
                errReader.consume(errPipe.fileHandleForReading.availableData)
                outReader.flush()
                errReader.flush()
                continuation.yield(.exit(finished.terminationStatus))
                continuation.finish()
            }

            continuation.onTermination = { reason in
                if case .cancelled = reason, process.isRunning { process.terminate() }
            }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: ShellError.launchFailed(error.localizedDescription))
            }
        }
    }
}

/// Shared across the two readers so line ids order stdout against stderr.
private final class LineCounter: Sendable {
    private let value = Mutex(0)

    func next() -> Int {
        value.withLock { current in
            current += 1
            return current
        }
    }
}

/// Splits pipe data into lines. `readabilityHandler` fires on a private queue,
/// so the partial-line buffer and the shared line counter are both locked.
private final class LineReader: Sendable {
    private let channel: OutputLine.Channel
    private let counter: LineCounter
    private let buffer = Mutex(Data())
    private let continuation: AsyncThrowingStream<ProcessEvent, any Error>.Continuation

    init(
        channel: OutputLine.Channel,
        counter: LineCounter,
        continuation: AsyncThrowingStream<ProcessEvent, any Error>.Continuation
    ) {
        self.channel = channel
        self.counter = counter
        self.continuation = continuation
    }

    func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        let completed: [Data] = buffer.withLock { pending in
            pending.append(data)
            var lines: [Data] = []
            while let newline = pending.firstIndex(of: 0x0A) {
                lines.append(Data(pending[pending.startIndex..<newline]))
                pending = Data(pending[pending.index(after: newline)...])
            }
            return lines
        }
        for line in completed { emit(line) }
    }

    func flush() {
        let remainder = buffer.withLock { pending -> Data in
            defer { pending = Data() }
            return pending
        }
        guard !remainder.isEmpty else { return }
        emit(remainder)
    }

    private func emit(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        continuation.yield(.output(OutputLine(id: counter.next(), channel: channel, text: text)))
    }
}

// MARK: - Administrator execution

extension Shell {
    private static let exitMarker = "__PORTS_EXIT__:"

    private static func appleScriptLiteral(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func osascript(shellLine: String) -> Command {
        let script = "do shell script \(appleScriptLiteral(shellLine)) with administrator privileges"
        return Command(executable: "/usr/bin/osascript", arguments: ["-e", script])
    }

    private static func isCancellation(_ output: CommandOutput) -> Bool {
        output.standardError.contains("User canceled") || output.standardError.contains("-128")
    }

    private static func runElevated(_ command: Command) async throws -> CommandOutput {
        let wrapped = "{ \(command.shellLine) ; } 2>&1; printf '\\n\(exitMarker)%d' \"$?\""
        let output = try await runDirect(osascript(shellLine: wrapped))
        if !output.succeeded {
            if isCancellation(output) { throw ShellError.authorizationDenied }
            throw ShellError.nonZeroExit(code: output.exitCode, standardError: output.standardError)
        }
        let (text, code) = splitExitMarker(output.standardOutput)
        return CommandOutput(standardOutput: text, standardError: "", exitCode: code)
    }

    private static func splitExitMarker(_ text: String) -> (String, Int32) {
        guard let range = text.range(of: exitMarker, options: .backwards) else { return (text, 0) }
        let code = Int32(text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        var body = String(text[text.startIndex..<range.lowerBound])
        if body.hasSuffix("\n") { body.removeLast() }
        return (body, code)
    }

    /// `do shell script` withholds output until the command finishes, so elevated
    /// output goes to a spool file that is followed while the command runs.
    private static func streamElevated(_ command: Command) -> AsyncThrowingStream<ProcessEvent, any Error> {
        AsyncThrowingStream { continuation in
            let spool = URL(filePath: NSTemporaryDirectory())
                .appending(path: "ports-\(UUID().uuidString).log")
            FileManager.default.createFile(atPath: spool.path(percentEncoded: false), contents: nil)
            let quoted = Command.quote(spool.path(percentEncoded: false))
            let wrapped = "{ \(command.shellLine) ; } > \(quoted) 2>&1"
            let follower = SpoolFollower(url: spool, continuation: continuation)

            let task = Task {
                let pump = Task { await follower.run() }
                defer { try? FileManager.default.removeItem(at: spool) }
                do {
                    let output = try await runDirect(osascript(shellLine: wrapped))
                    pump.cancel()
                    _ = await pump.value
                    follower.drain()
                    if !output.succeeded, isCancellation(output) {
                        continuation.finish(throwing: ShellError.authorizationDenied)
                        return
                    }
                    continuation.yield(.exit(output.exitCode))
                    continuation.finish()
                } catch {
                    pump.cancel()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { reason in
                if case .cancelled = reason { task.cancel() }
            }
        }
    }
}

private final class SpoolFollower: Sendable {
    private struct State {
        var offset: UInt64 = 0
        var counter = 0
        var pending = Data()
    }

    private let url: URL
    private let state = Mutex(State())
    private let continuation: AsyncThrowingStream<ProcessEvent, any Error>.Continuation

    init(url: URL, continuation: AsyncThrowingStream<ProcessEvent, any Error>.Continuation) {
        self.url = url
        self.continuation = continuation
    }

    func run() async {
        while !Task.isCancelled {
            drain()
            try? await Task.sleep(for: .milliseconds(120))
        }
    }

    func drain() {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let lines: [(Int, String)] = state.withLock { state in
            try? handle.seek(toOffset: state.offset)
            let data = (try? handle.readToEnd()) ?? Data()
            guard !data.isEmpty else { return [] }
            state.offset += UInt64(data.count)
            state.pending.append(data)
            var emitted: [(Int, String)] = []
            while let newline = state.pending.firstIndex(of: 0x0A) {
                let line = Data(state.pending[state.pending.startIndex..<newline])
                state.pending = Data(state.pending[state.pending.index(after: newline)...])
                state.counter += 1
                emitted.append((state.counter, String(decoding: line, as: UTF8.self)))
            }
            return emitted
        }
        for (id, text) in lines {
            continuation.yield(.output(OutputLine(id: id, channel: .standardOutput, text: text)))
        }
    }
}
