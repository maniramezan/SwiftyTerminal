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
    public init(terminal: any Terminal, stream: TerminalStream) {
        self.terminal = terminal
        self.stream = stream
    }

    /// Replaces the previous frame with `lines`.
    public mutating func render(_ lines: [String]) {
        let width = max(1, terminal.size.columns - 1)
        var frame = rewind()
        for line in lines {
            frame += fitted(line, width: width) + "\n"
        }
        terminal.write(frame, to: stream)
        renderedLineCount = lines.count
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
    public mutating func commit(_ lines: [String]) {
        var frame = rewind()
        for line in lines {
            frame += line + "\n"
        }
        terminal.write(frame, to: stream)
        renderedLineCount = 0
    }

    private func rewind() -> String {
        guard renderedLineCount > 0 else { return "" }
        return "\u{1B}[\(renderedLineCount)A\r\u{1B}[J"
    }

    // Styled lines keep their escapes when they fit; overlong lines and lines with stray
    // control characters (which could move the cursor) are flattened.
    private func fitted(_ line: String, width: Int) -> String {
        let hasControl = line.unicodeScalars.contains { $0.properties.generalCategory == .control && $0 != "\u{1B}" }
        return !hasControl && TextMetrics.displayWidth(line) <= width
            ? line : TextMetrics.truncate(line, toWidth: width)
    }
}
