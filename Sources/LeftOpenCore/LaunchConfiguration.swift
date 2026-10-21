import Foundation

/// A start command a project declares for coding agents, such as `.claude/launch.json`.
/// It is project-authored data: it is parsed strictly and only ever run without a shell.
public struct LaunchCommand: Sendable, Equatable {
    public let name: String
    public let executable: String
    public let arguments: [String]
    public let port: Int?
    public let source: String
}

public enum LaunchConfiguration {
    static let maxFileBytes = 64 * 1024
    static let maxArguments = 64
    static let maxEntries = 32

    /// A launch file format. Support for another agent's file (for example a future OpenAI/Codex one)
    /// is one more entry here, with a parser that returns the same `LaunchCommand` values.
    struct Source: Sendable {
        let path: String
        let parse: @Sendable (Data) -> [LaunchCommand]
    }
    static let sources = [Source(path: ".claude/launch.json") { parse($0, source: ".claude/launch.json") }]

    /// Commands from every supported launch file under `root`; malformed files and entries are skipped.
    public static func commands(projectRoot root: String) -> [LaunchCommand] {
        sources.flatMap { source -> [LaunchCommand] in
            let path = (root as NSString).appendingPathComponent(source.path)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  (attributes[.type] as? FileAttributeType) == .typeRegular,
                  (attributes[.size] as? Int ?? .max) <= maxFileBytes,
                  let data = FileManager.default.contents(atPath: path) else { return [] }
            return source.parse(data)
        }
    }

    public static func parse(_ data: Data, source: String = ".claude/launch.json") -> [LaunchCommand] {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = object["configurations"] as? [[String: Any]] else { return [] }
        return entries.prefix(maxEntries).compactMap { entry in
            guard let name = entry["name"] as? String, !name.isEmpty, name.count <= 100,
                  let executable = entry["runtimeExecutable"] as? String, validExecutable(executable) else { return nil }
            let arguments = entry["runtimeArgs"] as? [Any] ?? []
            let strings = arguments.compactMap { $0 as? String }
            guard strings.count == arguments.count, strings.count <= maxArguments,
                  strings.allSatisfy({ !$0.contains("\0") }) else { return nil }
            var port: Int?
            if let value = entry["port"] {
                guard let number = value as? Int, Portless.validAppPort(number) else { return nil }
                port = number
            }
            return LaunchCommand(name: name, executable: executable, arguments: strings, port: port, source: source)
        }
    }

    /// The command for a saved address: the one declaring the service's port, else the only entry.
    public static func command(in commands: [LaunchCommand], preferredPort: Int) -> LaunchCommand? {
        let byPort = commands.filter { $0.port == preferredPort }
        if byPort.count == 1 { return byPort[0] }
        if byPort.isEmpty, commands.count == 1 { return commands[0] }
        return nil
    }

    /// No shell is involved, so only a bare program name or a path is allowed. A leading dash could
    /// be read as a Portless flag.
    static func validExecutable(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 1024 && !value.hasPrefix("-")
            && !value.contains(where: { $0 == "\0" || $0.isNewline })
    }
}

extension Portless {
    static func validAppPort(_ port: Int) -> Bool { (1...65535).contains(port) }
}

/// Text a user pastes into their coding agent so it writes the launch file LeftOpen reads.
public enum LaunchSetupPrompt {
    public static func text(projectRoot: String, port: Int?) -> String {
        let portLine = port.map { L("It was last seen listening on port \($0).", "它上次监听的端口是 \($0)。") } ?? ""
        let example = """
        {
          "version": "0.0.1",
          "configurations": [
            {
              "name": "web",
              "runtimeExecutable": "npm",
              "runtimeArgs": ["run", "dev", "--", "--port", "5173", "--strictPort"],
              "port": 5173
            }
          ]
        }
        """
        return L("""
        LeftOpen could not find how to start the web server of the project at \(projectRoot). \(portLine)

        Find the command that starts this project's local web server (check package.json scripts, Makefile, README, pyproject.toml, scripts/), then create `.claude/launch.json` in the project root. Do not start the server and do not change any other file.

        Format:
        \(example)

        Rules:
        - "runtimeExecutable" is one program name or path, never a shell string. Put every argument in "runtimeArgs" as separate strings. No `&&`, `|`, `;`, `cd` or `VAR=value` prefixes; if the server needs them, wrap them in a project script and run that script.
        - "port" is the port the server listens on. Pin it with the framework's own flag so it stays fixed (for example --port and --strictPort).
        - One entry per server, using the "name" of the app. Use relative paths only inside the project.
        - Commands run from the project root.
        """, """
        LeftOpen 无法确定位于 \(projectRoot) 的项目该如何启动 Web 服务。\(portLine)

        请找出启动此项目本地 Web 服务的命令（查看 package.json 的 scripts、Makefile、README、pyproject.toml、scripts/），然后在项目根目录创建 `.claude/launch.json`。不要启动服务，也不要修改其他文件。

        格式：
        \(example)

        规则：
        - "runtimeExecutable" 只能是一个程序名或路径，不能是 shell 字符串。每个参数单独放进 "runtimeArgs"。不要使用 `&&`、`|`、`;`、`cd` 或 `VAR=value` 前缀；如果需要，请先写成项目脚本再运行该脚本。
        - "port" 是服务监听的端口。请用框架自己的参数固定端口（例如 --port 和 --strictPort）。
        - 每个服务一个条目，"name" 用应用名称。项目内只使用相对路径。
        - 命令从项目根目录运行。
        """)
    }
}
