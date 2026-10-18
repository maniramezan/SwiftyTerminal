/// A determinate progress bar (`Uploading [██████░░░░] 60%`) on stderr.
///
/// Draws only when the stream is a terminal; otherwise only the final line from ``succeed(_:)``
/// or ``fail(_:)`` is written, so logs record the outcome without a line per update.
public actor ProgressBar {
    private let terminal: any Terminal
    private let styler: Styler
    private let symbols: Symbols
    private let width: Int
    private let minimumRedrawInterval: Duration
    private var message: String
    private var fraction = 0.0
    private var region: LiveRegion
    private var lastDraw: ContinuousClock.Instant?
    private let startedAt: ContinuousClock.Instant = .now

    /// Whether the bar is redrawn as progress changes.
    public nonisolated let isEnabled: Bool

    /// Creates a bar at 0%; nothing is drawn until the first ``update(fraction:message:)``.
    public init(
        _ message: String,
        terminal: any Terminal = StandardTerminal(),
        stream: TerminalStream = .standardError,
        colorMode: ColorMode = .auto,
        width: Int = 30,
        minimumRedrawInterval: Duration = .milliseconds(50)
    ) {
        self.message = message
        self.terminal = terminal
        self.styler = Styler(isEnabled: terminal.environment.isColorEnabled(for: stream, mode: colorMode))
        self.symbols = .for(terminal.environment)
        self.width = max(5, width)
        self.minimumRedrawInterval = minimumRedrawInterval
        self.region = LiveRegion(terminal: terminal, stream: stream)
        self.isEnabled = terminal.environment.supportsCursorControl(on: stream)
    }

    /// Sets progress to `fraction` (clamped to 0...1) and optionally a new message.
    public func update(fraction: Double, message: String? = nil) {
        self.fraction = min(max(fraction, 0), 1)
        if let message { self.message = message }
        guard isEnabled else { return }
        let now = ContinuousClock.now
        if let lastDraw, now - lastDraw < minimumRedrawInterval, self.fraction < 1 { return }
        lastDraw = now
        region.render([line()])
    }

    /// Sets progress to `completed` out of `total`.
    public func update(completed: Double, total: Double, message: String? = nil) {
        update(fraction: total > 0 ? completed / total : 0, message: message)
    }

    /// Leaves `✔ message (elapsed)`.
    public func succeed(_ message: String? = nil) {
        finish(symbol: styler.green(symbols.success), message: message)
    }

    /// Leaves `✖ message (elapsed)`.
    public func fail(_ message: String? = nil) {
        finish(symbol: styler.red(symbols.failure), message: message)
    }

    /// Erases the bar.
    public func stop() {
        region.clear()
    }

    private func finish(symbol: String, message: String?) {
        let summary = "\(symbol) \(message ?? self.message)" + styler.dim(" (\(formatElapsed(.now - startedAt)))")
        if isEnabled {
            region.commit([summary])
        } else {
            terminal.writeLine(summary, to: .standardError)
        }
    }

    /// One rendered frame.
    func line() -> String {
        let filled = Int((fraction * Double(width)).rounded(.down))
        let bar =
            styler.cyan(String(repeating: symbols.progressFilled, count: filled))
            + styler.dim(String(repeating: symbols.progressEmpty, count: width - filled))
        let percent = Int((fraction * 100).rounded(.down))
        return "\(message) [\(bar)] \(percent)%"
    }
}
