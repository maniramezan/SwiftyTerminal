/// The semantic colors shared by prompts, output and progress indicators.
///
/// Pass the same theme to each component for a consistent palette. Choose foreground colors
/// from ``ANSIStyle``; color emission still follows ``ColorMode`` and ``TerminalEnvironment``.
public struct TerminalTheme: Sendable, Equatable {
    /// The color of headings, selections and active progress indicators.
    public var accent: ANSIStyle
    /// The color of successful outcomes.
    public var success: ANSIStyle
    /// The color of errors and failed outcomes.
    public var error: ANSIStyle
    /// The color of warnings and input validation messages.
    public var warning: ANSIStyle
    /// The color of informational status glyphs and alert borders.
    public var info: ANSIStyle

    /// Creates a palette, keeping the standard color for any omitted role.
    ///
    /// - Parameters:
    ///   - accent: The foreground color for headings, selections and active progress.
    ///   - success: The foreground color for successful outcomes.
    ///   - error: The foreground color for errors and failed outcomes.
    ///   - warning: The foreground color for warnings and validation messages.
    ///   - info: The foreground color for informational status glyphs and alert borders.
    public init(
        accent: ANSIStyle = .cyan,
        success: ANSIStyle = .green,
        error: ANSIStyle = .red,
        warning: ANSIStyle = .yellow,
        info: ANSIStyle = .blue
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
