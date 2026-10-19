import SwiftyTerminal
import SwiftyTerminalTesting
import Testing

@Suite("Terminal colors")
struct TerminalColorTests {
    @Test(
        "Named colors keep their palette entries at every depth",
        arguments: [ColorDepth.ansi16, .ansi256, .trueColor]
    )
    func namedColors(_ depth: ColorDepth) {
        let colors: [TerminalColor] = [
            .black, .red, .green, .yellow, .blue, .magenta, .cyan, .white,
            .gray, .brightRed, .brightGreen, .brightYellow, .brightBlue, .brightMagenta, .brightCyan, .brightWhite,
        ]
        let codes = Array(30...37) + Array(90...97)
        let styler = Styler(isEnabled: true, colorDepth: depth)
        for (color, code) in zip(colors, codes) {
            #expect(styler.apply("text", color: color) == "\u{1B}[\(code)mtext\u{1B}[0m")
        }
    }

    @Test(
        "RGB colors preserve all channels at true-color depth",
        arguments: [(UInt8(0), UInt8(0), UInt8(0)), (255, 255, 255), (120, 80, 255)]
    )
    func trueColor(red: UInt8, green: UInt8, blue: UInt8) {
        let color = TerminalColor.rgb(red, green, blue)
        #expect(color == .rgb(red, green, blue))
        #expect(
            Styler(isEnabled: true).apply("text", color: color, styles: [.bold, .underline])
                == "\u{1B}[1m\u{1B}[4m\u{1B}[38;2;\(red);\(green);\(blue)mtext\u{1B}[0m"
        )
        #expect(Styler(isEnabled: true).apply("", color: color).isEmpty)
        #expect(Styler(isEnabled: false).apply("text", color: color, styles: [.bold]) == "text")
    }

    @Test(
        "RGB colors choose the nearest fixed cube or grayscale entry in the 256-color palette",
        arguments: [
            (TerminalColor.rgb(0, 0, 0), 16), (.rgb(255, 255, 255), 231),
            (.rgb(0, 95, 135), 24), (.rgb(128, 128, 128), 244), (.rgb(120, 80, 255), 99),
        ]
    )
    func palette256(color: TerminalColor, index: Int) {
        #expect(
            Styler(isEnabled: true, colorDepth: .ansi256).apply("text", color: color)
                == "\u{1B}[38;5;\(index)mtext\u{1B}[0m"
        )
    }

    @Test(
        "RGB colors approximate the standard sixteen-color palette",
        arguments: [
            (TerminalColor.rgb(0, 0, 0), 30), (.rgb(255, 255, 255), 97), (.rgb(128, 0, 0), 31),
            (.rgb(255, 0, 0), 91), (.rgb(128, 128, 128), 90), (.rgb(120, 80, 255), 90),
        ]
    )
    func palette16(color: TerminalColor, code: Int) {
        #expect(
            Styler(isEnabled: true, colorDepth: .ansi16).apply("text", color: color)
                == "\u{1B}[\(code)mtext\u{1B}[0m"
        )
    }

    @Test(
        "Environment color-depth detection is conservative and case-insensitive",
        arguments: [
            ([String: String](), ColorDepth.ansi16), (["TERM": "xterm"], .ansi16),
            (["TERM": "XTERM-256COLOR"], .ansi256), (["COLORTERM": "TRUECOLOR"], .trueColor),
            (["COLORTERM": "24bit", "TERM": "xterm-256color"], .trueColor),
            (["COLORTERM": "yes"], .ansi16), (["TERM": "xterm-direct"], .trueColor),
            (["TERM": "dumb", "COLORTERM": "truecolor"], .ansi16),
        ]
    )
    func detection(variables: [String: String], expected: ColorDepth) {
        let environment = TerminalEnvironment(variables: variables)
        #expect(environment.colorDepth == expected)
        let styler = Styler(stream: .standardError, mode: .always, environment: environment)
        #expect(styler.isEnabled)
        #expect(styler.colorDepth == expected)
    }

    @Test(
        "RGB themes reach every component at the detected depth",
        arguments: [
            (["COLORTERM": "truecolor"], "\u{1B}[38;2;120;80;255m"),
            (["TERM": "xterm-256color"], "\u{1B}[38;5;99m"),
            ([String: String](), "\u{1B}[90m"),
        ]
    )
    func components(variables: [String: String], sequence: String) async {
        let environment = TerminalEnvironment(
            variables: variables.merging(["LANG": "en_US.UTF-8"]) { _, value in value },
            isInputTerminal: true,
            isOutputTerminal: true,
            isErrorTerminal: true
        )
        let terminal = ScriptedTerminal(input: [.key(.enter)], environment: environment)
        let color = TerminalColor.rgb(120, 80, 255)
        let theme = TerminalTheme(accent: color, success: color, error: color, warning: color, info: color)
        let console = Console(terminal: terminal, theme: theme)
        console.header("RGB")
        console.success("Success")
        console.error("Error")
        console.warning("Warning")
        console.info("Info")
        console.alert(.info, title: "Alert")
        let prompter = Prompter(terminal: terminal, theme: theme)
        #expect(prompter.choose("Pick", options: ["Option"], default: 0) == 0)
        let output = terminal.output()
        #expect(output.contains("\u{1B}[1m" + sequence + "=== RGB ==="))
        for text in ["Success", "Error", "Warning", "ℹ", "╭─ ", "> (*) Option", "Option"] {
            #expect(output.contains(sequence + text + ANSIStyle.reset))
        }

        let bar = ProgressBar("Bar", terminal: terminal, theme: theme, width: 5)
        await bar.update(fraction: 1)
        await bar.succeed()
        #expect(terminal.output(.standardError).contains(sequence + "█████" + ANSIStyle.reset))
        let steps = StepList(["Step"], terminal: terminal, theme: theme)
        await steps.start("Step")
        await steps.fail("Step")
        await steps.finish()
        let tail = LiveTail("Tail", terminal: terminal, theme: theme)
        await tail.start()
        await tail.succeed()
        let spinner = Spinner("Spinner", terminal: terminal, theme: theme)
        await spinner.fail()
        await withSpinner("Operation", terminal: terminal, theme: theme, showsResult: true) {}
        let progress = terminal.output(.standardError)
        #expect(progress.contains(sequence + "⠋" + ANSIStyle.reset))
        #expect(progress.contains(sequence + "✖" + ANSIStyle.reset))
        #expect(progress.contains(sequence + "✔" + ANSIStyle.reset))
        #expect(TextMetrics.displayWidth(console.styler.accent("RGB")) == 3)
    }

    @Test(
        "RGB themes honor per-stream color policy",
        arguments: [
            (["COLORTERM": "truecolor", "NO_COLOR": "1"], ColorMode.auto),
            (["COLORTERM": "truecolor", "FORCE_COLOR": "1"], .never),
            (["COLORTERM": "truecolor", "TERM": "dumb"], .auto),
            (["COLORTERM": "truecolor"], .auto),
        ]
    )
    func disabled(variables: [String: String], mode: ColorMode) async {
        let terminal = ScriptedTerminal(input: [], environment: TerminalEnvironment(variables: variables))
        let theme = TerminalTheme(accent: .rgb(120, 80, 255), success: .rgb(0, 255, 0))
        Console(terminal: terminal, colorMode: mode, theme: theme).header("RGB")
        let bar = ProgressBar("Bar", terminal: terminal, colorMode: mode, theme: theme)
        await bar.succeed()
        #expect(terminal.output() == "\n=== RGB ===\n")
        #expect(!terminal.output(.standardError).contains("\u{1B}"))
    }

    @Test("Redirected stdout stays plain while terminal stderr emits RGB")
    func separateStreams() async {
        let environment = TerminalEnvironment(variables: ["COLORTERM": "truecolor"], isErrorTerminal: true)
        let terminal = ScriptedTerminal(input: [], environment: environment)
        let theme = TerminalTheme(accent: .rgb(120, 80, 255), success: .rgb(0, 255, 0))
        Console(terminal: terminal, theme: theme).header("RGB")
        await ProgressBar("Bar", terminal: terminal, theme: theme).succeed()
        #expect(terminal.output() == "\n=== RGB ===\n")
        #expect(terminal.output(.standardError).contains("\u{1B}[38;2;0;255;0m"))
    }
}
