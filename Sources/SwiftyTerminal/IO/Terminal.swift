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
    /// Writes `text` to `stream` immediately.
    func write(_ text: String, to stream: TerminalStream)
    /// Reads one line without its terminator, or nil at end of input.
    func readLine() -> String?
    /// Reads one key press in raw mode, or nil when stdin is not a terminal.
    func readKey() -> Key?
    /// Reads one line without echoing it, or nil at end of input.
    func readSecret() -> String?
    /// Runs `body` with stdin held in raw mode, so key presses that arrive while output is being
    /// drawn are neither echoed nor turned into signals. Calls nest.
    func withRawInput<T>(_ body: () throws -> T) rethrows -> T
}

extension Terminal {
    /// Runs `body` unchanged; terminals without a raw mode need nothing more.
    public func withRawInput<T>(_ body: () throws -> T) rethrows -> T {
        try body()
    }

    /// Writes `text` to stdout.
    public func write(_ text: String) {
        write(text, to: .standardOutput)
    }

    /// Writes `text` followed by a newline to `stream`.
    public func writeLine(_ text: String = "", to stream: TerminalStream = .standardOutput) {
        write(text + "\n", to: stream)
    }
}

/// The process's stdin, stdout and stderr.
///
/// stdout goes through the C stdio buffer, so it stays ordered with the host's `print` calls.
public struct StandardTerminal: Terminal {
    public let environment: TerminalEnvironment

    /// Creates a terminal over the standard streams, by default with the process environment.
    public init(environment: TerminalEnvironment = .current()) {
        self.environment = environment
    }

    public var size: TerminalSize {
        TerminalSize(columns: Int(st_terminal_columns()), rows: Int(st_terminal_rows()))
    }

    public func write(_ text: String, to stream: TerminalStream) {
        switch stream {
        case .standardOutput: st_write_stdout(text)
        case .standardError: st_write_stderr(text)
        }
    }

    public func readLine() -> String? {
        Swift.readLine()
    }

    public func readKey() -> Key? {
        var buffer = [UInt8](repeating: 0, count: 16)
        let count = Int(st_read_key(&buffer, Int32(buffer.count)))
        if count < 0 { return nil }
        return Key(bytes: Array(buffer.prefix(count)))
    }

    public func withRawInput<T>(_ body: () throws -> T) rethrows -> T {
        let entered = st_raw_enter() != 0
        defer {
            if entered { st_raw_exit() }
        }
        return try body()
    }

    public func readSecret() -> String? {
        guard let pointer = st_read_secret_line() else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    /// Line-buffers stdout so partial lines from `print(_:terminator:)` appear without a flush.
    public static func lineBufferStandardOutput() {
        st_line_buffer_stdout()
    }
}
