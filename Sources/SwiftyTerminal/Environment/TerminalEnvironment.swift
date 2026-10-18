import CSwiftyTerminal
import Foundation

/// One of the process's standard streams.
public enum TerminalStream: Sendable, Hashable {
    /// The standard output stream (stdout).
    case standardOutput
    /// The standard error stream (stderr).
    case standardError
}

/// Whether to emit ANSI styling, typically bound to a `--color` flag.
public enum ColorMode: String, Sendable, CaseIterable {
    /// Style only when the stream is a terminal and the environment does not opt out.
    case auto
    /// Always style, even when output is redirected.
    case always
    /// Never style.
    case never
}

/// What the current process can do with its terminal: which streams are interactive and
/// which environment variables shape color and Unicode output.
///
/// Every decision is a pure function of the stored values, so tests construct one directly
/// instead of depending on how the test runner was launched.
public struct TerminalEnvironment: Sendable, Equatable {
    /// Environment variables consulted for color, Unicode and terminal type.
    public var variables: [String: String]
    /// Whether stdin is a terminal.
    public var isInputTerminal: Bool
    /// Whether stdout is a terminal.
    public var isOutputTerminal: Bool
    /// Whether stderr is a terminal.
    public var isErrorTerminal: Bool

    /// Creates an environment from explicit values.
    ///
    /// - Parameters:
    ///   - variables: Environment variables consulted for terminal type, color, and locale.
    ///   - isInputTerminal: Whether stdin is attached to a terminal.
    ///   - isOutputTerminal: Whether stdout is attached to a terminal.
    ///   - isErrorTerminal: Whether stderr is attached to a terminal.
    public init(
        variables: [String: String] = [:],
        isInputTerminal: Bool = false,
        isOutputTerminal: Bool = false,
        isErrorTerminal: Bool = false
    ) {
        self.variables = variables
        self.isInputTerminal = isInputTerminal
        self.isOutputTerminal = isOutputTerminal
        self.isErrorTerminal = isErrorTerminal
    }

    /// The environment of the running process.
    public static func current() -> TerminalEnvironment {
        TerminalEnvironment(
            variables: ProcessInfo.processInfo.environment,
            isInputTerminal: st_isatty(STDIN_FILENO) != 0,
            isOutputTerminal: st_isatty(STDOUT_FILENO) != 0,
            isErrorTerminal: st_isatty(STDERR_FILENO) != 0
        )
    }

    /// Whether `stream` is attached to a terminal.
    ///
    /// - Parameters:
    ///   - stream: The standard stream whose capabilities or output to use.
    public func isTerminal(_ stream: TerminalStream) -> Bool {
        switch stream {
        case .standardOutput: isOutputTerminal
        case .standardError: isErrorTerminal
        }
    }

    /// `TERM=dumb`: the terminal cannot move the cursor or render styles.
    public var isDumb: Bool {
        variables["TERM"]?.lowercased() == "dumb"
    }

    /// Whether ANSI styling should be written to `stream`.
    ///
    /// In ``ColorMode/auto``, a non-empty `NO_COLOR` disables color, then a non-empty
    /// `FORCE_COLOR` (other than `0` or `false`) enables it, then `TERM=dumb` disables it, and
    /// otherwise color follows whether the stream is a terminal.
    ///
    /// - Parameters:
    ///   - stream: The standard stream whose capabilities or output to use.
    ///   - mode: The requested color policy.
    public func isColorEnabled(for stream: TerminalStream, mode: ColorMode = .auto) -> Bool {
        switch mode {
        case .always:
            return true
        case .never:
            return false
        case .auto:
            if let noColor = variables["NO_COLOR"], !noColor.isEmpty {
                return false
            }
            if let force = variables["FORCE_COLOR"]?.lowercased(), !force.isEmpty, force != "0", force != "false" {
                return true
            }
            return !isDumb && isTerminal(stream)
        }
    }

    /// Whether the locale advertises UTF-8, so box-drawing characters and Braille spinner
    /// frames render instead of falling back to ASCII.
    public var supportsUnicode: Bool {
        guard !isDumb else { return false }
        let locale =
            [variables["LC_ALL"], variables["LC_CTYPE"], variables["LANG"]]
            .compactMap { $0?.uppercased() }.first { !$0.isEmpty } ?? ""
        return locale.contains("UTF-8") || locale.contains("UTF8")
    }

    /// Whether `stream` can host redrawn content (spinners, arrow-key menus): it is a terminal
    /// that understands cursor movement.
    ///
    /// - Parameters:
    ///   - stream: The standard stream whose capabilities or output to use.
    public func supportsCursorControl(on stream: TerminalStream) -> Bool {
        isTerminal(stream) && !isDumb
    }

    /// Whether arrow-key selection menus can be shown: stdin and stdout are both terminals that
    /// understand cursor movement.
    public var supportsInteractiveSelection: Bool {
        isInputTerminal && supportsCursorControl(on: .standardOutput)
    }
}
