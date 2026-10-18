/// A terminal conversation. Every question returns nil when the user cancels (Esc, Ctrl-C in a
/// menu, Ctrl-D) or input ends, which callers treat as "the user walked away".
///
/// ``Prompter`` is the terminal implementation; conform a fake to drive command logic in tests,
/// or use ``Prompter`` with `SwiftyTerminalTesting.ScriptedTerminal` to test the prompts themselves.
public protocol Prompting {
    /// Prints a status or section line.
    ///
    /// - Parameters:
    ///   - text: The text to display.
    func say(_ text: String)
    /// Asks for free text. Enter keeps `defaultValue`; `validate` returns an error message to
    /// ask again, or nil to accept.
    ///
    /// - Parameters:
    ///   - prompt: The question or input prefix displayed before reading an answer.
    ///   - defaultValue: The text accepted when the user submits an empty line.
    ///   - validate: Returns an error message to retry the question, or nil to accept the answer.
    func ask(_ prompt: String, default defaultValue: String?, validate: ((String) -> String?)?) -> String?
    /// Asks for text without echoing it (passwords, keys).
    ///
    /// - Parameters:
    ///   - prompt: The question or input prefix displayed before reading an answer.
    func askSecret(_ prompt: String) -> String?
    /// Asks a yes/no question; one key press on a terminal, Enter keeps `defaultAnswer`.
    ///
    /// - Parameters:
    ///   - prompt: The question or input prefix displayed before reading an answer.
    ///   - defaultAnswer: The answer accepted when Enter is pressed.
    func confirm(_ prompt: String, default defaultAnswer: Bool) -> Bool?
    /// Asks for one key out of `keys` (case-insensitive), e.g. `[r]etry / [s]kip / [a]bort`.
    /// Enter keeps `defaultKey`. Returns the matching element of `keys`.
    ///
    /// - Parameters:
    ///   - prompt: The question or input prefix displayed before reading an answer.
    ///   - keys: Allowed answer keys, matched case-insensitively.
    ///   - defaultKey: The key accepted on Enter; matched case-insensitively against the allowed keys.
    func askKey(_ prompt: String, keys: [Character], default defaultKey: Character?) -> Character?
    /// Asks for one option (a radio-button menu on a terminal, a numbered list otherwise).
    ///
    /// - Parameters:
    ///   - prompt: The question or input prefix displayed before reading an answer.
    ///   - options: The choices in their original display order.
    ///   - index: The initially focused zero-based option index; invalid values select the first option.
    func choose(_ prompt: String, options: [String], default index: Int) -> Int?
    /// Asks for one or more options (a checkbox menu on a terminal, `1,3` / `2-4` / `all`
    /// otherwise). Returns sorted indexes.
    ///
    /// - Parameters:
    ///   - prompt: The question or input prefix displayed before reading an answer.
    ///   - options: The choices in their original display order.
    ///   - defaults: Options initially selected. Invalid values are ignored and duplicates are removed.
    func chooseMany(_ prompt: String, options: [String], defaults: [Int]) -> [Int]?
}

extension Prompting {
    /// Asks for free text with no validation.
    ///
    /// - Parameters:
    ///   - prompt: The question or input prefix displayed before reading an answer.
    ///   - defaultValue: The text accepted when the user submits an empty line.
    public func ask(_ prompt: String, default defaultValue: String? = nil) -> String? {
        ask(prompt, default: defaultValue, validate: nil)
    }

    /// Asks for one of `options`, returning the option itself.
    ///
    /// - Parameters:
    ///   - prompt: The question or input prefix displayed before reading an answer.
    ///   - options: The choices in their original display order.
    ///   - defaultOption: The option initially focused, or the first option when nil or absent.
    public func choose<Option: CustomStringConvertible & Equatable>(
        _ prompt: String,
        from options: [Option],
        default defaultOption: Option? = nil
    ) -> Option? {
        let index = defaultOption.flatMap { options.firstIndex(of: $0) } ?? 0
        return choose(prompt, options: options.map(\.description), default: index).map { options[$0] }
    }

    /// Asks for any of `options`, returning the chosen options in their original order.
    ///
    /// - Parameters:
    ///   - prompt: The question or input prefix displayed before reading an answer.
    ///   - options: The choices in their original display order.
    ///   - defaults: Options initially selected. Invalid values are ignored and duplicates are removed.
    public func chooseMany<Option: CustomStringConvertible & Equatable>(
        _ prompt: String,
        from options: [Option],
        defaults: [Option] = []
    ) -> [Option]? {
        let defaultIndexes = defaults.compactMap { options.firstIndex(of: $0) }
        return chooseMany(prompt, options: options.map(\.description), defaults: defaultIndexes)?.map { options[$0] }
    }
}
