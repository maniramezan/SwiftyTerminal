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
    private let maximumRetainedBytes: Int
    private let interval: Duration
    private let title: String
    private var captured: [String] = []
    private var capturedStart = 0
    private var capturedBytes = 0
    private var partialLine: [UInt8] = []
    private var partialWasTruncated = false
    private var pendingCarriageReturn = false
    private var lastDraw: ContinuousClock.Instant?
    private var finished = false
    private var region: LiveRegion
    private var animation: Task<Void, Never>?
    private var frame = 0
    private var startedAt: ContinuousClock.Instant?

    /// Whether output is tailed in place rather than passed through.
    public nonisolated let isInteractive: Bool

    /// Creates a tail; call ``start()`` before appending.
    ///
    /// - Parameters:
    ///   - title: What is running, shown next to the spinner and in the final line.
    ///   - terminal: Where output is written.
    ///   - stream: The stream to draw on; stderr by default.
    ///   - colorMode: Whether to style output.
    ///   - theme: The semantic palette shared by component colors.
    ///   - visibleLineCount: Output lines shown under the title.
    ///   - retainedLineCount: Output lines kept for the failure report.
    ///   - interval: Minimum time between redraws and animation frames.
    ///   - maximumRetainedBytes: The maximum UTF-8 bytes retained in complete lines and separately in a partial line; at least one.
    public init(
        _ title: String,
        terminal: any Terminal = StandardTerminal(),
        stream: TerminalStream = .standardError,
        colorMode: ColorMode = .auto,
        theme: TerminalTheme = .default,
        visibleLineCount: Int = 5,
        retainedLineCount: Int = 2000,
        interval: Duration = .milliseconds(80),
        maximumRetainedBytes: Int = 1_048_576
    ) {
        self.title = title
        self.terminal = terminal
        self.stream = stream
        self.styler = Styler(stream: stream, mode: colorMode, environment: terminal.environment, theme: theme)
        self.symbols = .for(terminal.environment)
        self.visibleLineCount = max(1, visibleLineCount)
        self.retainedLineCount = max(1, visibleLineCount, retainedLineCount)
        self.maximumRetainedBytes = max(1, maximumRetainedBytes)
        self.interval = interval
        self.region = LiveRegion(terminal: terminal, stream: stream)
        self.isInteractive = terminal.environment.supportsCursorControl(on: stream)
    }

    /// Shows the title and starts animating.
    public func start() {
        guard startedAt == nil, !finished else { return }
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
            terminal.writeLine("\(styler.accent(symbols == .unicode ? "→" : ">")) \(title)", to: stream)
        }
    }

    /// Adds command output; text may hold several lines or end mid-line.
    ///
    /// - Parameters:
    ///   - text: The text to display.
    public func append(_ text: String) {
        guard !finished else { return }
        if !isInteractive {
            terminal.write(text, to: stream)
            if !text.isEmpty { partialLine = text.hasSuffix("\n") ? [] : [1] }
            return
        }
        for byte in text.utf8 {
            if pendingCarriageReturn {
                pendingCarriageReturn = false
                if byte != 10 {
                    partialLine.removeAll(keepingCapacity: true)
                    partialWasTruncated = false
                }
            }
            if byte == 13 {
                pendingCarriageReturn = true
            } else if byte == 10 {
                recordPartialLine()
            } else if partialLine.count < maximumRetainedBytes {
                partialLine.append(byte)
            } else {
                partialWasTruncated = true
            }
        }
        let now = ContinuousClock.now
        if let lastDraw, now - lastDraw < interval { return }
        redraw()
    }

    /// Collapses to `✔ title (elapsed)`.
    ///
    /// - Parameters:
    ///   - message: A replacement message, or nil to keep the existing message.
    public func succeed(_ message: String? = nil) async {
        await finish(symbol: styler.success(symbols.success), message: message, report: [])
    }

    /// Ends with `✖ title (elapsed)`, preceded on a terminal by the last `reportLineCount`
    /// captured lines (all retained lines when nil).
    ///
    /// - Parameters:
    ///   - message: A replacement message, or nil to keep the existing message.
    ///   - reportLineCount: The maximum retained lines to include on failure; nil includes all and negative values include none.
    public func fail(_ message: String? = nil, reportLineCount: Int? = nil) async {
        guard !finished else { return }
        flushPartialLine()
        let report =
            isInteractive ? Array(captured[capturedStart...].suffix(max(0, reportLineCount ?? captured.count))) : []
        await finish(symbol: styler.error(symbols.failure), message: message, report: report)
    }

    private func finish(symbol: String, message: String?, report: [String]) async {
        guard !finished else { return }
        finished = true
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
        if !isInteractive {
            if !partialLine.isEmpty { terminal.writeLine(to: stream) }
            partialLine = []
        } else if !partialLine.isEmpty || partialWasTruncated {
            recordPartialLine()
        }
    }

    private func recordPartialLine() {
        let marker = partialWasTruncated ? String(" [truncated]".prefix(maximumRetainedBytes)) : ""
        let budget = max(0, maximumRetainedBytes - marker.utf8.count)
        var bytes = Array(partialLine.prefix(budget))
        while !bytes.isEmpty && String(bytes: bytes, encoding: .utf8) == nil { bytes.removeLast() }
        let line = String(decoding: bytes, as: UTF8.self) + marker
        partialLine.removeAll(keepingCapacity: true)
        partialWasTruncated = false
        captured.append(line)
        capturedBytes += line.utf8.count
        while captured.count - capturedStart > retainedLineCount || capturedBytes > maximumRetainedBytes {
            capturedBytes -= captured[capturedStart].utf8.count
            captured[capturedStart] = ""
            capturedStart += 1
        }
        if capturedStart > 1024 && capturedStart >= captured.count / 2 {
            captured.removeFirst(capturedStart)
            capturedStart = 0
        }
    }

    private func tick() {
        guard !finished else { return }
        frame = (frame + 1) % symbols.spinnerFrames.count
        redraw()
    }

    private func redraw() {
        lastDraw = .now
        let glyph = styler.accent(symbols.spinnerFrames[frame % symbols.spinnerFrames.count])
        let elapsed = startedAt.map { styler.dim(" (\(formatElapsed(.now - $0)))") } ?? ""
        let tail = captured[capturedStart...].suffix(min(visibleLineCount, max(0, terminal.size(for: stream).rows - 2)))
            .map { styler.dim("  " + $0) }
        region.render(["\(glyph) \(title)\(elapsed)"] + tail)
    }
}
