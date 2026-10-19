/// An animated "working…" line for an operation of unknown length.
///
/// The spinner draws on stderr (so `--json` stdout stays clean) and only when that stream is a
/// terminal; otherwise every call is a no-op. It waits `delay` before drawing, so operations
/// that finish quickly never flicker. Always end it with ``succeed(_:)``, ``fail(_:)`` or
/// ``stop()``, or use ``withSpinner(_:terminal:colorMode:theme:showsResult:isolation:operation:)``.
public actor Spinner {
    private let terminal: any Terminal
    private let stream: TerminalStream
    private let styler: Styler
    private let symbols: Symbols
    private let delay: Duration
    private let interval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private var message: String
    private var region: LiveRegion
    private var animation: Task<Void, Never>?
    private var frame = 0
    private var finishing = false
    private var startedAt: ContinuousClock.Instant?

    /// Whether the spinner draws anything.
    public nonisolated let isEnabled: Bool

    /// Creates a spinner; nothing is drawn until ``start()``.
    ///
    /// - Parameters:
    ///   - message: Text displayed beside the progress indicator or status glyph.
    ///   - terminal: The terminal used for input, output, and capability decisions.
    ///   - stream: The standard stream whose capabilities or output to use.
    ///   - colorMode: Whether styling follows the environment, is forced on, or is disabled.
    ///   - theme: The semantic palette shared by component colors.
    ///   - delay: How long to wait before displaying the first animation frame.
    ///   - interval: The time between animation frames and, for live tails, between redraws.
    public init(
        _ message: String,
        terminal: any Terminal = StandardTerminal(),
        stream: TerminalStream = .standardError,
        colorMode: ColorMode = .auto,
        theme: TerminalTheme = .default,
        delay: Duration = .milliseconds(150),
        interval: Duration = .milliseconds(80)
    ) {
        self.init(
            message,
            terminal: terminal,
            stream: stream,
            colorMode: colorMode,
            theme: theme,
            delay: delay,
            interval: interval,
            sleep: { try await Task.sleep(for: $0) }
        )
    }

    init(
        _ message: String,
        terminal: any Terminal,
        stream: TerminalStream = .standardError,
        colorMode: ColorMode = .auto,
        theme: TerminalTheme = .default,
        delay: Duration,
        interval: Duration,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.message = message
        self.terminal = terminal
        self.stream = stream
        self.styler = Styler(isEnabled: terminal.environment.isColorEnabled(for: stream, mode: colorMode), theme: theme)
        self.symbols = .for(terminal.environment)
        self.delay = delay
        self.interval = max(.milliseconds(1), interval)
        self.sleep = sleep
        self.region = LiveRegion(terminal: terminal, stream: stream)
        self.isEnabled = terminal.environment.supportsCursorControl(on: stream)
    }

    /// Starts animating after the configured delay.
    public func start() {
        guard isEnabled, animation == nil, !finishing else { return }
        startedAt = .now
        let delay = delay
        let interval = interval
        let sleep = sleep
        animation = Task {
            guard (try? await sleep(delay)) != nil else { return }
            while !Task.isCancelled {
                self.drawNextFrame()
                guard (try? await sleep(interval)) != nil else { return }
            }
        }
    }

    /// Changes the message shown next to the spinner.
    ///
    /// - Parameters:
    ///   - message: Text displayed beside the progress indicator or status glyph.
    public func update(_ message: String) {
        self.message = message
    }

    /// Stops and leaves `✔ message (elapsed)`.
    ///
    /// - Parameters:
    ///   - message: A replacement message, or nil to keep the existing message.
    public func succeed(_ message: String? = nil) async {
        await finish(symbol: styler.success(symbols.success), message: message)
    }

    /// Stops and leaves `✖ message (elapsed)`.
    ///
    /// - Parameters:
    ///   - message: A replacement message, or nil to keep the existing message.
    public func fail(_ message: String? = nil) async {
        await finish(symbol: styler.error(symbols.failure), message: message)
    }

    /// Stops and erases the spinner without a trace.
    public func stop() async {
        guard !finishing else { return }
        finishing = true
        await halt()
        region.clear()
        finishing = false
    }

    private func finish(symbol: String, message: String?) async {
        guard isEnabled, !finishing else { return }
        finishing = true
        let elapsed = startedAt.map { formatElapsed(.now - $0) }
        await halt()
        let suffix = elapsed.map { styler.dim(" (\($0))") } ?? ""
        region.commit(["\(symbol) \(message ?? self.message)\(suffix)"])
        finishing = false
    }

    private func halt() async {
        animation?.cancel()
        await animation?.value
        animation = nil
    }

    private func drawNextFrame() {
        let glyph = symbols.spinnerFrames[frame % symbols.spinnerFrames.count]
        frame += 1
        region.render(["\(styler.accent(glyph)) \(message)"])
    }
}

/// Runs `operation` with a spinner, erasing it afterwards; with `showsResult`, leaves a
/// success or failure line instead. `operation` runs in the caller's isolation.
///
/// - Parameters:
///   - message: Text displayed beside the progress indicator or status glyph.
///   - terminal: The terminal used for input, output, and capability decisions.
///   - colorMode: Whether styling follows the environment, is forced on, or is disabled.
///   - theme: The semantic palette shared by component colors.
///   - showsResult: Whether to leave a success or failure line rather than erasing the spinner.
///   - isolation: The actor isolation in which the operation executes; defaults to the caller.
///   - operation: The asynchronous work to perform. Its value or error is returned after cleanup.
public func withSpinner<T>(
    _ message: String,
    terminal: any Terminal = StandardTerminal(),
    colorMode: ColorMode = .auto,
    theme: TerminalTheme = .default,
    showsResult: Bool = false,
    isolation: isolated (any Actor)? = #isolation,
    operation: () async throws -> T
) async rethrows -> T {
    let spinner = Spinner(message, terminal: terminal, colorMode: colorMode, theme: theme)
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
