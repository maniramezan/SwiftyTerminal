/// Measures and trims text by the columns it occupies in a terminal, which differs from its
/// `count` for wide (CJK, emoji) characters, zero-width marks and embedded escape sequences.
public enum TextMetrics {
    /// `text` without ANSI CSI sequences (styles, cursor movement) or OSC sequences (hyperlinks).
    public static func strippingEscapes(_ text: String) -> String {
        guard text.contains("\u{1B}") else { return text }
        var result = String.UnicodeScalarView()
        var scalars = text.unicodeScalars.makeIterator()
        while let scalar = scalars.next() {
            guard scalar == "\u{1B}" else {
                result.append(scalar)
                continue
            }
            switch scalars.next() {
            case "[":
                // CSI: parameters, then one final byte in 0x40...0x7E.
                while let next = scalars.next(), !(0x40...0x7E).contains(next.value) {}
            case "]":
                // OSC: terminated by BEL or ESC \.
                while let next = scalars.next() {
                    if next == "\u{07}" { break }
                    if next == "\u{1B}" {
                        _ = scalars.next()
                        break
                    }
                }
            default:
                break
            }
        }
        return String(result)
    }

    /// The number of terminal columns `text` occupies, ignoring escape sequences.
    public static func displayWidth(_ text: String) -> Int {
        strippingEscapes(text).reduce(0) { $0 + width(of: $1) }
    }

    /// `text` cut to at most `width` columns, ending in `ellipsis` when anything was removed.
    /// Escape sequences and control characters are removed first so the result cannot
    /// move the cursor or leave a style open.
    public static func truncate(_ text: String, toWidth width: Int, ellipsis: String = "…") -> String {
        let clean = String(strippingEscapes(text).filter { !isControl($0) })
        guard width > 0 else { return "" }
        guard displayWidth(clean) > width else { return clean }
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
    public static func padRight(_ text: String, toWidth width: Int) -> String {
        let missing = width - displayWidth(text)
        return missing > 0 ? text + String(repeating: " ", count: missing) : text
    }

    /// The columns one character occupies: 0 for control and combining characters, 2 for wide
    /// East Asian characters and emoji presentation, 1 otherwise.
    public static func width(of character: Character) -> Int {
        guard let first = character.unicodeScalars.first else { return 0 }
        if isControl(character) { return 0 }
        if first.properties.generalCategory == .nonspacingMark || first.properties.generalCategory == .enclosingMark {
            return 0
        }
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
            0xFFE0...0xFFE6, 0x1F300...0x1F64F, 0x1F900...0x1F9FF, 0x20000...0x3FFFD:
            true
        default:
            false
        }
    }
}
