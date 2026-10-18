import SwiftyTerminal
import SwiftyTerminalTesting
import Testing

@Suite("Documentation recipes")
struct DocumentationExamplesTests {
    @Test("Redirected and interactive getting-started examples select the same option")
    func prompts() {
        let terminal = ScriptedTerminal(input: [.line("2")], environment: ScriptedTerminal.redirected)
        #expect(Prompter(terminal: terminal).choose("Platform", options: ["iOS", "Android"], default: 0) == 1)
        let interactive = ScriptedTerminal(.key(.down), .key(.enter))
        #expect(Prompter(terminal: interactive).choose("Platform", options: ["iOS", "Android"], default: 0) == 1)
        #expect(interactive.remainingInput.isEmpty)
        #expect(interactive.unexpectedReads.isEmpty)
    }

    @Test("The progress and cancellation recipes preserve stdout and return values")
    func progress() async throws {
        let terminal = ScriptedTerminal(input: [], environment: ScriptedTerminal.redirected)
        let bar = ProgressBar("Uploading", terminal: terminal)
        await bar.update(completed: 3, total: 10)
        await bar.succeed("Uploaded")
        #expect(terminal.output().isEmpty)
        #expect(terminal.output(.standardError).contains("Uploaded"))
        let result = try await withSpinner("Inspecting", terminal: terminal) {
            try Task.checkCancellation()
            return 42
        }
        #expect(result == 42)
    }
}
