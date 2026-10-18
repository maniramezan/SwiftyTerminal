import CSwiftyTerminal
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Terminal dimensions in character cells.
public struct TerminalSize: Sendable, Equatable {
    /// Width in columns.
    public var columns: Int
    /// Height in rows.
    public var rows: Int

    /// Creates a size.
    ///
    /// - Parameters:
    ///   - columns: Width in terminal character cells.
    ///   - rows: Height in terminal character cells.
    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }
}

/// The input and output a prompt or progress indicator talks to.
///
/// ``StandardTerminal`` is the real process terminal; `SwiftyTerminalTesting.ScriptedTerminal`
/// replays scripted input and records output for tests.
public protocol Terminal: Sendable {
    /// Which streams are terminals and which environment variables apply.
    var environment: TerminalEnvironment { get }
    /// Current dimensions.
    var size: TerminalSize { get }
    /// Dimensions of the terminal attached to `stream`.
    ///
    /// - Parameters:
    ///   - stream: The standard stream whose capabilities or output to use.
    func size(for stream: TerminalStream) -> TerminalSize
    /// Writes `text` to `stream` immediately.
    ///
    /// - Parameters:
    ///   - text: The text to write to the selected stream.
    ///   - stream: The standard stream whose capabilities or output to use.
    func write(_ text: String, to stream: TerminalStream)
    /// Reads one line without its terminator, or nil at end of input.
    func readLine() -> String?
    /// Reads one key press in raw mode, or nil when stdin is not a terminal.
    func readKey() -> Key?
    /// Reads one line without echoing it, or nil at end of input.
    func readSecret() -> String?
    /// Writes `prompt` to `stream` after disabling echo, then reads a secret line.
    ///
    /// - Parameters:
    ///   - prompt: The question or input prefix displayed before reading an answer.
    ///   - stream: The standard stream whose capabilities or output to use.
    func readSecret(after prompt: String, to stream: TerminalStream) -> String?
    /// Runs `body` with stdin held in raw mode, so key presses that arrive while output is being
    /// drawn are neither echoed nor turned into signals. Calls nest.
    ///
    /// - Parameters:
    ///   - body: Synchronous work to perform while raw input is held; errors are rethrown after restoration.
    func withRawInput<T>(_ body: () throws -> T) rethrows -> T
}

extension Terminal {
    /// Writes the prompt and delegates to ``readSecret()``. Real terminals can disable echo
    /// before writing the prompt to avoid exposing fast input.
    ///
    /// - Parameters:
    ///   - prompt: The question or input prefix displayed before reading an answer.
    ///   - stream: The standard stream whose capabilities or output to use.
    public func readSecret(after prompt: String, to stream: TerminalStream) -> String? {
        write(prompt, to: stream)
        return readSecret()
    }

    /// Uses ``size`` when a terminal does not distinguish output streams.
    ///
    /// - Parameters:
    ///   - stream: The standard stream whose capabilities or output to use.
    public func size(for stream: TerminalStream) -> TerminalSize { size }

    /// Runs `body` unchanged; terminals without a raw mode need nothing more.
    ///
    /// - Parameters:
    ///   - body: Synchronous work to perform while raw input is held; errors are rethrown after restoration.
    public func withRawInput<T>(_ body: () throws -> T) rethrows -> T {
        try body()
    }

    /// Writes `text` to stdout.
    ///
    /// - Parameters:
    ///   - text: The text to write to the selected stream.
    public func write(_ text: String) {
        write(text, to: .standardOutput)
    }

    /// Writes `text` followed by a newline to `stream`.
    ///
    /// - Parameters:
    ///   - text: The text to write to the selected stream.
    ///   - stream: The standard stream whose capabilities or output to use.
    public func writeLine(_ text: String = "", to stream: TerminalStream = .standardOutput) {
        write(text + "\n", to: stream)
    }
}

/// The process's stdin, stdout and stderr.
///
/// stdout goes through the C stdio buffer, so it stays ordered with the host's `print` calls.
public struct StandardTerminal: Terminal {
    /// Which streams are terminals and which environment variables apply.
    public let environment: TerminalEnvironment

    /// Creates a terminal over the standard streams, by default with the process environment.
    ///
    /// - Parameters:
    ///   - environment: Terminal capabilities and environment variables to use for rendering decisions.
    public init(environment: TerminalEnvironment = .current()) {
        self.environment = environment
    }

    /// Current dimensions.
    public var size: TerminalSize {
        TerminalSize(columns: Int(st_terminal_columns()), rows: Int(st_terminal_rows()))
    }

    /// Dimensions of the terminal attached to `stream`.
    ///
    /// - Parameters:
    ///   - stream: The standard stream whose capabilities or output to use.
    public func size(for stream: TerminalStream) -> TerminalSize {
        let descriptor = stream == .standardOutput ? STDOUT_FILENO : STDERR_FILENO
        return TerminalSize(
            columns: Int(st_terminal_columns_for(descriptor)),
            rows: Int(st_terminal_rows_for(descriptor))
        )
    }

    /// Writes `text` to `stream` immediately.
    ///
    /// - Parameters:
    ///   - text: The text to write to the selected stream.
    ///   - stream: The standard stream whose capabilities or output to use.
    public func write(_ text: String, to stream: TerminalStream) {
        switch stream {
        case .standardOutput: st_write_stdout(text)
        case .standardError: st_write_stderr(text)
        }
    }

    /// Reads one line without its terminator, or nil at end of input.
    public func readLine() -> String? {
        Swift.readLine()
    }

    /// Reads one key press in raw mode, or nil when stdin is not a terminal.
    public func readKey() -> Key? {
        var buffer = [UInt8](repeating: 0, count: 16)
        let count = Int(st_read_key(&buffer, Int32(buffer.count)))
        if count < 0 { return nil }
        return Key(bytes: Array(buffer.prefix(count)))
    }

    /// Runs `body` with stdin held in raw mode, so key presses that arrive while output is being
    /// drawn are neither echoed nor turned into signals. Calls nest.
    ///
    /// - Parameters:
    ///   - body: Synchronous work to perform while raw input is held; errors are rethrown after restoration.
    public func withRawInput<T>(_ body: () throws -> T) rethrows -> T {
        let entered = st_raw_enter() != 0
        defer {
            if entered { st_raw_exit() }
        }
        return try body()
    }

    /// Reads one line without echoing it, or nil at end of input.
    public func readSecret() -> String? {
        guard let pointer = st_read_secret_line() else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    /// Writes `prompt` to `stream` after disabling echo, then reads a secret line.
    ///
    /// - Parameters:
    ///   - prompt: The question or input prefix displayed before reading an answer.
    ///   - stream: The standard stream whose capabilities or output to use.
    public func readSecret(after prompt: String, to stream: TerminalStream) -> String? {
        let descriptor = stream == .standardOutput ? STDOUT_FILENO : STDERR_FILENO
        guard let pointer = st_read_secret_line_with_prompt(prompt, descriptor) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    /// Line-buffers stdout so complete lines are flushed on newline. Partial writes still
    /// require a flush; terminal writes made through this library flush immediately.
    public static func lineBufferStandardOutput() {
        st_line_buffer_stdout()
    }
}
