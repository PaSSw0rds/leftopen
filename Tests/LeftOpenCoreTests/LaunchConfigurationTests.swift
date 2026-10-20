import XCTest
@testable import LeftOpenCore

final class LaunchConfigurationTests: XCTestCase {
    private func parse(_ json: String) -> [LaunchCommand] { LaunchConfiguration.parse(Data(json.utf8)) }

    func testParsesClaudeLaunchConfigurations() {
        let commands = parse("""
        {"version":"0.0.1","configurations":[
          {"name":"ui-dev","runtimeExecutable":"npm","runtimeArgs":["--prefix","ui","run","dev"],"port":5173},
          {"name":"dashboard","runtimeExecutable":"uv","runtimeArgs":["run","token-flow","dashboard"],"port":19527}]}
        """)
        XCTAssertEqual(commands.map(\.name), ["ui-dev", "dashboard"])
        XCTAssertEqual(commands[0].executable, "npm")
        XCTAssertEqual(commands[0].arguments, ["--prefix", "ui", "run", "dev"])
        XCTAssertEqual(commands[1].port, 19527)
    }

    func testSkipsInvalidEntriesWithoutRejectingTheFile() {
        let commands = parse("""
        {"configurations":[
          {"name":"flag","runtimeExecutable":"--force","port":3000},
          {"name":"bad-args","runtimeExecutable":"npm","runtimeArgs":["run",1]},
          {"name":"bad-port","runtimeExecutable":"npm","port":70000},
          {"name":"string-port","runtimeExecutable":"npm","port":"3000"},
          {"runtimeExecutable":"npm"},
          {"name":"ok","runtimeExecutable":"npm","runtimeArgs":["start"]}]}
        """)
        XCTAssertEqual(commands.map(\.name), ["ok"])
        XCTAssertNil(commands[0].port)
        XCTAssertTrue(parse("not json").isEmpty)
        XCTAssertTrue(parse(#"{"configurations":"x"}"#).isEmpty)
    }

    func testChoosesCommandByPortOrSoleEntry() {
        func command(_ name: String, _ port: Int?) -> LaunchCommand {
            LaunchCommand(name: name, executable: "npm", arguments: [], port: port, source: "")
        }
        let two = [command("a", 3000), command("b", 4000)]
        XCTAssertEqual(LaunchConfiguration.command(in: two, preferredPort: 4000)?.name, "b")
        XCTAssertNil(LaunchConfiguration.command(in: two, preferredPort: 5000))
        XCTAssertEqual(LaunchConfiguration.command(in: [command("only", nil)], preferredPort: 5000)?.name, "only")
        XCTAssertNil(LaunchConfiguration.command(in: [command("x", 3000), command("y", 3000)], preferredPort: 3000))
    }

    func testReadsFileFromProjectAndIgnoresOversizedOrMissing() throws {
        let root = NSTemporaryDirectory() + "leftopen-launch-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root + "/.claude", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        XCTAssertTrue(LaunchConfiguration.commands(projectRoot: root).isEmpty)
        let file = root + "/.claude/launch.json"
        try #"{"configurations":[{"name":"web","runtimeExecutable":"python3","runtimeArgs":["-m","http.server","8000"],"port":8000}]}"#
            .write(toFile: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(LaunchConfiguration.commands(projectRoot: root).first?.name, "web")
        try String(repeating: " ", count: LaunchConfiguration.maxFileBytes + 1).write(toFile: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(LaunchConfiguration.commands(projectRoot: root).isEmpty)
    }
}
