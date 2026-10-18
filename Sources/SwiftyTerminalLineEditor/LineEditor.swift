import CSwiftyTerminalLineEditor

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Reads REPL input with line editing (arrows, Ctrl-A/E/K/U/W, Alt-Backspace), history and tab
/// completion through libedit.
///
/// Where libedit is unavailable (Linux without libedit headers) it falls back to plain line
/// reading without history or completion. libedit keeps process-wide state, so use one editor
/// at a time.
public struct LineEditor: Sendable {
    /// Where history is loaded from and saved to, if anywhere.
    public let historyPath: String?

    /// Creates an editor, loading history from `historyPath` when given.
    public init(historyPath: String? = nil) {
        self.historyPath = historyPath
        if let historyPath {
            st_le_load_history(historyPath)
        }
    }

    /// Shows `prompt` and reads one edited line, or nil at end of input. Non-empty lines are
    /// added to history. Blocks the calling thread.
    public func readLine(prompt: String) -> String? {
        guard let pointer = st_le_readline(prompt) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    /// Writes the session history to ``historyPath``.
    public func saveHistory() {
        if let historyPath {
            st_le_save_history(historyPath)
        }
    }

    /// Replaces tab completions: `commands` complete the first word, and `arguments[command]`
    /// complete later words after that command. Prefix matches are offered first, then
    /// substring matches.
    public func setCompletions(commands: [String], arguments: [String: [String]] = [:]) {
        st_le_reset_completions()
        st_le_set_root_completions(commands.joined(separator: "\n"))
        for (command, values) in arguments {
            st_le_set_command_completions(command, values.joined(separator: "\n"))
        }
    }

    /// Whether `candidate` completes `text`: a prefix match, or with `preferPrefix` false, a
    /// substring match.
    public static func completionMatches(_ candidate: String, text: String, preferPrefix: Bool) -> Bool {
        st_le_completion_candidate_matches(candidate, text, preferPrefix ? 1 : 0) != 0
    }
}
