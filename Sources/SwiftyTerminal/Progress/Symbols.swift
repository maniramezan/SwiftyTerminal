/// Status glyphs and spinner frames, in Unicode or an ASCII fallback for terminals whose locale
/// is not UTF-8.
public struct Symbols: Sendable, Equatable {
    /// Glyph for a successful operation.
    public var success: String
    /// Glyph for a failed operation.
    public var failure: String
    /// Glyph for a warning.
    public var warning: String
    /// Glyph for an informational message.
    public var info: String
    /// Glyph for a skipped step.
    public var skipped: String
    /// Glyph for a step that has not started.
    public var pending: String
    /// Animation frames cycled by progress components.
    public var spinnerFrames: [String]
    /// Glyph for the completed part of a progress bar.
    public var progressFilled: String
    /// Glyph for the remaining part of a progress bar.
    public var progressEmpty: String

    /// Unicode glyphs and a Braille spinner.
    public static let unicode = Symbols(
        success: "✔",
        failure: "✖",
        warning: "⚠",
        info: "ℹ",
        skipped: "↷",
        pending: "○",
        spinnerFrames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
        progressFilled: "█",
        progressEmpty: "░"
    )

    /// Plain ASCII glyphs and a line spinner.
    public static let ascii = Symbols(
        success: "[ok]",
        failure: "[x]",
        warning: "[!]",
        info: "[i]",
        skipped: "[-]",
        pending: "[ ]",
        spinnerFrames: ["|", "/", "-", "\\"],
        progressFilled: "#",
        progressEmpty: "-"
    )

    /// The set matching `environment`'s Unicode support.
    ///
    /// - Parameters:
    ///   - environment: Terminal capabilities and environment variables to use for rendering decisions.
    public static func `for`(_ environment: TerminalEnvironment) -> Symbols {
        environment.supportsUnicode ? .unicode : .ascii
    }
}

/// Formats elapsed time compactly: `850ms`, `4.2s`, `3m 07s`.
///
/// - Parameters:
///   - duration: Elapsed time to format.
public func formatElapsed(_ duration: Duration) -> String {
    let milliseconds = duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000
    if milliseconds < 1000 {
        return "\(milliseconds)ms"
    }
    if milliseconds < 60_000 {
        let tenths = (milliseconds + 50) / 100
        return "\(tenths / 10).\(tenths % 10)s"
    }
    let seconds = milliseconds / 1000
    let remainder = seconds % 60
    return "\(seconds / 60)m \(remainder < 10 ? "0" : "")\(remainder)s"
}
