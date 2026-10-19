/// A foreground color, independent of text attributes such as bold or underline.
///
/// Named colors use the terminal's palette. RGB colors are emitted directly at
/// ``ColorDepth/trueColor`` and approximated at lower color depths.
public enum TerminalColor: Sendable, Equatable {
    /// Black from the terminal palette.
    case black
    /// Red from the terminal palette.
    case red
    /// Green from the terminal palette.
    case green
    /// Yellow from the terminal palette.
    case yellow
    /// Blue from the terminal palette.
    case blue
    /// Magenta from the terminal palette.
    case magenta
    /// Cyan from the terminal palette.
    case cyan
    /// White from the terminal palette.
    case white
    /// Gray, also called bright black, from the terminal palette.
    case gray
    /// Bright red from the terminal palette.
    case brightRed
    /// Bright green from the terminal palette.
    case brightGreen
    /// Bright yellow from the terminal palette.
    case brightYellow
    /// Bright blue from the terminal palette.
    case brightBlue
    /// Bright magenta from the terminal palette.
    case brightMagenta
    /// Bright cyan from the terminal palette.
    case brightCyan
    /// Bright white from the terminal palette.
    case brightWhite
    /// An RGB color with channel values from zero through 255.
    ///
    /// - Parameters:
    ///   - red: The red channel intensity.
    ///   - green: The green channel intensity.
    ///   - blue: The blue channel intensity.
    case rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8)

    func escapeSequence(for depth: ColorDepth) -> String {
        if let index = paletteIndex { return Self.ansiSequence(index: index) }
        guard case .rgb(let red, let green, let blue) = self else { return "" }
        switch depth {
        case .trueColor:
            return "\u{1B}[38;2;\(red);\(green);\(blue)m"
        case .ansi256:
            let index = Self.nearestIndex(red: red, green: green, blue: blue, palette: Self.extendedPalette) + 16
            return "\u{1B}[38;5;\(index)m"
        case .ansi16:
            let index = Self.nearestIndex(red: red, green: green, blue: blue, palette: Self.standardPalette)
            return Self.ansiSequence(index: index)
        }
    }

    private var paletteIndex: Int? {
        switch self {
        case .black: 0
        case .red: 1
        case .green: 2
        case .yellow: 3
        case .blue: 4
        case .magenta: 5
        case .cyan: 6
        case .white: 7
        case .gray: 8
        case .brightRed: 9
        case .brightGreen: 10
        case .brightYellow: 11
        case .brightBlue: 12
        case .brightMagenta: 13
        case .brightCyan: 14
        case .brightWhite: 15
        case .rgb: nil
        }
    }

    private static func ansiSequence(index: Int) -> String {
        "\u{1B}[\(index < 8 ? 30 + index : 90 + index - 8)m"
    }

    private static let standardPalette: [(Int, Int, Int)] = [
        (0, 0, 0), (128, 0, 0), (0, 128, 0), (128, 128, 0),
        (0, 0, 128), (128, 0, 128), (0, 128, 128), (192, 192, 192),
        (128, 128, 128), (255, 0, 0), (0, 255, 0), (255, 255, 0),
        (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255),
    ]

    private static let extendedPalette: [(Int, Int, Int)] = (16...255).map { index in
        if index >= 232 {
            let level = 8 + (index - 232) * 10
            return (level, level, level)
        }
        let levels = [0, 95, 135, 175, 215, 255]
        let offset = index - 16
        return (levels[offset / 36], levels[(offset / 6) % 6], levels[offset % 6])
    }

    private static func nearestIndex(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        palette: [(Int, Int, Int)]
    ) -> Int {
        var nearest = 0
        var smallestDistance = Int.max
        for (index, entry) in palette.enumerated() {
            let redDifference = Int(red) - entry.0
            let greenDifference = Int(green) - entry.1
            let blueDifference = Int(blue) - entry.2
            let distance =
                redDifference * redDifference + greenDifference * greenDifference + blueDifference * blueDifference
            if distance < smallestDistance {
                nearest = index
                smallestDistance = distance
            }
        }
        return nearest
    }
}
