/// One key press read in raw mode.
public enum Key: Sendable, Hashable {
    /// A printable character, including space.
    case character(Character)
    /// Enter or Return.
    case enter
    /// The Tab key.
    case tab
    /// Backspace, deleting before the cursor.
    case backspace
    /// Forward Delete.
    case delete
    /// A lone Escape key.
    case escape
    /// The Up arrow.
    case up
    /// The Down arrow.
    case down
    /// The Left arrow.
    case left
    /// The Right arrow.
    case right
    /// Moves to the beginning.
    case home
    /// Moves to the end.
    case end
    /// Moves one page up.
    case pageUp
    /// Moves one page down.
    case pageDown
    /// Ctrl-C. Raw mode disables the signal, so prompts treat it as cancellation.
    case interrupt
    /// Ctrl-D or end of input.
    case endOfInput
    /// Any other control character or unrecognized escape sequence.
    case unknown

    /// Decodes the bytes of one key press as returned by a raw terminal read.
    ///
    /// - Parameters:
    ///   - bytes: The bytes of one key press, including its full UTF-8 or escape sequence.
    public init(bytes: [UInt8]) {
        guard let first = bytes.first else {
            self = .endOfInput
            return
        }
        if first == 0x1B {
            self = Self.escapeSequence(Array(bytes.dropFirst()))
            return
        }
        switch first {
        case 0x03: self = .interrupt
        case 0x04: self = .endOfInput
        case 0x09: self = .tab
        case 0x0A, 0x0D: self = .enter
        case 0x08, 0x7F: self = .backspace
        case 0x00..<0x20: self = .unknown
        default:
            if let text = String(bytes: bytes, encoding: .utf8), let character = text.first, text.count == 1 {
                self = .character(character)
            } else {
                self = .unknown
            }
        }
    }

    private static func escapeSequence(_ rest: [UInt8]) -> Key {
        guard let introducer = rest.first else { return .escape }
        guard introducer == UInt8(ascii: "[") || introducer == UInt8(ascii: "O"),
            let final = rest.last, rest.count >= 2
        else { return .unknown }
        switch final {
        case UInt8(ascii: "A"): return .up
        case UInt8(ascii: "B"): return .down
        case UInt8(ascii: "C"): return .right
        case UInt8(ascii: "D"): return .left
        case UInt8(ascii: "H"): return .home
        case UInt8(ascii: "F"): return .end
        case UInt8(ascii: "~"):
            switch String(bytes: rest.dropFirst().dropLast(), encoding: .ascii) {
            case "1", "7": return .home
            case "3": return .delete
            case "4", "8": return .end
            case "5": return .pageUp
            case "6": return .pageDown
            default: return .unknown
            }
        default:
            return .unknown
        }
    }
}
