/// The foreground color precision available when ANSI styling is enabled.
///
/// Color depth controls RGB approximation. ``ColorMode`` independently determines whether
/// styling is emitted at all.
public enum ColorDepth: Sendable, Equatable {
    /// The terminal's sixteen named palette colors.
    case ansi16
    /// The xterm 256-color palette, including its fixed color cube and grayscale ramp.
    case ansi256
    /// Direct 24-bit RGB colors.
    case trueColor
}
