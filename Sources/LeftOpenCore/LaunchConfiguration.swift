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
    static let sources = [".claude/launch.json"]

    /// Commands from every supported launch file under `root`; malformed files and entries are skipped.
    public static func commands(projectRoot root: String) -> [LaunchCommand] {
        sources.flatMap { source -> [LaunchCommand] in
            let path = (root as NSString).appendingPathComponent(source)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  (attributes[.type] as? FileAttributeType) == .typeRegular,
                  (attributes[.size] as? Int ?? .max) <= maxFileBytes,
                  let data = FileManager.default.contents(atPath: path) else { return [] }
            return parse(data, source: source)
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
