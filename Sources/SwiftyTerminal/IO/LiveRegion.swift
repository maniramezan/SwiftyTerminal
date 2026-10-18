/// A block of lines at the bottom of a stream that is redrawn in place: menus, spinners,
/// step lists and log tails.
///
/// Each ``render(_:)`` moves the cursor back to the top of the previous frame, clears to the
/// end of the screen and writes the new frame, so a shorter frame leaves no stale lines.
/// Lines are cut to the terminal width because a wrapped line would break the line count.
public struct LiveRegion: Sendable {
    private let terminal: any Terminal
    private let stream: TerminalStream
    private var renderedLineCount = 0

    /// Creates an empty region on `stream`.
    ///
    /// - Parameters:
    ///   - terminal: The terminal used for input, output, and capability decisions.
    ///   - stream: The standard stream whose capabilities or output to use.
    public init(terminal: any Terminal, stream: TerminalStream) {
        self.terminal = terminal
        self.stream = stream
    }

    /// Replaces the previous frame with `lines`.
    ///
    /// - Parameters:
    ///   - lines: The frame or permanent output lines; unsafe terminal controls are removed.
    public mutating func render(_ lines: [String]) {
        let size = terminal.size(for: stream)
        let width = max(0, size.columns - 1)
        let visible = Array(lines.prefix(max(0, size.rows - 1)))
        var frame = rewind()
        for line in visible {
            frame += fitted(line, width: width) + "\n"
        }
        terminal.write(frame, to: stream)
        renderedLineCount = visible.count
    }

    /// Erases the current frame and leaves the cursor where it began.
    public mutating func clear() {
        let frame = rewind()
        if !frame.isEmpty {
            terminal.write(frame, to: stream)
        }
        renderedLineCount = 0
    }

    /// Erases the current frame and writes `lines` as permanent output below which the next
    /// frame starts.
    ///
    /// - Parameters:
    ///   - lines: The frame or permanent output lines; unsafe terminal controls are removed.
    public mutating func commit(_ lines: [String]) {
        var frame = rewind()
        for line in lines {
            frame += TextMetrics.sanitized(line) + "\n"
        }
        terminal.write(frame, to: stream)
        renderedLineCount = 0
    }

    private func rewind() -> String {
        guard renderedLineCount > 0 else { return "" }
        let rows = min(renderedLineCount, max(0, terminal.size(for: stream).rows - 1))
        guard rows > 0 else { return "" }
        return "\u{1B}[\(rows)A\r\u{1B}[J"
    }

    private func fitted(_ line: String, width: Int) -> String {
        let clean = TextMetrics.sanitized(line)
        let ellipsis = terminal.environment.supportsUnicode ? "…" : "..."
        return TextMetrics.displayWidth(clean) <= width
            ? clean : TextMetrics.truncate(clean, toWidth: width, ellipsis: ellipsis)
    }
}
