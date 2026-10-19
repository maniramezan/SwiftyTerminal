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
    ///   - theme: The semantic palette shared by component colors.
    public init(
        terminal: any Terminal = StandardTerminal(),
        stream: TerminalStream = .standardOutput,
        colorMode: ColorMode = .auto,
        theme: TerminalTheme = .default
    ) {
        self.terminal = terminal
        self.stream = stream
        self.styler = Styler(stream: stream, mode: colorMode, environment: terminal.environment, theme: theme)
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
        print("\n" + styler.apply("=== \(title) ===", color: styler.theme.accent, styles: [.bold]))
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
        print("  \(styler.accent(TextMetrics.padRight(key, toWidth: keyWidth))) \(value)")
    }

    /// `✔ message` in the theme’s success color.
    ///
    /// - Parameters:
    ///   - message: Text displayed beside the progress indicator or status glyph.
    public func success(_ message: String) {
        print("\(styler.success(symbols.success)) \(styler.success(message))")
    }

    /// `✖ message` in the theme’s error color.
    ///
    /// - Parameters:
    ///   - message: Text displayed beside the progress indicator or status glyph.
    public func error(_ message: String) {
        print("\(styler.error(symbols.failure)) \(styler.error(message))")
    }

    /// `⚠ message` in the theme’s warning color.
    ///
    /// - Parameters:
    ///   - message: Text displayed beside the progress indicator or status glyph.
    public func warning(_ message: String) {
        print("\(styler.warning(symbols.warning)) \(styler.warning(message))")
    }

    /// `ℹ message` in the theme’s information color.
    ///
    /// - Parameters:
    ///   - message: Text displayed beside the progress indicator or status glyph.
    public func info(_ message: String) {
        print("\(styler.info(symbols.info)) \(message)")
    }

    /// An indented pass/fail line, as in a `doctor` report.
    ///
    /// - Parameters:
    ///   - name: The capability or component being checked.
    ///   - passed: Whether the check succeeded.
    public func check(_ name: String, passed: Bool) {
        let symbol = passed ? styler.success(symbols.success) : styler.error(symbols.failure)
        print("  \(symbol) \(passed ? styler.success(name) : styler.error(name))")
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
