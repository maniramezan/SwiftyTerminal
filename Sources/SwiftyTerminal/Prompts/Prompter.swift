import Foundation

/// Asks questions on a ``Terminal``.
///
/// On an interactive terminal, yes/no and short numbered choices take a single key press and
/// choices become arrow-key menus that collapse to a one-line answer. When input is
/// redirected or `TERM=dumb`, every question falls back to line-based input, so scripted runs
/// (`printf '1\ny\n' | tool`) keep working.
public struct Prompter: Prompting {
    /// Where questions are written and answers read.
    public let terminal: any Terminal
    /// Styling for stdout.
    public var styler: Styler
    /// Whether choices use arrow-key menus; defaults to what the terminal supports.
    public var usesInteractiveMenus: Bool
    /// Maximum option rows an arrow-key menu shows at once.
    public var menuHeight = 8

    /// Creates a prompter on `terminal` with styling per `colorMode`.
    public init(terminal: any Terminal = StandardTerminal(), colorMode: ColorMode = .auto) {
        self.terminal = terminal
        self.styler = Styler(isEnabled: terminal.environment.isColorEnabled(for: .standardOutput, mode: colorMode))
        self.usesInteractiveMenus = terminal.environment.supportsInteractiveSelection
    }

    private var rewritesLines: Bool {
        terminal.environment.supportsCursorControl(on: .standardOutput)
    }

    public func say(_ text: String) {
        terminal.writeLine(styler.apply(text, .bold, .cyan))
    }

    public func ask(_ prompt: String, default defaultValue: String?, validate: ((String) -> String?)?) -> String? {
        let promptLine = "\(prompt)\(defaultValue.map { " [\($0)]" } ?? ""): "
        while true {
            terminal.write(promptLine)
            guard let line = terminal.readLine() else { return nil }
            let typed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = typed.isEmpty ? (defaultValue ?? "") : typed
            if let message = validate?(answer) {
                acknowledge(promptLine: promptLine, typed: typed, answer: typed)
                terminal.writeLine(styler.yellow(message))
                continue
            }
            acknowledge(promptLine: promptLine, typed: typed, answer: answer)
            return answer
        }
    }

    public func askSecret(_ prompt: String) -> String? {
        terminal.write("\(prompt): ")
        let secret = terminal.readSecret()?.trimmingCharacters(in: .whitespacesAndNewlines)
        if !terminal.environment.isInputTerminal {
            terminal.writeLine()
        }
        return secret
    }

    public func confirm(_ prompt: String, default defaultAnswer: Bool) -> Bool? {
        let promptLine = "\(prompt) [\(defaultAnswer ? "Y/n" : "y/N")]: "
        while true {
            guard let answer = readAnswer(after: promptLine, singleKey: true) else { return nil }
            let decision: Bool? =
                switch answer.lowercased() {
                case "": defaultAnswer
                case "y", "yes": true
                case "n", "no": false
                default: nil
                }
            acknowledge(promptLine: promptLine, typed: answer, answer: decision.map { $0 ? "yes" : "no" } ?? answer)
            if let decision {
                return decision
            }
            terminal.writeLine("Please answer y or n.")
        }
    }

    public func askKey(_ prompt: String, keys: [Character], default defaultKey: Character?) -> Character? {
        guard !keys.isEmpty else { return nil }
        let labels = keys.map { $0 == defaultKey ? String($0).uppercased() : String($0).lowercased() }
        let promptLine = "\(prompt) [\(labels.joined(separator: "/"))]: "
        while true {
            guard let answer = readAnswer(after: promptLine, singleKey: true) else { return nil }
            let match =
                answer.isEmpty
                ? defaultKey : keys.first { String($0).lowercased() == answer.lowercased() }
            acknowledge(promptLine: promptLine, typed: answer, answer: match.map(String.init) ?? answer)
            if let match {
                return match
            }
            terminal.writeLine("Press one of \(keys.map(String.init).joined(separator: ", ")).")
        }
    }

    public func choose(_ prompt: String, options: [String], default index: Int) -> Int? {
        guard !options.isEmpty else { return nil }
        let defaultIndex = options.indices.contains(index) ? index : 0
        if usesInteractiveMenus {
            return runMenu(prompt, options: options, defaults: [defaultIndex], allowsMultiple: false)?.first
        }
        writeNumberedOptions(prompt, options: options)
        while true {
            let promptLine = "Choose 1-\(options.count) [\(defaultIndex + 1)]: "
            guard let answer = readAnswer(after: promptLine, singleKey: options.count <= 9) else { return nil }
            let choice = answer.isEmpty ? defaultIndex : Int(answer).map { $0 - 1 }
            acknowledge(promptLine: promptLine, typed: answer, answer: choice.map { String($0 + 1) } ?? answer)
            if let choice, options.indices.contains(choice) {
                return choice
            }
            terminal.writeLine("Enter a number between 1 and \(options.count).")
        }
    }

    public func chooseMany(_ prompt: String, options: [String], defaults: [Int]) -> [Int]? {
        guard !options.isEmpty else { return nil }
        let validDefaults = defaults.filter { options.indices.contains($0) }
        if usesInteractiveMenus {
            return runMenu(prompt, options: options, defaults: validDefaults, allowsMultiple: true)
        }
        writeNumberedOptions(prompt, options: options)
        let fallback = validDefaults.map { String($0 + 1) }.joined(separator: ",")
        while true {
            let promptLine = "Choose one or more (e.g. 1,3 or 1-2 or all) [\(fallback)]: "
            terminal.write(promptLine)
            guard let line = terminal.readLine() else { return nil }
            let answer = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let picked =
                answer.isEmpty && !validDefaults.isEmpty
                ? validDefaults : SelectionParser.parse(answer, count: options.count)
            let shown = picked.map { $0.map { String($0 + 1) }.joined(separator: ",") } ?? answer
            acknowledge(promptLine: promptLine, typed: answer, answer: shown)
            if let picked {
                return picked
            }
            terminal.writeLine("Enter numbers between 1 and \(options.count).")
        }
    }

    // MARK: - Helpers

    private func writeNumberedOptions(_ prompt: String, options: [String]) {
        terminal.writeLine(styler.apply("\(prompt):", .bold, .cyan))
        for (offset, option) in options.enumerated() {
            terminal.writeLine("  " + styler.cyan("\(offset + 1))") + " \(option)")
        }
    }

    private func runMenu(_ prompt: String, options: [String], defaults: [Int], allowsMultiple: Bool) -> [Int]? {
        var menu = SelectionMenu(
            title: prompt,
            options: options,
            allowsMultiple: allowsMultiple,
            defaults: defaults,
            viewportHeight: menuHeight
        )
        // Raw mode is held for the whole menu, so keys typed while a frame is drawn are not
        // echoed or turned into signals.
        return terminal.withRawInput {
            menuLoop(&menu)
        }
    }

    private func menuLoop(_ menu: inout SelectionMenu) -> [Int]? {
        var region = LiveRegion(terminal: terminal, stream: .standardOutput)
        while true {
            region.render(menu.render(styler: styler, maximumRows: terminal.size.rows - 1))
            guard let key = terminal.readKey() else {
                region.clear()
                return nil
            }
            if let outcome = menu.handle(key) {
                region.commit([menu.summary(for: outcome, styler: styler)])
                if case .submitted(let indexes) = outcome {
                    return indexes
                }
                return nil
            }
        }
    }

    /// Writes `prompt`, then reads one key on a terminal when `singleKey` is set, otherwise a
    /// line. Enter yields "", cancellation keys nil, and keys that cannot be an answer a
    /// non-empty invalid marker. The prompt is written inside the raw-mode scope so a key
    /// pressed right after it appears is not echoed.
    private func readAnswer(after prompt: String, singleKey: Bool) -> String? {
        let key: Key? =
            singleKey && terminal.environment.isInputTerminal
            ? terminal.withRawInput {
                terminal.write(prompt)
                return terminal.readKey()
            } : nil
        guard let key else {
            if !(singleKey && terminal.environment.isInputTerminal) {
                terminal.write(prompt)
            }
            return terminal.readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        switch key {
        case .enter:
            terminal.writeLine()
            return ""
        case .character(let character) where !character.isWhitespace:
            terminal.writeLine(String(character))
            return String(character)
        case .escape, .interrupt, .endOfInput:
            terminal.writeLine()
            return nil
        default:
            terminal.writeLine()
            return "\u{FFFD}"
        }
    }

    /// Leaves the accepted answer visible after a line was read.
    ///
    /// On a terminal the user's own typing is already on screen, so only an empty answer that
    /// took a default is rewritten in place. With redirected input nothing was echoed, so the
    /// answer is written out to keep the transcript readable.
    private func acknowledge(promptLine: String, typed: String, answer: String) {
        guard terminal.environment.isInputTerminal else {
            terminal.writeLine(answer)
            return
        }
        guard typed.isEmpty, !answer.isEmpty, rewritesLines else { return }
        terminal.write("\u{1B}[1A\u{1B}[2K\r\(promptLine)\(styler.cyan(answer))\n")
    }
}
