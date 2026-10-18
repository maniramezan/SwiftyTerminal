/// An animated "working…" line for an operation of unknown length.
///
/// The spinner draws on stderr (so `--json` stdout stays clean) and only when that stream is a
/// terminal; otherwise every call is a no-op. It waits `delay` before drawing, so operations
/// that finish quickly never flicker. Always end it with ``succeed(_:)``, ``fail(_:)`` or
/// ``stop()``, or use ``withSpinner(_:terminal:colorMode:showsResult:isolation:operation:)``.
public actor Spinner {
    private let terminal: any Terminal
    private let stream: TerminalStream
    private let styler: Styler
    private let symbols: Symbols
    private let delay: Duration
    private let interval: Duration
    private var message: String
    private var region: LiveRegion
    private var animation: Task<Void, Never>?
    private var frame = 0
    private var startedAt: ContinuousClock.Instant?

    /// Whether the spinner draws anything.
    public nonisolated let isEnabled: Bool

    /// Creates a spinner; nothing is drawn until ``start()``.
    public init(
        _ message: String,
        terminal: any Terminal = StandardTerminal(),
        stream: TerminalStream = .standardError,
        colorMode: ColorMode = .auto,
        delay: Duration = .milliseconds(150),
        interval: Duration = .milliseconds(80)
    ) {
        self.message = message
        self.terminal = terminal
        self.stream = stream
        self.styler = Styler(isEnabled: terminal.environment.isColorEnabled(for: stream, mode: colorMode))
        self.symbols = .for(terminal.environment)
        self.delay = delay
        self.interval = interval
        self.region = LiveRegion(terminal: terminal, stream: stream)
        self.isEnabled = terminal.environment.supportsCursorControl(on: stream)
    }

    /// Starts animating after the configured delay.
    public func start() {
        guard isEnabled, animation == nil else { return }
        startedAt = .now
        let delay = delay
        let interval = interval
        animation = Task {
            guard (try? await Task.sleep(for: delay)) != nil else { return }
            while !Task.isCancelled {
                self.drawNextFrame()
                guard (try? await Task.sleep(for: interval)) != nil else { return }
            }
        }
    }

    /// Changes the message shown next to the spinner.
    public func update(_ message: String) {
        self.message = message
    }

    /// Stops and leaves `✔ message (elapsed)`.
    public func succeed(_ message: String? = nil) async {
        await finish(symbol: styler.green(symbols.success), message: message)
    }

    /// Stops and leaves `✖ message (elapsed)`.
    public func fail(_ message: String? = nil) async {
        await finish(symbol: styler.red(symbols.failure), message: message)
    }

    /// Stops and erases the spinner without a trace.
    public func stop() async {
        await halt()
        region.clear()
    }

    private func finish(symbol: String, message: String?) async {
        guard isEnabled else { return }
        let elapsed = startedAt.map { formatElapsed(.now - $0) }
        await halt()
        let suffix = elapsed.map { styler.dim(" (\($0))") } ?? ""
        region.commit(["\(symbol) \(message ?? self.message)\(suffix)"])
    }

    private func halt() async {
        animation?.cancel()
        await animation?.value
        animation = nil
    }

    private func drawNextFrame() {
        let glyph = symbols.spinnerFrames[frame % symbols.spinnerFrames.count]
        frame += 1
        region.render(["\(styler.cyan(glyph)) \(message)"])
    }
}

/// Runs `operation` with a spinner, erasing it afterwards; with `showsResult`, leaves a
/// success or failure line instead. `operation` runs in the caller's isolation.
public func withSpinner<T>(
    _ message: String,
    terminal: any Terminal = StandardTerminal(),
    colorMode: ColorMode = .auto,
    showsResult: Bool = false,
    isolation: isolated (any Actor)? = #isolation,
    operation: () async throws -> T
) async rethrows -> T {
    let spinner = Spinner(message, terminal: terminal, colorMode: colorMode)
    await spinner.start()
    do {
        let value = try await operation()
        if showsResult { await spinner.succeed() } else { await spinner.stop() }
        return value
    } catch {
        if showsResult { await spinner.fail() } else { await spinner.stop() }
        throw error
    }
}
