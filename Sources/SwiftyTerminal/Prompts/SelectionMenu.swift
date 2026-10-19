import Foundation

/// The state of an arrow-key selection menu, separate from terminal I/O so key handling and
/// rendering are testable as plain values.
///
/// Keys: Up/Down (or `k`/`j`) move, PageUp/PageDown jump a screen, Home/End go to the ends,
/// `1`–`9` jump to an option, `/` starts filtering (type to narrow, Backspace edits, Esc clears),
/// Space toggles and `a` toggles all in a multiple-choice menu, Enter submits, and Esc, Ctrl-C
/// or Ctrl-D cancel.
public struct SelectionMenu: Sendable, Equatable {
    /// How a menu ended.
    public enum Outcome: Sendable, Equatable {
        /// The chosen option indexes, sorted.
        case submitted([Int])
        /// The user cancelled without submitting a selection.
        case cancelled
    }

    /// The question shown above the options.
    public let title: String
    /// The option labels.
    public let options: [String]
    /// Whether several options can be chosen.
    public let allowsMultiple: Bool
    /// Maximum option rows shown at once.
    public var viewportHeight: Int
    /// Chosen option indexes (multiple-choice menus).
    public private(set) var selected: Set<Int>
    /// The highlighted option index.
    public private(set) var focused: Int
    /// The filter text, or nil when not filtering.
    public private(set) var filter: String?

    /// Creates a menu. `defaults` preselects options and the first of them gets focus.
    ///
    /// - Parameters:
    ///   - title: The title or step name displayed to the user.
    ///   - options: The choices in their original display order.
    ///   - allowsMultiple: Whether Space toggles several choices rather than selecting one option.
    ///   - defaults: Options initially selected. Invalid values are ignored and duplicates are removed.
    ///   - viewportHeight: The maximum visible option rows, excluding title, filter, and hints.
    public init(title: String, options: [String], allowsMultiple: Bool, defaults: [Int] = [], viewportHeight: Int = 8) {
        self.title = title
        self.options = options
        self.allowsMultiple = allowsMultiple
        self.viewportHeight = max(1, viewportHeight)
        let valid = Set(defaults.filter { options.indices.contains($0) })
        self.selected = allowsMultiple ? valid : []
        self.focused = valid.min() ?? 0
    }

    /// Option indexes that match the filter, in order.
    public var visibleIndexes: [Int] {
        guard let filter, !filter.isEmpty else { return Array(options.indices) }
        return options.indices.filter { options[$0].localizedCaseInsensitiveContains(filter) }
    }

    /// Applies one key press; returns an outcome when the menu is finished.
    ///
    /// - Parameters:
    ///   - key: The key press to apply to menu state.
    public mutating func handle(_ key: Key) -> Outcome? {
        if filter != nil, editFilter(with: key) {
            return nil
        }
        switch key {
        case .up, .character("k"):
            moveFocus(by: -1, wrapping: true)
        case .down, .character("j"):
            moveFocus(by: 1, wrapping: true)
        case .pageUp:
            moveFocus(by: -viewportHeight, wrapping: false)
        case .pageDown:
            moveFocus(by: viewportHeight, wrapping: false)
        case .home:
            focused = visibleIndexes.first ?? focused
        case .end:
            focused = visibleIndexes.last ?? focused
        case .character(" ") where allowsMultiple:
            toggle(focused)
        case .character("a") where allowsMultiple:
            let all = Set(visibleIndexes)
            selected = all.isSubset(of: selected) ? selected.subtracting(all) : selected.union(all)
        case .character("/"):
            filter = ""
        case .character(let digit) where digit.isNumber:
            if let value = digit.wholeNumberValue, options.indices.contains(value - 1) {
                focused = value - 1
            }
        case .enter:
            guard visibleIndexes.contains(focused) else { return nil }
            if !allowsMultiple { return .submitted([focused]) }
            return selected.isEmpty ? nil : .submitted(selected.sorted())
        case .escape, .interrupt, .endOfInput:
            return .cancelled
        default:
            break
        }
        return nil
    }

    /// Applies `key` to the filter text; false when the key is navigation instead.
    private mutating func editFilter(with key: Key) -> Bool {
        switch key {
        case .character(let character) where !(character == " " && allowsMultiple):
            filter?.append(character)
        case .backspace:
            if filter?.isEmpty == true { filter = nil } else { filter?.removeLast() }
        case .escape:
            filter = nil
        default:
            return false
        }
        refocus()
        return true
    }

    private mutating func toggle(_ index: Int) {
        guard visibleIndexes.contains(index) else { return }
        if selected.remove(index) == nil {
            selected.insert(index)
        }
    }

    private mutating func moveFocus(by offset: Int, wrapping: Bool) {
        let visible = visibleIndexes
        guard !visible.isEmpty else { return }
        let position = visible.firstIndex(of: focused) ?? 0
        let target = position + offset
        let count = visible.count
        focused = visible[wrapping ? ((target % count) + count) % count : min(max(target, 0), count - 1)]
    }

    private mutating func refocus() {
        let visible = visibleIndexes
        if !visible.contains(focused), let first = visible.first {
            focused = first
        }
    }

    /// The lines of one frame, at most `maximumRows` tall.
    ///
    /// - Parameters:
    ///   - styler: The styling policy applied to rendered text.
    ///   - maximumRows: The maximum number of rendered rows, including title and hints. Zero hides the menu.
    public func render(styler: Styler, maximumRows: Int = .max) -> [String] {
        guard maximumRows > 0 else { return [] }
        let visible = visibleIndexes
        let chromeRows = 2 + (filter == nil ? 0 : 1)
        if maximumRows <= chromeRows {
            let option = visible.contains(focused) ? ["> " + options[focused]] : ["No matches"]
            return Array((option + [title]).prefix(maximumRows))
        }
        let rows = max(1, min(max(1, viewportHeight), visible.count, maximumRows - chromeRows))
        let position = visible.firstIndex(of: focused) ?? 0
        let start = max(0, min(position - rows / 2, visible.count - rows))

        var lines = [styler.bold(title)]
        if let filter {
            lines.append(styler.dim("Filter: ") + filter + styler.dim("_"))
        }
        if visible.isEmpty {
            lines.append(styler.dim("  No matches"))
        }
        for index in visible.dropFirst(start).prefix(rows) {
            let isFocused = index == focused
            let marker =
                allowsMultiple ? (selected.contains(index) ? "[x]" : "[ ]") : (isFocused ? "(*)" : "( )")
            let line = "\(isFocused ? ">" : " ") \(marker) \(options[index])"
            lines.append(isFocused ? styler.accent(line) : line)
        }
        lines.append(styler.dim(hint(showing: rows, of: visible.count)))
        return lines
    }

    private func hint(showing rows: Int, of count: Int) -> String {
        var parts = ["Up/Down move"]
        if allowsMultiple {
            parts += ["Space toggle", "a all"]
        }
        parts.append(filter == nil ? "/ filter" : "Esc clear filter")
        parts.append(allowsMultiple ? "Enter done" : "Enter select")
        if filter == nil {
            parts.append("Esc cancel")
        }
        let position = count > rows ? " (\((visibleIndexes.firstIndex(of: focused) ?? 0) + 1)/\(count))" : ""
        return parts.joined(separator: " | ") + position
    }

    /// The one-line answer left behind after the menu closes.
    ///
    /// - Parameters:
    ///   - outcome: The submitted indexes or cancellation outcome to summarize.
    ///   - styler: The styling policy applied to rendered text.
    public func summary(for outcome: Outcome, styler: Styler) -> String {
        switch outcome {
        case .submitted(let indexes):
            return styler.bold(title) + ": " + styler.accent(indexes.map { options[$0] }.joined(separator: ", "))
        case .cancelled:
            return styler.bold(title) + ": " + styler.dim("cancelled")
        }
    }
}

/// Parses typed selections such as `1,3`, `2-4` or `all` into sorted, unique, zero-based indexes.
public enum SelectionParser {
    /// The indexes `text` names among `count` options, or nil when empty or out of range.
    ///
    /// - Parameters:
    ///   - text: The numbered selection expression, such as `1,3`, `2-4`, or `all`.
    ///   - count: The number of available options.
    public static func parse(_ text: String, count: Int) -> [Int]? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed == "all" {
            return count > 0 ? Array(0..<count) : nil
        }
        var picked = Set<Int>()
        for part in trimmed.split(whereSeparator: { $0 == "," || $0 == " " }) {
            let bounds = part.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
            switch bounds.count {
            case 1:
                guard let value = bounds[0], value >= 1, value <= count else { return nil }
                picked.insert(value - 1)
            case 2:
                guard let low = bounds[0], let high = bounds[1], low <= high, low >= 1, high <= count else {
                    return nil
                }
                picked.formUnion((low - 1)...(high - 1))
            default:
                return nil
            }
        }
        return picked.isEmpty ? nil : picked.sorted()
    }
}
