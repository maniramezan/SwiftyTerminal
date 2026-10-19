/// The semantic colors shared by prompts, output and progress indicators.
///
/// Pass the same theme to each component for a consistent palette. Choose foreground colors
/// from ``TerminalColor``; color emission still follows ``ColorMode`` and ``TerminalEnvironment``.
public struct TerminalTheme: Sendable, Equatable {
    /// The color of headings, selections and active progress indicators.
    public var accent: TerminalColor
    /// The color of successful outcomes.
    public var success: TerminalColor
    /// The color of errors and failed outcomes.
    public var error: TerminalColor
    /// The color of warnings and input validation messages.
    public var warning: TerminalColor
    /// The color of informational status glyphs and alert borders.
    public var info: TerminalColor

    /// Creates a palette, keeping the standard color for any omitted role.
    ///
    /// - Parameters:
    ///   - accent: The foreground color for headings, selections and active progress.
    ///   - success: The foreground color for successful outcomes.
    ///   - error: The foreground color for errors and failed outcomes.
    ///   - warning: The foreground color for warnings and validation messages.
    ///   - info: The foreground color for informational status glyphs and alert borders.
    public init(
        accent: TerminalColor = .cyan,
        success: TerminalColor = .green,
        error: TerminalColor = .red,
        warning: TerminalColor = .yellow,
        info: TerminalColor = .blue
    ) {
        self.accent = accent
        self.success = success
        self.error = error
        self.warning = warning
        self.info = info
    }

    /// The standard cyan accent with green success, red errors, yellow warnings and blue information.
    public static let `default` = TerminalTheme()
}
