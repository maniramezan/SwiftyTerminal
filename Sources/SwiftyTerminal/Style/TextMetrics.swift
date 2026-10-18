/// Measures and trims text by the columns it occupies in a terminal, which differs from its
/// `count` for wide (CJK, emoji) characters, zero-width marks and embedded escape sequences.
public enum TextMetrics {
    /// `text` without ANSI CSI sequences (styles, cursor movement) or OSC sequences (hyperlinks).
    ///
    /// - Parameters:
    ///   - text: The text whose terminal display width is measured or constrained.
    public static func strippingEscapes(_ text: String) -> String {
        guard text.contains("\u{1B}") else { return text }
        return sanitized(text, preservingStyles: false, removingControls: false)
    }

    // A line renderer may retain SGR colors/attributes and OSC 8 links, but never cursor
    // commands, terminal queries, title changes, or incomplete escape sequences.
    static func sanitized(_ text: String, preservingStyles: Bool = true, removingControls: Bool = true) -> String {
        let scalars = Array(text.unicodeScalars)
        var result = String.UnicodeScalarView()
        var index = 0
        var styled = false
        var linked = false
        while index < scalars.count {
            let scalar = scalars[index]
            index += 1
            if scalar != "\u{1B}" {
                if !removingControls || scalar.properties.generalCategory != .control {
                    result.append(scalar)
                }
                continue
            }
            guard index < scalars.count else { break }
            let introducer = scalars[index]
            index += 1
            let start = index
            if introducer == "[" {
                while index < scalars.count && !(0x40...0x7E).contains(scalars[index].value) { index += 1 }
                guard index < scalars.count else { break }
                let parameters = scalars[start..<index]
                if preservingStyles, scalars[index] == "m",
                    parameters.allSatisfy({ (0x30...0x39).contains($0.value) || $0 == ";" || $0 == ":" })
                {
                    result.append("\u{1B}")
                    result.append("[")
                    result.append(contentsOf: parameters)
                    result.append("m")
                    styled = true
                }
                index += 1
            } else if introducer == "]" || introducer == "P" || introducer == "X" || introducer == "^"
                || introducer == "_"
            {
                while index < scalars.count {
                    if scalars[index] == "\u{07}" && introducer == "]" { break }
                    if scalars[index] == "\u{1B}", index + 1 < scalars.count, scalars[index + 1] == "\\" { break }
                    index += 1
                }
                guard index < scalars.count else { break }
                let payload = scalars[start..<index]
                if preservingStyles, introducer == "]",
                    !payload.contains(where: { $0.properties.generalCategory == .control })
                {
                    let value = String(String.UnicodeScalarView(payload))
                    if value.hasPrefix("8;;") {
                        result.append(contentsOf: "\u{1B}]".unicodeScalars)
                        result.append(contentsOf: payload)
                        result.append(contentsOf: "\u{1B}\\".unicodeScalars)
                        linked = value != "8;;"
                    }
                }
                index += scalars[index] == "\u{1B}" ? 2 : 1
            }
        }
        var output = String(result)
        if linked { output += "\u{1B}]8;;\u{1B}\\" }
        if preservingStyles && styled && !output.hasSuffix(ANSIStyle.reset) { output += ANSIStyle.reset }
        return output
    }

    /// The number of terminal columns `text` occupies, ignoring escape sequences.
    ///
    /// - Parameters:
    ///   - text: The text whose terminal display width is measured or constrained.
    public static func displayWidth(_ text: String) -> Int {
        strippingEscapes(text).reduce(0) { $0 + width(of: $1) }
    }

    /// `text` cut to at most `width` columns, ending in `ellipsis` when anything was removed.
    /// Escape sequences and control characters are removed first so the result cannot
    /// move the cursor or leave a style open.
    ///
    /// - Parameters:
    ///   - text: The text whose terminal display width is measured or constrained.
    ///   - width: The desired display width in terminal character cells.
    ///   - ellipsis: The suffix used when truncating; escape sequences and controls are removed.
    public static func truncate(_ text: String, toWidth width: Int, ellipsis: String = "…") -> String {
        let clean = String(strippingEscapes(text).filter { !isControl($0) })
        guard width > 0 else { return "" }
        guard displayWidth(clean) > width else { return clean }
        let ellipsis = sanitized(ellipsis, preservingStyles: false)
        let ellipsisWidth = displayWidth(ellipsis)
        let budget = max(0, width - ellipsisWidth)
        var result = ""
        var used = 0
        for character in clean {
            let characterWidth = self.width(of: character)
            if used + characterWidth > budget { break }
            result.append(character)
            used += characterWidth
        }
        return ellipsisWidth <= width ? result + ellipsis : result
    }

    /// `text` padded with spaces on the right to `width` columns.
    ///
    /// - Parameters:
    ///   - text: The text whose terminal display width is measured or constrained.
    ///   - width: The desired display width in terminal character cells.
    public static func padRight(_ text: String, toWidth width: Int) -> String {
        let missing = width - displayWidth(text)
        return missing > 0 ? text + String(repeating: " ", count: missing) : text
    }

    /// The columns one character occupies: 0 for control and combining characters, 2 for wide
    /// East Asian characters and emoji presentation, 1 otherwise.
    ///
    /// - Parameters:
    ///   - character: The extended grapheme cluster whose terminal width is measured.
    public static func width(of character: Character) -> Int {
        guard let first = character.unicodeScalars.first else { return 0 }
        if isControl(character)
            || character.unicodeScalars.allSatisfy({
                $0.properties.generalCategory == .format || $0.properties.generalCategory == .nonspacingMark
            })
        {
            return 0
        }
        if first.properties.generalCategory == .nonspacingMark || first.properties.generalCategory == .enclosingMark {
            return 0
        }
        if character.unicodeScalars.contains("\u{FE0E}") { return isWide(first.value) ? 2 : 1 }
        if character.unicodeScalars.contains("\u{20E3}") { return 2 }
        if character.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation })
            || character.unicodeScalars.contains("\u{FE0F}")
        {
            return 2
        }
        return isWide(first.value) ? 2 : 1
    }

    private static func isControl(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { $0.properties.generalCategory == .control }
    }

    private static func isWide(_ value: UInt32) -> Bool {
        switch value {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
            0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60,
            0xFFE0...0xFFE6, 0x16FE0...0x18DFF, 0x1AFF0...0x1B2FF, 0x1F300...0x1F64F, 0x1F900...0x1F9FF,
            0x20000...0x3FFFD:
            true
        default:
            false
        }
    }
}
