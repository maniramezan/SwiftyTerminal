/// A boxed message with a severity, for errors with remediation steps or end-of-command
/// summaries:
///
/// ```
/// ╭─ ✖ Upload failed ──────────────────╮
/// │ The API key was rejected.          │
/// │                                    │
/// │ Next steps:                        │
/// │   1. Run shipit doctor             │
/// ╰────────────────────────────────────╯
/// ```
public struct Alert: Sendable, Equatable {
    /// Severity, which sets the glyph and border color.
    public enum Kind: Sendable, Equatable {
        /// A successful outcome.
        case success
        /// An informational message.
        case info
        /// A warning requiring attention.
        case warning
        /// An error with remediation guidance.
        case error
    }

    /// Severity used to choose the glyph and border color.
    public var kind: Kind
    /// The heading shown in the top border.
    public var title: String
    /// Body lines displayed inside the box.
    public var lines: [String]
    /// Remediation actions displayed as a numbered list.
    public var nextSteps: [String]

    /// Creates an alert.
    ///
    /// - Parameters:
    ///   - kind: The severity that determines the status glyph and border color.
    ///   - title: The title or step name displayed to the user.
    ///   - lines: Body lines to display in order.
    ///   - nextSteps: Remediation actions displayed as a numbered list.
    public init(kind: Kind, title: String, lines: [String] = [], nextSteps: [String] = []) {
        self.kind = kind
        self.title = title
        self.lines = lines
        self.nextSteps = nextSteps
    }

    /// The rendered box, no wider than `maximumWidth` columns.
    ///
    /// - Parameters:
    ///   - styler: The styling policy applied to rendered text.
    ///   - symbols: Unicode or ASCII glyphs used to render the alert.
    ///   - maximumWidth: The maximum terminal width, including borders. Narrow widths use a compact layout.
    public func render(styler: Styler, symbols: Symbols, maximumWidth: Int = 80) -> [String] {
        let unicode = symbols == .unicode
        let (glyph, color): (String, TerminalColor) =
            switch kind {
            case .success: (symbols.success, styler.theme.success)
            case .info: (symbols.info, styler.theme.info)
            case .warning: (symbols.warning, styler.theme.warning)
            case .error: (symbols.failure, styler.theme.error)
            }
        var body = lines
        if !nextSteps.isEmpty {
            if !body.isEmpty { body.append("") }
            body.append("Next steps:")
            body += nextSteps.enumerated().map { "  \($0.offset + 1). \($0.element)" }
        }
        let heading = "\(glyph) \(title)"
        let ellipsis = unicode ? "…" : "..."
        guard maximumWidth >= 14 else {
            return ([heading] + body).map { TextMetrics.truncate($0, toWidth: maximumWidth, ellipsis: ellipsis) }
        }
        let contentWidth = min(
            max(TextMetrics.displayWidth(heading) + 2, body.map(TextMetrics.displayWidth).max() ?? 0),
            max(10, maximumWidth - 4)
        )
        let (topLeft, topRight, bottomLeft, bottomRight, horizontal, vertical) =
            unicode ? ("╭", "╮", "╰", "╯", "─", "│") : ("+", "+", "+", "+", "-", "|")
        let border = { (text: String) in styler.apply(text, color: color) }

        let fittedHeading = TextMetrics.truncate(heading, toWidth: contentWidth - 1, ellipsis: ellipsis)
        let headingFill = contentWidth - TextMetrics.displayWidth(fittedHeading) - 1
        var rendered = [
            border(topLeft + horizontal + " ") + styler.apply(fittedHeading, color: color, styles: [.bold]) + " "
                + border(String(repeating: horizontal, count: max(0, headingFill)) + topRight)
        ]
        for line in body {
            let fitted = TextMetrics.padRight(
                TextMetrics.truncate(line, toWidth: contentWidth, ellipsis: ellipsis),
                toWidth: contentWidth
            )
            rendered.append(border(vertical) + " " + fitted + " " + border(vertical))
        }
        rendered.append(border(bottomLeft + String(repeating: horizontal, count: contentWidth + 2) + bottomRight))
        return rendered
    }
}
