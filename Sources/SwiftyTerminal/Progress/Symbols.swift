/// Status glyphs and spinner frames, in Unicode or an ASCII fallback for terminals whose locale
/// is not UTF-8.
public struct Symbols: Sendable, Equatable {
    public var success: String
    public var failure: String
    public var warning: String
    public var info: String
    public var skipped: String
    public var pending: String
    public var spinnerFrames: [String]
    public var progressFilled: String
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
    public static func `for`(_ environment: TerminalEnvironment) -> Symbols {
        environment.supportsUnicode ? .unicode : .ascii
    }
}

/// Formats elapsed time compactly: `850ms`, `4.2s`, `3m 07s`.
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
