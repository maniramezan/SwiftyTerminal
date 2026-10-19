import SwiftyTerminal
import SwiftyTerminalTesting
import Testing

@Suite("Color themes")
struct ThemeTests {
    private let theme = TerminalTheme(
        accent: .magenta,
        success: .brightGreen,
        error: .brightRed,
        warning: .brightYellow,
        info: .brightBlue
    )

    @Test("The default palette preserves the original component colors")
    func defaults() {
        #expect(TerminalTheme.default == TerminalTheme())
        #expect(TerminalTheme.default.accent == .cyan)
        #expect(TerminalTheme.default.success == .green)
        #expect(TerminalTheme.default.error == .red)
        #expect(TerminalTheme.default.warning == .yellow)
        #expect(TerminalTheme.default.info == .blue)
        #expect(TerminalTheme(accent: .magenta).success == .green)
    }

    @Test("Semantic text uses the palette while explicit colors keep their meaning")
    func semanticText() {
        let styler = Styler(isEnabled: true, theme: theme)
        #expect(styler.accent("a") == "\u{1B}[35ma\u{1B}[0m")
        #expect(styler.success("s") == "\u{1B}[92ms\u{1B}[0m")
        #expect(styler.error("e") == "\u{1B}[91me\u{1B}[0m")
        #expect(styler.warning("w") == "\u{1B}[93mw\u{1B}[0m")
        #expect(styler.info("i") == "\u{1B}[94mi\u{1B}[0m")
        #expect(styler.cyan("a") == "\u{1B}[36ma\u{1B}[0m")
        #expect(styler.red("e") == "\u{1B}[31me\u{1B}[0m")
        #expect(Styler(isEnabled: false, theme: theme).accent("a") == "a")
        let resolved = Styler(
            stream: .standardOutput,
            mode: .always,
            environment: .init(variables: ["COLORTERM": "truecolor"]),
            theme: theme
        )
        #expect(resolved == styler)
    }

    @Test("Themes are independent values and existing stylers can change palette")
    func valueSemantics() {
        var customized = TerminalTheme.default
        customized.accent = .brightMagenta
        var styler = Styler(isEnabled: true, theme: customized)
        customized.success = .blue
        #expect(styler.theme.success == .green)
        #expect(TerminalTheme.default.accent == .cyan)
        styler.theme = theme
        #expect(styler.accent("a") == "\u{1B}[35ma\u{1B}[0m")
    }

    @Test("Console headings, keys, statuses, checks and alerts share the palette")
    func console() {
        let terminal = ScriptedTerminal(input: [])
        let console = Console(terminal: terminal, colorMode: .always, theme: theme)
        console.header("Title")
        console.keyValue("Key", "Value", keyWidth: 3)
        console.success("Success")
        console.error("Error")
        console.warning("Warning")
        console.info("Info")
        console.check("Pass", passed: true)
        console.check("Fail", passed: false)
        let output = terminal.output()
        #expect(output.contains("\u{1B}[1m\u{1B}[35m=== Title ===\u{1B}[0m"))
        #expect(output.contains("\u{1B}[35mKey\u{1B}[0m"))
        #expect(output.contains("\u{1B}[92mSuccess\u{1B}[0m"))
        #expect(output.contains("\u{1B}[91mError\u{1B}[0m"))
        #expect(output.contains("\u{1B}[93mWarning\u{1B}[0m"))
        #expect(output.contains("\u{1B}[94mℹ\u{1B}[0m"))
        #expect(output.contains("\u{1B}[92mPass\u{1B}[0m"))
        #expect(output.contains("\u{1B}[91mFail\u{1B}[0m"))
        for (kind, code) in [(Alert.Kind.success, "92"), (.error, "91"), (.warning, "93"), (.info, "94")] {
            console.alert(kind, title: "Alert")
            #expect(terminal.output().contains("\u{1B}[\(code)m╭─ \u{1B}[0m"))
        }
        #expect(terminal.output(.standardError).isEmpty)
    }

    @Test("Interactive selections and their summaries use the accent")
    func interactivePrompts() {
        let terminal = ScriptedTerminal(.key(.enter))
        let prompter = Prompter(terminal: terminal, colorMode: .always, theme: theme)
        prompter.say("Title")
        #expect(prompter.choose("Pick", options: ["A", "B"], default: 0) == 0)
        let output = terminal.output()
        #expect(output.contains("\u{1B}[1m\u{1B}[35mTitle\u{1B}[0m"))
        #expect(output.contains("\u{1B}[35m> (*) A\u{1B}[0m"))
        #expect(output.contains("\u{1B}[35mA\u{1B}[0m"))
    }

    @Test("Numbered choices and validation messages use their semantic colors")
    func redirectedPrompts() {
        let terminal = ScriptedTerminal(
            input: [.line("1"), .line("bad"), .line("good")],
            environment: ScriptedTerminal.redirected
        )
        let prompter = Prompter(terminal: terminal, colorMode: .always, theme: theme)
        #expect(prompter.choose("Pick", options: ["A"], default: 0) == 0)
        #expect(prompter.ask("Name", default: nil, validate: { $0 == "bad" ? "Retry" : nil }) == "good")
        let output = terminal.output()
        #expect(output.contains("\u{1B}[1m\u{1B}[35mPick:\u{1B}[0m"))
        #expect(output.contains("\u{1B}[35m1)\u{1B}[0m"))
        #expect(output.contains("\u{1B}[93mRetry\u{1B}[0m"))
    }

    @Test(
        "Themes respect automatic color suppression and explicit disabling",
        arguments: [
            (ScriptedTerminal.interactive, ColorMode.auto),
            (ScriptedTerminal.redirected, .auto),
            (TerminalEnvironment(variables: ["TERM": "dumb"], isOutputTerminal: true), .auto),
            (TerminalEnvironment(variables: ["FORCE_COLOR": "1"]), .never),
        ]
    )
    func plainOutput(environment: TerminalEnvironment, mode: ColorMode) async {
        let terminal = ScriptedTerminal(input: [.line("1")], environment: environment)
        let console = Console(terminal: terminal, colorMode: mode, theme: theme)
        console.header("Title")
        console.success("Done")
        console.alert(.warning, title: "Warning")
        Prompter(terminal: terminal, colorMode: mode, theme: theme).say("Prompt")
        let bar = ProgressBar("Upload", terminal: terminal, colorMode: mode, theme: theme)
        await bar.fail()
        #expect(!terminal.output().contains("\u{1B}"))
        #expect(!terminal.output(.standardError).contains("\u{1B}"))
    }

    @Test("Progress bars, steps and live tails share accent and result colors on stderr")
    func progress() async {
        let terminal = ScriptedTerminal(input: [])
        let bar = ProgressBar("Upload", terminal: terminal, colorMode: .always, theme: theme, width: 5)
        await bar.update(fraction: 1)
        await bar.succeed()
        await bar.fail()
        #expect(terminal.output(.standardError).contains("\u{1B}[35m█████\u{1B}[0m"))
        #expect(terminal.output(.standardError).contains("\u{1B}[92m✔\u{1B}[0m"))
        #expect(terminal.output(.standardError).contains("\u{1B}[91m✖\u{1B}[0m"))

        let stepsTerminal = ScriptedTerminal(input: [])
        let steps = StepList(["Build", "Test"], terminal: stepsTerminal, colorMode: .always, theme: theme)
        await steps.start("Build")
        await steps.succeed("Build")
        await steps.fail("Test")
        await steps.finish()
        let stepsOutput = stepsTerminal.output(.standardError)
        #expect(stepsOutput.contains("\u{1B}[35m⠋\u{1B}[0m"))
        #expect(stepsOutput.contains("\u{1B}[92m✔\u{1B}[0m"))
        #expect(stepsOutput.contains("\u{1B}[91m✖\u{1B}[0m"))

        for succeeds in [true, false] {
            let tailTerminal = ScriptedTerminal(input: [])
            let tail = LiveTail("Build", terminal: tailTerminal, colorMode: .always, theme: theme)
            await tail.start()
            if succeeds { await tail.succeed() } else { await tail.fail() }
            let output = tailTerminal.output(.standardError)
            #expect(output.contains("\u{1B}[35m⠋\u{1B}[0m"))
            #expect(output.contains(succeeds ? "\u{1B}[92m✔\u{1B}[0m" : "\u{1B}[91m✖\u{1B}[0m"))
            #expect(tailTerminal.output().isEmpty)
        }
        #expect(terminal.output().isEmpty)
        #expect(stepsTerminal.output().isEmpty)
    }

    @Test("Spinner and its operation helper forward the theme for both outcomes")
    func spinner() async {
        struct Failure: Error {}
        let terminal = ScriptedTerminal(input: [])
        let spinner = Spinner("Work", terminal: terminal, colorMode: .always, theme: theme)
        await spinner.succeed()
        #expect(terminal.output(.standardError).contains("\u{1B}[92m✔\u{1B}[0m"))
        await spinner.fail()
        #expect(terminal.output(.standardError).contains("\u{1B}[91m✖\u{1B}[0m"))

        let helperTerminal = ScriptedTerminal(input: [])
        let value = await withSpinner(
            "Work",
            terminal: helperTerminal,
            colorMode: .always,
            theme: theme,
            showsResult: true
        ) {
            42
        }
        #expect(value == 42)
        await #expect(throws: Failure.self) {
            try await withSpinner("Work", terminal: helperTerminal, colorMode: .always, theme: theme, showsResult: true)
            {
                throw Failure()
            }
        }
        #expect(helperTerminal.output(.standardError).contains("\u{1B}[92m✔\u{1B}[0m"))
        #expect(helperTerminal.output(.standardError).contains("\u{1B}[91m✖\u{1B}[0m"))
        #expect(helperTerminal.output().isEmpty)
    }
}
