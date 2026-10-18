/// Shows the last few lines of a long-running command's output under an animated title, then
/// collapses to one line on success or prints the captured output on failure:
///
/// ```
/// ⠼ Building MyApp (12.4s)
///   CompileSwift normal arm64 AppDelegate.swift
///   CompileSwift normal arm64 ContentView.swift
/// ```
///
/// When the stream is not a terminal, every line is passed straight through instead, so CI logs
/// keep the complete output.
public actor LiveTail {
    private let terminal: any Terminal
    private let stream: TerminalStream
    private let styler: Styler
    private let symbols: Symbols
    private let visibleLineCount: Int
    private let retainedLineCount: Int
    private let interval: Duration
    private let title: String
    private var captured: [String] = []
    private var partialLine = ""
    private var region: LiveRegion
    private var animation: Task<Void, Never>?
    private var frame = 0
    private var startedAt: ContinuousClock.Instant?

    /// Whether output is tailed in place rather than passed through.
    public nonisolated let isInteractive: Bool

    /// Creates a tail; call ``start()`` before appending.
    ///
    /// - Parameters:
    ///   - visibleLineCount: Output lines shown under the title.
    ///   - retainedLineCount: Output lines kept for the failure report.
    public init(
        _ title: String,
        terminal: any Terminal = StandardTerminal(),
        stream: TerminalStream = .standardError,
        colorMode: ColorMode = .auto,
        visibleLineCount: Int = 5,
        retainedLineCount: Int = 2000,
        interval: Duration = .milliseconds(80)
    ) {
        self.title = title
        self.terminal = terminal
        self.stream = stream
        self.styler = Styler(isEnabled: terminal.environment.isColorEnabled(for: stream, mode: colorMode))
        self.symbols = .for(terminal.environment)
        self.visibleLineCount = max(1, visibleLineCount)
        self.retainedLineCount = max(visibleLineCount, retainedLineCount)
        self.interval = interval
        self.region = LiveRegion(terminal: terminal, stream: stream)
        self.isInteractive = terminal.environment.supportsCursorControl(on: stream)
    }

    /// Shows the title and starts animating.
    public func start() {
        guard startedAt == nil else { return }
        startedAt = .now
        if isInteractive {
            redraw()
            let interval = interval
            animation = Task {
                while !Task.isCancelled {
                    guard (try? await Task.sleep(for: interval)) != nil else { return }
                    self.tick()
                }
            }
        } else {
            terminal.writeLine("\(styler.cyan("→")) \(title)", to: stream)
        }
    }

    /// Adds command output; text may hold several lines or end mid-line.
    public func append(_ text: String) {
        // "\r\n" is a single Character, so it has to be matched alongside "\n".
        var pieces = (partialLine + text)
            .split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" }
            .map(String.init)
        partialLine = pieces.removeLast()
        for line in pieces {
            record(line)
        }
        if isInteractive, !pieces.isEmpty {
            redraw()
        }
    }

    /// Collapses to `✔ title (elapsed)`.
    public func succeed(_ message: String? = nil) async {
        await finish(symbol: styler.green(symbols.success), message: message, report: [])
    }

    /// Ends with `✖ title (elapsed)`, preceded on a terminal by the last `reportLineCount`
    /// captured lines (all retained lines when nil).
    public func fail(_ message: String? = nil, reportLineCount: Int? = nil) async {
        flushPartialLine()
        let report = isInteractive ? Array(captured.suffix(reportLineCount ?? captured.count)) : []
        await finish(symbol: styler.red(symbols.failure), message: message, report: report)
    }

    private func finish(symbol: String, message: String?, report: [String]) async {
        flushPartialLine()
        animation?.cancel()
        await animation?.value
        animation = nil
        let elapsed = startedAt.map { styler.dim(" (\(formatElapsed(.now - $0)))") } ?? ""
        let summary = "\(symbol) \(message ?? title)\(elapsed)"
        if isInteractive {
            region.commit(report + [summary])
        } else {
            terminal.writeLine(summary, to: stream)
        }
    }

    private func flushPartialLine() {
        guard !partialLine.isEmpty else { return }
        record(partialLine)
        partialLine = ""
    }

    private func record(_ line: String) {
        if isInteractive {
            captured.append(line)
            if captured.count > retainedLineCount {
                captured.removeFirst(captured.count - retainedLineCount)
            }
        } else {
            terminal.writeLine(line, to: stream)
        }
    }

    private func tick() {
        frame += 1
        redraw()
    }

    private func redraw() {
        let glyph = styler.cyan(symbols.spinnerFrames[frame % symbols.spinnerFrames.count])
        let elapsed = startedAt.map { styler.dim(" (\(formatElapsed(.now - $0)))") } ?? ""
        let tail = captured.suffix(visibleLineCount).map { styler.dim("  " + $0) }
        region.render(["\(glyph) \(title)\(elapsed)"] + tail)
    }
}
