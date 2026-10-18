import Synchronization
import SwiftyTerminal

/// A ``Terminal`` that replays scripted input and records everything written, for testing
/// prompts and progress output without a real TTY.
///
/// Input is consumed in order. A read whose kind does not match the next scripted input (a
/// key press when a line was scripted, say) returns nil like end of input and is recorded in
/// ``unexpectedReads``, so tests can assert the prompt read the way they expected.
///
/// ```swift
/// let terminal = ScriptedTerminal(.key(.down), .key(.enter))
/// let choice = Prompter(terminal: terminal).choose("Platform", options: ["iOS", "Android"], default: 0)
/// #expect(choice == 1)
/// #expect(terminal.remainingInput.isEmpty)
/// ```
public final class ScriptedTerminal: Terminal {
    /// One scripted user action.
    public enum Input: Sendable, Equatable {
        /// A line typed and submitted with Enter.
        case line(String)
        /// A single key press.
        case key(Key)
        /// A line typed at a hidden-input prompt.
        case secret(String)
    }

    private struct State {
        var input: [Input]
        var output: [TerminalStream: String] = [:]
        var unexpectedReads: [String] = []
    }

    public let environment: TerminalEnvironment
    public let size: TerminalSize
    private let state: Mutex<State>

    /// Creates a terminal that replays `input`.
    ///
    /// The default environment is a fully interactive, uncolored, UTF-8 terminal: menus and
    /// single-key prompts are used and output has no style escapes.
    public init(
        input: [Input],
        environment: TerminalEnvironment = ScriptedTerminal.interactive,
        size: TerminalSize = TerminalSize(columns: 80, rows: 24)
    ) {
        self.environment = environment
        self.size = size
        self.state = Mutex(State(input: input))
    }

    /// Creates a terminal that replays `input`.
    public convenience init(_ input: Input...) {
        self.init(input: input)
    }

    /// Every stream is a terminal; `NO_COLOR` is set so assertions can match plain text.
    public static let interactive = TerminalEnvironment(
        variables: ["TERM": "xterm-256color", "LANG": "en_US.UTF-8", "NO_COLOR": "1"],
        isInputTerminal: true,
        isOutputTerminal: true,
        isErrorTerminal: true
    )

    /// No stream is a terminal, as when input and output are redirected.
    public static let redirected = TerminalEnvironment(variables: ["LANG": "en_US.UTF-8"])

    /// Input not yet consumed.
    public var remainingInput: [Input] {
        state.withLock { $0.input }
    }

    /// Reads that did not match the next scripted input.
    public var unexpectedReads: [String] {
        state.withLock { $0.unexpectedReads }
    }

    /// Everything written to `stream`, escapes included.
    public func output(_ stream: TerminalStream = .standardOutput) -> String {
        state.withLock { $0.output[stream, default: ""] }
    }

    /// Everything written to `stream` with escape sequences removed.
    public func plainOutput(_ stream: TerminalStream = .standardOutput) -> String {
        TextMetrics.strippingEscapes(output(stream))
    }

    public func write(_ text: String, to stream: TerminalStream) {
        state.withLock { $0.output[stream, default: ""] += text }
    }

    public func readLine() -> String? {
        next("line") { input in
            if case .line(let text) = input { return text }
            return nil
        }
    }

    public func readKey() -> Key? {
        guard environment.isInputTerminal else { return nil }
        return next("key") { input in
            if case .key(let key) = input { return key }
            return nil
        }
    }

    public func readSecret() -> String? {
        next("secret") { input in
            if case .secret(let text) = input { return text }
            return nil
        }
    }

    private func next<Value>(_ kind: String, _ extract: (Input) -> Value?) -> Value? {
        state.withLock { state in
            guard let input = state.input.first else { return nil }
            guard let value = extract(input) else {
                state.unexpectedReads.append("\(kind) requested, \(input) scripted")
                return nil
            }
            state.input.removeFirst()
            return value
        }
    }
}
