@testable import SwiftyTerminal
import SwiftyTerminalTesting
import Testing

@Suite("Progress")
struct ProgressTests {
    @Test("A spinner on a non-terminal stream writes nothing")
    func spinnerDisabled() async {
        let terminal = ScriptedTerminal(input: [], environment: ScriptedTerminal.redirected)
        let spinner = Spinner("Working", terminal: terminal, delay: .zero)
        #expect(!spinner.isEnabled)
        await spinner.start()
        await spinner.succeed()
        #expect(terminal.output(.standardError).isEmpty)
    }

    @Test("A spinner that finishes before its delay draws nothing")
    func spinnerDelay() async {
        let terminal = ScriptedTerminal(input: [])
        let value = await withSpinner("Inspecting", terminal: terminal) { 42 }
        #expect(value == 42)
        #expect(terminal.output(.standardError).isEmpty)
    }

    @Test("A spinner animates on stderr and leaves a result line")
    func spinnerAnimates() async {
        let terminal = ScriptedTerminal(input: [])
        let schedule = ManualAnimationSchedule()
        let spinner = Spinner(
            "Inspecting",
            terminal: terminal,
            colorMode: .always,
            theme: TerminalTheme(accent: .magenta),
            delay: .seconds(10),
            interval: .seconds(1),
            sleep: { try await schedule.sleep($0) }
        )
        await spinner.start()
        await schedule.waitForRequests(1)
        #expect(terminal.output(.standardError).isEmpty)
        await schedule.advance()
        await schedule.waitForRequests(2)
        await spinner.succeed("Inspected")
        let output = terminal.plainOutput(.standardError)
        #expect(output.contains("⠋ Inspecting"))
        #expect(output.contains("✔ Inspected ("))
        #expect(terminal.output(.standardError).contains("\u{1B}[35m⠋\u{1B}[0m"))
        #expect(terminal.output(.standardOutput).isEmpty)
    }

    @Test("withSpinner erases the spinner when the operation throws")
    func spinnerThrows() async {
        struct Failure: Error {}
        let terminal = ScriptedTerminal(input: [])
        await #expect(throws: Failure.self) {
            try await withSpinner("Working", terminal: terminal) { throw Failure() }
        }
    }

    @Test("A progress bar renders proportionally and ends with a summary")
    func progressBar() async {
        let terminal = ScriptedTerminal(input: [])
        let bar = ProgressBar("Uploading", terminal: terminal, width: 10, minimumRedrawInterval: .zero)
        await bar.update(completed: 3, total: 10)
        await bar.succeed("Uploaded")
        let output = terminal.plainOutput(.standardError)
        #expect(output.contains("Uploading [███░░░░░░░] 30%"))
        #expect(output.contains("✔ Uploaded ("))
    }

    @Test("A redirected progress bar writes only the outcome")
    func progressBarRedirected() async {
        let terminal = ScriptedTerminal(input: [], environment: ScriptedTerminal.redirected)
        let bar = ProgressBar("Uploading", terminal: terminal)
        await bar.update(fraction: 0.5)
        await bar.fail("Upload failed")
        let output = terminal.output(.standardError)
        #expect(!output.contains("50%"))
        #expect(output.hasPrefix("✖ Upload failed ("))
    }

    @Test("A redirected step list writes a line per transition")
    func stepListRedirected() async {
        let terminal = ScriptedTerminal(input: [], environment: ScriptedTerminal.redirected)
        let steps = StepList(["Build", "Test", "Upload"], terminal: terminal)
        await steps.start("Build")
        await steps.succeed("Build")
        await steps.start("Test")
        await steps.fail("Test", detail: "3 failures")
        await steps.skip("Upload")
        await steps.finish()
        let lines = terminal.output(.standardError).split(separator: "\n").map(String.init)
        #expect(lines.count == 5)
        #expect(lines[0] == "→ Build")
        #expect(lines[1].hasPrefix("✔ Build ("))
        #expect(lines[3].hasPrefix("✖ Test (3 failures, "))
        #expect(lines[4] == "↷ Upload")
        #expect(await steps.state(of: "Test") == .failed)
    }

    @Test("An interactive step list ends with the final frame")
    func stepListInteractive() async {
        let terminal = ScriptedTerminal(input: [])
        let steps = StepList(["Build", "Upload"], terminal: terminal)
        await steps.start("Build")
        await steps.succeed("Build")
        await steps.finish()
        let output = terminal.output(.standardError)
        #expect(output.contains("○ Upload"))
        #expect(output.contains("\u{1B}[2A\r\u{1B}[J"))
        #expect(output.hasSuffix("○ Upload\n"))
    }

    @Test("A redirected live tail passes every line through")
    func liveTailRedirected() async {
        let terminal = ScriptedTerminal(input: [], environment: ScriptedTerminal.redirected)
        let tail = LiveTail("Building", terminal: terminal)
        await tail.start()
        await tail.append("one\ntw")
        await tail.append("o\r\nthree")
        await tail.succeed()
        #expect(terminal.output(.standardError).hasPrefix("→ Building\none\ntwo\r\nthree\n✔ Building ("))
    }

    @Test("An interactive live tail shows the last lines and reports them on failure")
    func liveTailFailure() async {
        let terminal = ScriptedTerminal(input: [])
        let tail = LiveTail("Building", terminal: terminal, visibleLineCount: 2, interval: .zero)
        await tail.start()
        await tail.append("a\nb\nc\nerror: boom\n")
        await tail.fail(reportLineCount: 2)
        let output = terminal.plainOutput(.standardError)
        #expect(output.contains("  c\n  error: boom\n"))
        #expect(output.hasSuffix("c\nerror: boom\n✖ Building (" + output.split(separator: "(").last.map(String.init)!))
    }

    @Test("Elapsed time formats compactly", arguments: [(0.85, "850ms"), (4.24, "4.2s"), (187, "3m 07s")])
    func elapsed(seconds: Double, expected: String) {
        #expect(formatElapsed(.milliseconds(Int(seconds * 1000))) == expected)
    }
}

private actor ManualAnimationSchedule {
    private var requests = 0
    private var sleepers: [CheckedContinuation<Void, any Error>] = []
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []

    func sleep(_ duration: Duration) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    sleepers.append(continuation)
                    requests += 1
                    for (count, observer) in observers where count <= requests { observer.resume() }
                    observers.removeAll { $0.0 <= requests }
                }
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    func waitForRequests(_ count: Int) async {
        if requests >= count { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }

    func advance() { sleepers.removeFirst().resume() }
    private func cancel() {
        for sleeper in sleepers { sleeper.resume(throwing: CancellationError()) }
        sleepers.removeAll()
    }
}

@Suite("Progress boundary regressions")
struct ProgressBoundaryTests {
    @Test("Non-finite fractions render without trapping", arguments: [Double.nan, .infinity, -.infinity])
    func nonfiniteProgress(_ value: Double) async {
        let terminal = ScriptedTerminal(input: [])
        let bar = ProgressBar("Upload", terminal: terminal, minimumRedrawInterval: .zero)
        await bar.update(fraction: value)
        await bar.update(completed: value, total: .infinity)
        await bar.stop()
        #expect(terminal.output(.standardError).contains("%"))
    }

    @Test("Progress summaries honor their stream for redirected output")
    func progressStream() async {
        let terminal = ScriptedTerminal(input: [], environment: ScriptedTerminal.redirected)
        await ProgressBar("Done", terminal: terminal, stream: .standardOutput).succeed()
        #expect(terminal.output().hasPrefix("✔ Done"))
        #expect(terminal.output(.standardError).isEmpty)
    }

    @Test("Negative tail counts and repeated completion are safe")
    func negativeTailCounts() async {
        let terminal = ScriptedTerminal(input: [])
        let tail = LiveTail("Tail", terminal: terminal, visibleLineCount: -2, retainedLineCount: -1)
        await tail.append("line\n")
        await tail.fail(reportLineCount: -1)
        let output = terminal.output(.standardError)
        await tail.succeed()
        await tail.start()
        await tail.append("ignored\n")
        #expect(terminal.output(.standardError) == output)
    }

    @Test("Tail retention bounds long lines and handles split carriage returns")
    func boundedTail() async {
        let terminal = ScriptedTerminal(input: [])
        let tail = LiveTail("Tail", terminal: terminal, retainedLineCount: 2, maximumRetainedBytes: 40)
        await tail.append(String(repeating: "日", count: 100))
        await tail.append("\nold\r")
        await tail.append("new\r")
        await tail.append("\nlast")
        await tail.fail()
        let output = terminal.plainOutput(.standardError)
        #expect(!output.contains("old"))
        #expect(output.contains("new\nlast\n✖ Tail"))
    }

    @Test("A long unterminated line is retained with a bounded truncation marker")
    func truncatedTail() async {
        let terminal = ScriptedTerminal(input: [])
        let tail = LiveTail("Tail", terminal: terminal, maximumRetainedBytes: 30)
        await tail.append(String(repeating: "日", count: 100))
        await tail.fail()
        #expect(terminal.plainOutput(.standardError).contains(" [truncated]\n✖ Tail"))
    }

    @Test("Redirected output forwards partial chunks immediately")
    func partialRedirectedTail() async {
        let terminal = ScriptedTerminal(input: [], environment: ScriptedTerminal.redirected)
        let tail = LiveTail("Tail", terminal: terminal)
        await tail.append("partial")
        await tail.append("")
        #expect(terminal.output(.standardError) == "partial")
        await tail.succeed()
        #expect(terminal.output(.standardError).hasPrefix("partial\n✔ Tail"))
    }

    @Test("ASCII progress fallback has no Unicode glyphs")
    func asciiProgress() async {
        let terminal = ScriptedTerminal(input: [], environment: TerminalEnvironment(variables: ["LANG": "C"]))
        let steps = StepList(["Step"], terminal: terminal)
        await steps.start("Step")
        await steps.succeed("Step")
        await steps.finish()
        let tail = LiveTail("Tail", terminal: terminal)
        await tail.start()
        await tail.succeed()
        #expect(terminal.output(.standardError).unicodeScalars.allSatisfy { $0.isASCII })
    }
}
