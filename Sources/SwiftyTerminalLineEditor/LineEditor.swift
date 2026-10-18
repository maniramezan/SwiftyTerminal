import CSwiftyTerminalLineEditor
import Synchronization

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
/// On Linux it always falls back to plain line
/// reading without history or completion. All editors share a process-wide lock: reading a
/// line excludes history and completion changes until the read finishes.
public struct LineEditor: Sendable {
    private static let access = Mutex(())
    /// Where history is loaded from and saved to, if anywhere.
    public let historyPath: String?

    /// Creates an editor that loads and saves history at `historyPath`, if given.
    ///
    /// - Parameters:
    ///   - historyPath: The file used to persist history, or nil to keep history only in memory.
    public init(historyPath: String? = nil) {
        self.historyPath = historyPath
    }

    /// Adds the history saved at ``historyPath`` to this session.
    public func loadHistory() {
        if let historyPath {
            Self.access.withLock { _ in st_le_load_history(historyPath) }
        }
    }

    /// Shows `prompt` and reads one edited line, or nil at end of input. Non-empty lines are
    /// added to history. Blocks the calling thread.
    ///
    /// - Parameters:
    ///   - prompt: The question or input prefix displayed before reading an answer.
    public func readLine(prompt: String) -> String? {
        Self.access.withLock { _ in
            guard let pointer = st_le_readline(prompt) else { return nil }
            defer { free(pointer) }
            return String(cString: pointer)
        }
    }

    /// Writes the session history to ``historyPath``.
    public func saveHistory() {
        if let historyPath {
            Self.access.withLock { _ in st_le_save_history(historyPath) }
        }
    }

    /// Replaces tab completions: `commands` complete the first word, and `arguments[command]`
    /// complete later words after that command. Prefix matches are offered first, then
    /// substring matches.
    ///
    /// - Parameters:
    ///   - commands: Completion candidates for the first word of the input line.
    ///   - arguments: Argument completion candidates keyed by their first command word.
    public func setCompletions(commands: [String], arguments: [String: [String]] = [:]) {
        Self.access.withLock { _ in
            st_le_reset_completions()
            st_le_set_root_completions(commands.joined(separator: "\n"))
            for (command, values) in arguments {
                st_le_set_command_completions(command, values.joined(separator: "\n"))
            }
        }
    }

    /// Whether `candidate` completes `text`: a prefix match, or with `preferPrefix` false, a
    /// substring match.
    ///
    /// - Parameters:
    ///   - candidate: A possible completion to match against the typed text.
    ///   - text: The text typed so far at the completion point.
    ///   - preferPrefix: Whether to accept only prefixes instead of also allowing substring matches.
    public static func completionMatches(_ candidate: String, text: String, preferPrefix: Bool) -> Bool {
        st_le_completion_candidate_matches(candidate, text, preferPrefix ? 1 : 0) != 0
    }
}
