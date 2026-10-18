/// An SGR (Select Graphic Rendition) attribute or color.
public enum ANSIStyle: String, Sendable, CaseIterable {
    case bold = "1"
    case dim = "2"
    case italic = "3"
    case underline = "4"
    case inverse = "7"
    case strikethrough = "9"

    case black = "30"
    case red = "31"
    case green = "32"
    case yellow = "33"
    case blue = "34"
    case magenta = "35"
    case cyan = "36"
    case white = "37"
    case gray = "90"

    case brightRed = "91"
    case brightGreen = "92"
    case brightYellow = "93"
    case brightBlue = "94"
    case brightMagenta = "95"
    case brightCyan = "96"
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
/// Decide once per stream (``init(stream:mode:environment:)``) and pass the styler around,
/// rather than checking the terminal at every call site.
public struct Styler: Sendable, Equatable {
    /// Whether styles are emitted.
    public let isEnabled: Bool

    /// Creates a styler with an explicit decision.
    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    /// Creates a styler for `stream` following `mode` and the process environment.
    public init(
        stream: TerminalStream,
        mode: ColorMode = .auto,
        environment: TerminalEnvironment = .current()
    ) {
        self.isEnabled = environment.isColorEnabled(for: stream, mode: mode)
    }

    /// A styler for stdout in ``ColorMode/auto``, resolved once per process.
    public static let standardOutput = Styler(stream: .standardOutput)

    /// A styler for stderr in ``ColorMode/auto``, resolved once per process.
    public static let standardError = Styler(stream: .standardError)

    /// A styler that never emits styles.
    public static let plain = Styler(isEnabled: false)

    /// Wraps `text` in `styles`, or returns it unchanged when disabled or `styles` is empty.
    public func apply(_ text: String, _ styles: ANSIStyle...) -> String {
        apply(text, styles)
    }

    /// Wraps `text` in `styles`, or returns it unchanged when disabled or `styles` is empty.
    public func apply(_ text: String, _ styles: [ANSIStyle]) -> String {
        guard isEnabled, !styles.isEmpty, !text.isEmpty else { return text }
        return styles.map(\.escapeSequence).joined() + text + ANSIStyle.reset
    }

    /// Bold text.
    public func bold(_ text: String) -> String { apply(text, .bold) }
    /// Dimmed text.
    public func dim(_ text: String) -> String { apply(text, .dim) }
    /// Red text.
    public func red(_ text: String) -> String { apply(text, .red) }
    /// Green text.
    public func green(_ text: String) -> String { apply(text, .green) }
    /// Yellow text.
    public func yellow(_ text: String) -> String { apply(text, .yellow) }
    /// Blue text.
    public func blue(_ text: String) -> String { apply(text, .blue) }
    /// Magenta text.
    public func magenta(_ text: String) -> String { apply(text, .magenta) }
    /// Cyan text.
    public func cyan(_ text: String) -> String { apply(text, .cyan) }
    /// Gray text.
    public func gray(_ text: String) -> String { apply(text, .gray) }

    /// A clickable OSC 8 hyperlink, or `text (url)` when styling is disabled.
    public func hyperlink(_ text: String, url: String) -> String {
        guard isEnabled else { return text == url ? url : "\(text) (\(url))" }
        return "\u{1B}]8;;\(url)\u{1B}\\\(text)\u{1B}]8;;\u{1B}\\"
    }
}

/// `text` wrapped in `styles` for stdout, as decided by ``Styler/standardOutput``.
public func styled(_ text: String, _ styles: ANSIStyle...) -> String {
    Styler.standardOutput.apply(text, styles)
}

extension String {
    /// This string wrapped in `styles` using `styler`.
    public func styled(_ styles: ANSIStyle..., using styler: Styler = .standardOutput) -> String {
        styler.apply(self, styles)
    }
}
