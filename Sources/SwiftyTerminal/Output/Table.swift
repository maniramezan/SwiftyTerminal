/// Rows aligned into columns by display width, with a bold header and a rule beneath it.
public struct Table: Sendable, Equatable {
    /// Column titles.
    public var headers: [String]
    /// Cell text per row; short rows are padded with empty cells.
    public var rows: [[String]]

    /// Creates a table.
    ///
    /// - Parameters:
    ///   - headers: Column titles; an empty array omits the header row.
    ///   - rows: Rows of cell text. Missing cells are treated as empty strings.
    public init(headers: [String], rows: [[String]]) {
        self.headers = headers
        self.rows = rows
    }

    /// The rendered lines.
    ///
    /// - Parameters:
    ///   - styler: The styling policy applied to rendered text.
    ///   - unicode: Whether the header rule uses Unicode box-drawing characters.
    public func render(styler: Styler, unicode: Bool) -> [String] {
        let columnCount = max(headers.count, rows.map(\.count).max() ?? 0)
        guard columnCount > 0 else { return [] }
        func cell(_ row: [String], _ column: Int) -> String {
            column < row.count ? row[column] : ""
        }
        let widths = (0..<columnCount).map { column in
            ([headers] + rows).map { TextMetrics.displayWidth(cell($0, column)) }.max() ?? 0
        }
        func line(_ row: [String], style: (String) -> String = { $0 }) -> String {
            var count = min(columnCount, row.count)
            while count > 0 && row[count - 1].allSatisfy({ $0 == " " }) { count -= 1 }
            guard count > 0 else { return "" }
            let cells = (0..<count).map { column in
                var text = cell(row, column)
                if column == count - 1 {
                    while text.last == " " { text.removeLast() }
                    return style(text)
                }
                return style(TextMetrics.padRight(text, toWidth: widths[column]))
            }
            return cells.joined(separator: "  ")
        }
        var lines = [String]()
        if !headers.isEmpty {
            lines.append(line(headers, style: styler.bold))
            let rule = unicode ? "─" : "-"
            lines.append(styler.dim(widths.map { String(repeating: rule, count: $0) }.joined(separator: "  ")))
        }
        lines += rows.map { line($0) }
        return lines
    }
}
