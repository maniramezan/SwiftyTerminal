/// Writes styled, structured output: headers, key-value rows, status lines, tables and boxes.
///
/// Choose the stream and color mode once (typically from `--output`/`--color` flags) and pass
/// the console around. Glyphs fall back to ASCII when the locale is not UTF-8.
public struct Console: Sendable {
    /// Where output goes.
    public let terminal: any Terminal
    /// The stream written to.
    public let stream: TerminalStream
    /// Styling for ``stream``.
    public let styler: Styler
    /// Status glyphs.
    public let symbols: Symbols

    /// Creates a console on `stream` with styling per `colorMode`.
    ///
    /// - Parameters:
    ///   - terminal: The terminal used for input, output, and capability decisions.
    ///   - stream: The standard stream whose capabilities or output to use.
    ///   - colorMode: Whether styling follows the environment, is forced on, or is disabled.
    public init(
        terminal: any Terminal = StandardTerminal(),
        stream: TerminalStream = .standardOutput,
        colorMode: ColorMode = .auto
    ) {
        self.terminal = terminal
        self.stream = stream
        self.styler = Styler(isEnabled: terminal.environment.isColorEnabled(for: stream, mode: colorMode))
        self.symbols = .for(terminal.environment)
    }

    /// Writes `text` and a newline.
    ///
    /// - Parameters:
    ///   - text: The text to display.
    public func print(_ text: String = "") {
        terminal.writeLine(text, to: stream)
    }

    /// `=== Title ===`, preceded by a blank line.
    ///
    /// - Parameters:
    ///   - title: The title or step name displayed to the user.
    public func header(_ title: String) {
        print("\n" + styler.apply("=== \(title) ===", .bold, .cyan))
    }

    /// A dim horizontal rule.
    ///
    /// - Parameters:
    ///   - width: The desired display width in terminal character cells.
    public func divider(width: Int = 60) {
        print(styler.dim(String(repeating: symbols == .unicode ? "─" : "-", count: width)))
    }

    /// An indented `key  value` row with the key padded to `keyWidth` columns.
    ///
    /// - Parameters:
    ///   - key: The key label displayed before the value.
    ///   - value: The value displayed after the key.
    ///   - keyWidth: The minimum display width of the key column.
    public func keyValue(_ key: String, _ value: String, keyWidth: Int = 30) {
        print("  \(styler.cyan(TextMetrics.padRight(key, toWidth: keyWidth))) \(value)")
    }

    /// `✔ message` in green.
    ///
    /// - Parameters:
    ///   - message: Text displayed beside the progress indicator or status glyph.
    public func success(_ message: String) {
        print("\(styler.green(symbols.success)) \(styler.green(message))")
    }

    /// `✖ message` in red.
    ///
    /// - Parameters:
    ///   - message: Text displayed beside the progress indicator or status glyph.
    public func error(_ message: String) {
        print("\(styler.red(symbols.failure)) \(styler.red(message))")
    }

    /// `⚠ message` in yellow.
    ///
    /// - Parameters:
    ///   - message: Text displayed beside the progress indicator or status glyph.
    public func warning(_ message: String) {
        print("\(styler.yellow(symbols.warning)) \(styler.yellow(message))")
    }

    /// `ℹ message` in blue.
    ///
    /// - Parameters:
    ///   - message: Text displayed beside the progress indicator or status glyph.
    public func info(_ message: String) {
        print("\(styler.blue(symbols.info)) \(message)")
    }

    /// An indented pass/fail line, as in a `doctor` report.
    ///
    /// - Parameters:
    ///   - name: The capability or component being checked.
    ///   - passed: Whether the check succeeded.
    public func check(_ name: String, passed: Bool) {
        let symbol = passed ? styler.green(symbols.success) : styler.red(symbols.failure)
        print("  \(symbol) \(passed ? styler.green(name) : styler.red(name))")
    }

    /// A column-aligned table.
    ///
    /// - Parameters:
    ///   - headers: Column titles; an empty array omits the header row.
    ///   - rows: Rows of cell text. Missing cells are treated as empty strings.
    public func table(headers: [String], rows: [[String]]) {
        for line in Table(headers: headers, rows: rows).render(styler: styler, unicode: symbols == .unicode) {
            print(line)
        }
    }

    /// A boxed alert with a title, body lines and optional next steps.
    ///
    /// - Parameters:
    ///   - kind: The severity that determines the status glyph and border color.
    ///   - title: The title or step name displayed to the user.
    ///   - lines: Body lines to display in order.
    ///   - nextSteps: Remediation actions displayed as a numbered list.
    public func alert(_ kind: Alert.Kind, title: String, lines: [String] = [], nextSteps: [String] = []) {
        let alert = Alert(kind: kind, title: title, lines: lines, nextSteps: nextSteps)
        for line in alert.render(styler: styler, symbols: symbols, maximumWidth: terminal.size.columns) {
            print(line)
        }
    }
}
