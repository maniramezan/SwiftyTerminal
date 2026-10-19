/// An SGR (Select Graphic Rendition) attribute or color.
public enum ANSIStyle: String, Sendable, CaseIterable {
    /// Bold emphasis.
    case bold = "1"
    /// Reduced-intensity text.
    case dim = "2"
    /// Italic emphasis.
    case italic = "3"
    /// Underlined text.
    case underline = "4"
    /// Swapped foreground and background colors.
    case inverse = "7"
    /// Text with a horizontal strike.
    case strikethrough = "9"

    /// Black foreground color.
    case black = "30"
    /// Red foreground color.
    case red = "31"
    /// Green foreground color.
    case green = "32"
    /// Yellow foreground color.
    case yellow = "33"
    /// Blue foreground color.
    case blue = "34"
    /// Magenta foreground color.
    case magenta = "35"
    /// Cyan foreground color.
    case cyan = "36"
    /// White foreground color.
    case white = "37"
    /// Gray foreground color.
    case gray = "90"

    /// Bright red foreground color.
    case brightRed = "91"
    /// Bright green foreground color.
    case brightGreen = "92"
    /// Bright yellow foreground color.
    case brightYellow = "93"
    /// Bright blue foreground color.
    case brightBlue = "94"
    /// Bright magenta foreground color.
    case brightMagenta = "95"
    /// Bright cyan foreground color.
    case brightCyan = "96"
    /// Bright white foreground color.
    case brightWhite = "97"

    /// The escape sequence that turns this style on.
    public var escapeSequence: String {
        "\u{1B}[\(rawValue)m"
    }

    /// The escape sequence that resets every style.
    public static let reset = "\u{1B}[0m"
}

/// Applies ``ANSIStyle``s when styling is enabled and returns text unchanged otherwise.
///
/// Decide once per stream (``init(stream:mode:environment:theme:)``) and pass the styler around,
/// rather than checking the terminal at every call site.
public struct Styler: Sendable, Equatable {
    /// Whether styles are emitted.
    public let isEnabled: Bool

    /// The semantic palette used by components and theme-aware styling methods.
    public var theme: TerminalTheme

    /// Creates a styler with an explicit decision.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether the styler emits ANSI sequences.
    ///   - theme: The semantic palette to use when styling components.
    public init(isEnabled: Bool, theme: TerminalTheme = .default) {
        self.isEnabled = isEnabled
        self.theme = theme
    }

    /// Creates a styler for `stream` following `mode` and the process environment.
    ///
    /// - Parameters:
    ///   - stream: The standard stream whose capabilities or output to use.
    ///   - mode: The requested color policy.
    ///   - environment: Terminal capabilities and environment variables to use for rendering decisions.
    ///   - theme: The semantic palette to use when styling components.
    public init(
        stream: TerminalStream,
        mode: ColorMode = .auto,
        environment: TerminalEnvironment = .current(),
        theme: TerminalTheme = .default
    ) {
        self.isEnabled = environment.isColorEnabled(for: stream, mode: mode)
        self.theme = theme
    }

    /// A styler for stdout in ``ColorMode/auto``, resolved once per process.
    public static let standardOutput = Styler(stream: .standardOutput)

    /// A styler for stderr in ``ColorMode/auto``, resolved once per process.
    public static let standardError = Styler(stream: .standardError)

    /// A styler that never emits styles.
    public static let plain = Styler(isEnabled: false)

    /// Wraps `text` in `styles`, or returns it unchanged when disabled or `styles` is empty.
    ///
    /// - Parameters:
    ///   - text: The text to style or use as a hyperlink label.
    ///   - styles: The SGR attributes and colors to apply in order.
    public func apply(_ text: String, _ styles: ANSIStyle...) -> String {
        apply(text, styles)
    }

    /// Wraps `text` in `styles`, or returns it unchanged when disabled or `styles` is empty.
    ///
    /// - Parameters:
    ///   - text: The text to style or use as a hyperlink label.
    ///   - styles: The SGR attributes and colors to apply in order.
    public func apply(_ text: String, _ styles: [ANSIStyle]) -> String {
        guard isEnabled, !styles.isEmpty, !text.isEmpty else { return text }
        return styles.map(\.escapeSequence).joined() + text + ANSIStyle.reset
    }

    /// Text in the theme’s accent color.
    ///
    /// - Parameters:
    ///   - text: The text to style.
    public func accent(_ text: String) -> String { apply(text, theme.accent) }

    /// Text in the theme’s success color.
    ///
    /// - Parameters:
    ///   - text: The text to style.
    public func success(_ text: String) -> String { apply(text, theme.success) }

    /// Text in the theme’s error color.
    ///
    /// - Parameters:
    ///   - text: The text to style.
    public func error(_ text: String) -> String { apply(text, theme.error) }

    /// Text in the theme’s warning color.
    ///
    /// - Parameters:
    ///   - text: The text to style.
    public func warning(_ text: String) -> String { apply(text, theme.warning) }

    /// Text in the theme’s informational color.
    ///
    /// - Parameters:
    ///   - text: The text to style.
    public func info(_ text: String) -> String { apply(text, theme.info) }

    /// Bold text.
    ///
    /// - Parameters:
    ///   - text: The text to style or use as a hyperlink label.
    public func bold(_ text: String) -> String { apply(text, .bold) }
    /// Dimmed text.
    ///
    /// - Parameters:
    ///   - text: The text to style or use as a hyperlink label.
    public func dim(_ text: String) -> String { apply(text, .dim) }
    /// Red text.
    ///
    /// - Parameters:
    ///   - text: The text to style or use as a hyperlink label.
    public func red(_ text: String) -> String { apply(text, .red) }
    /// Green text.
    ///
    /// - Parameters:
    ///   - text: The text to style or use as a hyperlink label.
    public func green(_ text: String) -> String { apply(text, .green) }
    /// Yellow text.
    ///
    /// - Parameters:
    ///   - text: The text to style or use as a hyperlink label.
    public func yellow(_ text: String) -> String { apply(text, .yellow) }
    /// Blue text.
    ///
    /// - Parameters:
    ///   - text: The text to style or use as a hyperlink label.
    public func blue(_ text: String) -> String { apply(text, .blue) }
    /// Magenta text.
    ///
    /// - Parameters:
    ///   - text: The text to style or use as a hyperlink label.
    public func magenta(_ text: String) -> String { apply(text, .magenta) }
    /// Cyan text.
    ///
    /// - Parameters:
    ///   - text: The text to style or use as a hyperlink label.
    public func cyan(_ text: String) -> String { apply(text, .cyan) }
    /// Gray text.
    ///
    /// - Parameters:
    ///   - text: The text to style or use as a hyperlink label.
    public func gray(_ text: String) -> String { apply(text, .gray) }

    /// A clickable OSC 8 hyperlink, or `text (url)` when styling is disabled.
    ///
    /// - Parameters:
    ///   - text: The text to style or use as a hyperlink label.
    ///   - url: The hyperlink destination shown directly in the plain-text fallback.
    public func hyperlink(_ text: String, url: String) -> String {
        guard isEnabled else { return text == url ? url : "\(text) (\(url))" }
        return "\u{1B}]8;;\(url)\u{1B}\\\(text)\u{1B}]8;;\u{1B}\\"
    }
}

/// `text` wrapped in `styles` for stdout, as decided by ``Styler/standardOutput``.
///
/// - Parameters:
///   - text: The text to style or use as a hyperlink label.
///   - styles: The SGR attributes and colors to apply in order.
public func styled(_ text: String, _ styles: ANSIStyle...) -> String {
    Styler.standardOutput.apply(text, styles)
}

extension String {
    /// This string wrapped in `styles` using `styler`.
    ///
    /// - Parameters:
    ///   - styles: The SGR attributes and colors to apply in order.
    ///   - styler: The styling policy applied to rendered text.
    public func styled(_ styles: ANSIStyle..., using styler: Styler = .standardOutput) -> String {
        styler.apply(self, styles)
    }
}
