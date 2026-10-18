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
        case success
        case info
        case warning
        case error
    }

    public var kind: Kind
    public var title: String
    public var lines: [String]
    public var nextSteps: [String]

    /// Creates an alert.
    public init(kind: Kind, title: String, lines: [String] = [], nextSteps: [String] = []) {
        self.kind = kind
        self.title = title
        self.lines = lines
        self.nextSteps = nextSteps
    }

    /// The rendered box, no wider than `maximumWidth` columns.
    public func render(styler: Styler, symbols: Symbols, maximumWidth: Int = 80) -> [String] {
        let unicode = symbols == .unicode
        let (glyph, color): (String, ANSIStyle) =
            switch kind {
            case .success: (symbols.success, .green)
            case .info: (symbols.info, .blue)
            case .warning: (symbols.warning, .yellow)
            case .error: (symbols.failure, .red)
            }
        var body = lines
        if !nextSteps.isEmpty {
            if !body.isEmpty { body.append("") }
            body.append("Next steps:")
            body += nextSteps.enumerated().map { "  \($0.offset + 1). \($0.element)" }
        }
        let heading = "\(glyph) \(title)"
        let contentWidth = min(
            max(TextMetrics.displayWidth(heading) + 2, body.map(TextMetrics.displayWidth).max() ?? 0),
            max(10, maximumWidth - 4)
        )
        let (topLeft, topRight, bottomLeft, bottomRight, horizontal, vertical) =
            unicode ? ("╭", "╮", "╰", "╯", "─", "│") : ("+", "+", "+", "+", "-", "|")
        let border = { (text: String) in styler.apply(text, color) }

        let fittedHeading = TextMetrics.truncate(heading, toWidth: contentWidth - 1)
        let headingFill = contentWidth - TextMetrics.displayWidth(fittedHeading) - 1
        var rendered = [
            border(topLeft + horizontal + " ") + styler.apply(fittedHeading, .bold, color) + " "
                + border(String(repeating: horizontal, count: max(0, headingFill)) + topRight)
        ]
        for line in body {
            let fitted = TextMetrics.padRight(TextMetrics.truncate(line, toWidth: contentWidth), toWidth: contentWidth)
            rendered.append(border(vertical) + " " + fitted + " " + border(vertical))
        }
        rendered.append(border(bottomLeft + String(repeating: horizontal, count: contentWidth + 2) + bottomRight))
        return rendered
    }
}
