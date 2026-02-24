import Foundation

struct TerminalLauncher {
    enum TerminalKind: String, CaseIterable, Identifiable {
        case terminal
        case iterm
        case ghostty

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .terminal: return "Terminal"
            case .iterm: return "iTerm2"
            case .ghostty: return "Ghostty"
            }
        }
    }

    func open(kind: TerminalKind, path: String, windows: Int, command: String? = nil) throws {
        let count = max(1, min(5, windows))
        let script: String
        switch kind {
        case .terminal:
            script = terminalScript(path: path, count: count, command: command)
        case .iterm:
            script = iTermScript(path: path, count: count, command: command)
        case .ghostty:
            script = ghosttyScript(path: path, count: count, command: command)
        }
        try runAppleScript(script)
    }

    private func runAppleScript(_ script: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown AppleScript error"
            throw CoreClientError.commandFailed(errorOutput)
        }
    }

    private func terminalScript(path: String, count: Int, command: String?) -> String {
        let command = shellCommand(path: path, command: command)
        return """
        tell application \"Terminal\"
            activate
            repeat \(count)
                do script \"\(command)\"
            end repeat
        end tell
        """
    }

    private func iTermScript(path: String, count: Int, command: String?) -> String {
        let command = shellCommand(path: path, command: command)
        return """
        tell application \"iTerm2\"
            activate
            repeat \(count)
                create window with default profile
                tell current session of current window
                    write text \"\(command)\"
                end tell
            end repeat
        end tell
        """
    }

    private func ghosttyScript(path: String, count: Int, command: String?) -> String {
        let escapedPath = shellEscape(path)
        var extra = ""
        if let command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let custom = "cd \(shellEscape(path)) && \(command)"
            let payload = shellEscape(custom)
            extra = " --command \(payload)"
        }
        return """
        repeat \(count)
            do shell script \"open -na Ghostty --args --working-directory=\(escapedPath)\(extra)\"
        end repeat
        """
    }

    private func shellCommand(path: String, command: String?) -> String {
        let base = "cd \(shellEscape(path))"
        if let command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(base) && \(appleScriptEscape(command))"
        }
        return "\(base) && exec $SHELL -l"
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
