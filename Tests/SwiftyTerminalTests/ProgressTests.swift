import SwiftyTerminal
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
        try? await Task.sleep(for: .milliseconds(30))
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
        let spinner = Spinner("Inspecting", terminal: terminal, delay: .zero, interval: .milliseconds(5))
        await spinner.start()
        try? await Task.sleep(for: .milliseconds(40))
        await spinner.succeed("Inspected")
        let output = terminal.plainOutput(.standardError)
        #expect(output.contains("⠋ Inspecting"))
        #expect(output.contains("✔ Inspected ("))
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
        let lines = terminal.output(.standardError).split(separator: "\n").map(String.init)
        #expect(lines.prefix(4) == ["→ Building", "one", "two", "three"])
        #expect(lines[4].hasPrefix("✔ Building ("))
    }

    @Test("An interactive live tail shows the last lines and reports them on failure")
    func liveTailFailure() async {
        let terminal = ScriptedTerminal(input: [])
        let tail = LiveTail("Building", terminal: terminal, visibleLineCount: 2)
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
