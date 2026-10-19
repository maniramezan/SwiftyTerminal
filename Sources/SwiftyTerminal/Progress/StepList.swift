/// A checklist of named steps that updates in place:
///
/// ```
/// ✔ Build (41.2s)
/// ⠼ Test
/// ○ Upload
/// ```
///
/// On a terminal the list is redrawn as steps change and the running step animates. Otherwise
/// one line is written as each step starts and ends, which reads well in CI logs.
public actor StepList {
    /// Where a step is.
    public enum State: Sendable, Equatable {
        /// The step has not started.
        case pending
        /// The step is currently executing.
        case running
        /// The step completed successfully.
        case succeeded
        /// The step ended in failure.
        case failed
        /// The step was intentionally skipped.
        case skipped
    }

    private struct Step {
        var title: String
        var state: State = .pending
        var detail: String?
        var startedAt: ContinuousClock.Instant?
        var elapsed: Duration?
    }

    private let terminal: any Terminal
    private let stream: TerminalStream
    private let styler: Styler
    private let symbols: Symbols
    private let interval: Duration
    private var steps: [Step]
    private var region: LiveRegion
    private var animation: Task<Void, Never>?
    private var frame = 0

    /// Whether the list is redrawn in place.
    public nonisolated let isInteractive: Bool

    /// Creates a list of pending steps. Nothing is drawn until a step changes.
    ///
    /// - Parameters:
    ///   - titles: Step names in their initial display order.
    ///   - terminal: The terminal used for input, output, and capability decisions.
    ///   - stream: The standard stream whose capabilities or output to use.
    ///   - colorMode: Whether styling follows the environment, is forced on, or is disabled.
    ///   - theme: The semantic palette shared by component colors.
    ///   - interval: The time between animation frames and, for live tails, between redraws.
    public init(
        _ titles: [String],
        terminal: any Terminal = StandardTerminal(),
        stream: TerminalStream = .standardError,
        colorMode: ColorMode = .auto,
        theme: TerminalTheme = .default,
        interval: Duration = .milliseconds(80)
    ) {
        self.steps = titles.map { Step(title: $0) }
        self.terminal = terminal
        self.stream = stream
        self.styler = Styler(isEnabled: terminal.environment.isColorEnabled(for: stream, mode: colorMode), theme: theme)
        self.symbols = .for(terminal.environment)
        self.interval = interval
        self.region = LiveRegion(terminal: terminal, stream: stream)
        self.isInteractive = terminal.environment.supportsCursorControl(on: stream)
    }

    /// The state of the step titled `title`.
    ///
    /// - Parameters:
    ///   - title: The title or step name displayed to the user.
    public func state(of title: String) -> State? {
        steps.first { $0.title == title }?.state
    }

    /// Marks `title` as running, appending it when it was not listed.
    ///
    /// - Parameters:
    ///   - title: The title or step name displayed to the user.
    public func start(_ title: String) {
        let index = indexOrAppend(title)
        steps[index].state = .running
        steps[index].startedAt = .now
        if isInteractive {
            startAnimation()
            redraw()
        } else {
            terminal.writeLine("\(styler.accent(symbols == .unicode ? "→" : ">")) \(title)", to: stream)
        }
    }

    /// Marks `title` as succeeded.
    ///
    /// - Parameters:
    ///   - title: The title or step name displayed to the user.
    ///   - detail: Optional explanatory text displayed beside the completed step.
    public func succeed(_ title: String, detail: String? = nil) {
        end(title, state: .succeeded, detail: detail)
    }

    /// Marks `title` as failed.
    ///
    /// - Parameters:
    ///   - title: The title or step name displayed to the user.
    ///   - detail: Optional explanatory text displayed beside the completed step.
    public func fail(_ title: String, detail: String? = nil) {
        end(title, state: .failed, detail: detail)
    }

    /// Marks `title` as skipped.
    ///
    /// - Parameters:
    ///   - title: The title or step name displayed to the user.
    ///   - detail: Optional explanatory text displayed beside the completed step.
    public func skip(_ title: String, detail: String? = nil) {
        end(title, state: .skipped, detail: detail)
    }

    /// Stops animating and leaves the final list on screen.
    public func finish() async {
        animation?.cancel()
        await animation?.value
        animation = nil
        if isInteractive, steps.contains(where: { $0.state != .pending }) {
            region.commit(lines())
        }
    }

    private func end(_ title: String, state: State, detail: String?) {
        let index = indexOrAppend(title)
        steps[index].state = state
        steps[index].detail = detail
        steps[index].elapsed = steps[index].startedAt.map { .now - $0 }
        if isInteractive {
            redraw()
        } else {
            terminal.writeLine(line(for: steps[index]), to: stream)
        }
    }

    private func indexOrAppend(_ title: String) -> Int {
        if let index = steps.firstIndex(where: { $0.title == title }) {
            return index
        }
        steps.append(Step(title: title))
        return steps.count - 1
    }

    private func startAnimation() {
        guard animation == nil else { return }
        let interval = interval
        animation = Task {
            while !Task.isCancelled {
                guard (try? await Task.sleep(for: interval)) != nil else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        frame += 1
        if steps.contains(where: { $0.state == .running }) {
            redraw()
        }
    }

    private func redraw() {
        region.render(lines())
    }

    private func lines() -> [String] {
        steps.map(line(for:))
    }

    private func line(for step: Step) -> String {
        let glyph: String
        var title = step.title
        switch step.state {
        case .pending:
            glyph = styler.dim(symbols.pending)
            title = styler.dim(title)
        case .running:
            glyph = styler.accent(symbols.spinnerFrames[frame % symbols.spinnerFrames.count])
        case .succeeded:
            glyph = styler.success(symbols.success)
        case .failed:
            glyph = styler.error(symbols.failure)
        case .skipped:
            glyph = styler.dim(symbols.skipped)
            title = styler.dim(title)
        }
        var suffix = [String]()
        if let detail = step.detail { suffix.append(detail) }
        if let elapsed = step.elapsed, step.state != .skipped { suffix.append(formatElapsed(elapsed)) }
        let tail = suffix.isEmpty ? "" : styler.dim(" (\(suffix.joined(separator: ", ")))")
        return "\(glyph) \(title)\(tail)"
    }
}
