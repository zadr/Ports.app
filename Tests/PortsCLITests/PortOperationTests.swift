import Testing
import PortsShell
@testable import PortsCLI

@Suite("PortOperation.arguments")
struct OperationArgumentTests {
    let client = PortClient(
        environment: PortsEnvironment(
            executable: "/opt/local/bin/port",
            prefix: "/opt/local",
            version: "2.12.5",
            requiresAdministrator: true
        )
    )

    @Test("install appends variants after the name")
    func install() {
        let args = client.arguments(for: .install(name: "zlib", variants: ["+universal", "-x11"]))
        #expect(args == ["-N", "install", "zlib", "+universal", "-x11"])
    }

    @Test("uninstall, upgrade, and upgradeOutdated")
    func upgradeFamily() {
        #expect(client.arguments(for: .uninstall(name: "zlib", version: nil)) == ["-N", "uninstall", "zlib"])
        #expect(
            client.arguments(for: .uninstall(name: "zlib", version: "1.3.2_0+universal"))
                == ["-N", "uninstall", "zlib", "@1.3.2_0+universal"]
        )
        #expect(client.arguments(for: .upgrade(names: ["a", "b"])) == ["-N", "upgrade", "a", "b"])
        #expect(client.arguments(for: .upgradeOutdated) == ["-N", "upgrade", "outdated"])
    }

    @Test("activate carries an optional version, deactivate never does")
    func activateDeactivate() {
        #expect(client.arguments(for: .activate(name: "zlib", version: nil)) == ["-N", "activate", "zlib"])
        #expect(
            client.arguments(for: .activate(name: "zlib", version: "1.3.2_0"))
                == ["-N", "activate", "zlib", "@1.3.2_0"]
        )
        #expect(client.arguments(for: .deactivate(name: "zlib")) == ["-N", "deactivate", "zlib"])
    }

    @Test("clean, selfupdate, sync, reclaim")
    func maintenance() {
        #expect(client.arguments(for: .clean(name: "zlib")) == ["-N", "clean", "--all", "zlib"])
        #expect(client.arguments(for: .selfupdate) == ["-N", "selfupdate"])
        #expect(client.arguments(for: .sync) == ["-N", "sync"])
        #expect(client.arguments(for: .reclaim) == ["-N", "reclaim"])
    }

    @Test("reindex has no argument vector and custom passes arguments through verbatim")
    func reindexAndCustom() {
        #expect(client.arguments(for: .reindex(directory: "/tmp/tree")).isEmpty)
        #expect(client.arguments(for: .custom(arguments: ["info", "zlib"])) == ["info", "zlib"])
    }

    @Test("writesPrefix is false only for reindex and custom")
    func writesPrefixFlags() {
        #expect(PortOperation.install(name: "zlib", variants: []).writesPrefix)
        #expect(PortOperation.uninstall(name: "zlib", version: nil).writesPrefix)
        #expect(PortOperation.upgrade(names: []).writesPrefix)
        #expect(PortOperation.upgradeOutdated.writesPrefix)
        #expect(PortOperation.activate(name: "zlib", version: nil).writesPrefix)
        #expect(PortOperation.deactivate(name: "zlib").writesPrefix)
        #expect(PortOperation.clean(name: "zlib").writesPrefix)
        #expect(PortOperation.selfupdate.writesPrefix)
        #expect(PortOperation.sync.writesPrefix)
        #expect(PortOperation.reclaim.writesPrefix)
        #expect(!PortOperation.reindex(directory: "/tmp").writesPrefix)
        #expect(!PortOperation.custom(arguments: ["x"]).writesPrefix)
    }
}

@Suite("PortsEnvironment derived paths")
struct EnvironmentPathTests {
    @Test("portIndexBinary sits beside the port executable")
    func portIndexBinary() {
        let environment = PortsEnvironment(
            executable: "/opt/local/bin/port",
            prefix: "/opt/local",
            version: "2.12.5",
            requiresAdministrator: false
        )
        #expect(environment.portIndexBinary == "/opt/local/bin/portindex")
        #expect(environment.privilege == .direct)
    }

    @Test("requiresAdministrator maps to the administrator privilege")
    func privilegeMapping() {
        let environment = PortsEnvironment(
            executable: "/opt/local/bin/port",
            prefix: "/opt/local",
            version: "2.12.5",
            requiresAdministrator: true
        )
        #expect(environment.privilege == .administrator)
    }
}
