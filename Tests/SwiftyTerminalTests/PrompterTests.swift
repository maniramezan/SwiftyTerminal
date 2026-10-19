import SwiftyTerminal
import SwiftyTerminalTesting
import Testing

/// A terminal whose stdin is a TTY but whose stdout cannot host menus, so choices use the
/// numbered fallback while short answers still take one key.
private let keyOnly = TerminalEnvironment(
    variables: ["TERM": "dumb", "NO_COLOR": "1"],
    isInputTerminal: true,
    isOutputTerminal: true
)

@Suite("Prompter")
struct PrompterTests {
    @Test("A numbered choice of up to nine options takes one key and retries invalid keys")
    func singleKeyChoiceRetries() {
        let terminal = ScriptedTerminal(
            input: [.key(.character("x")), .key(.character("0")), .key(.character("4")), .key(.character("2"))],
            environment: keyOnly
        )
        #expect(Prompter(terminal: terminal).choose("Platform", options: ["iOS", "Android", "Both"], default: 0) == 1)
        #expect(terminal.remainingInput.isEmpty)
        #expect(terminal.unexpectedReads.isEmpty)
        #expect(terminal.plainOutput().contains("Enter a number between 1 and 3."))
    }

    @Test("A numbered choice of ten or more options reads a whole line")
    func multiDigitChoiceReadsLine() {
        let terminal = ScriptedTerminal(input: [.line("10")], environment: keyOnly)
        let choice = Prompter(terminal: terminal).choose("App", options: Array(repeating: "App", count: 10), default: 0)
        #expect(choice == 9)
        #expect(terminal.unexpectedReads.isEmpty)
    }

    @Test("Confirmation retries and accepts an uppercase key")
    func confirmationRetries() {
        let terminal = ScriptedTerminal(input: [.key(.character("x")), .key(.character("N"))], environment: keyOnly)
        #expect(Prompter(terminal: terminal).confirm("Continue?", default: true) == false)
        #expect(terminal.remainingInput.isEmpty)
        #expect(terminal.plainOutput().contains("Please answer y or n."))
    }

    @Test("Enter keeps the default, and end of input or Escape cancels")
    func defaultsAndCancellation() {
        let enter = ScriptedTerminal(input: [.key(.enter), .key(.enter)], environment: keyOnly)
        #expect(Prompter(terminal: enter).confirm("Continue?", default: false) == false)
        #expect(Prompter(terminal: enter).choose("App", options: ["A", "B"], default: 1) == 1)

        let eof = ScriptedTerminal(input: [], environment: keyOnly)
        #expect(Prompter(terminal: eof).confirm("Continue?", default: true) == nil)
        #expect(Prompter(terminal: eof).choose("App", options: ["A"], default: 0) == nil)

        let escape = ScriptedTerminal(input: [.key(.escape)], environment: keyOnly)
        #expect(Prompter(terminal: escape).confirm("Continue?", default: true) == nil)
    }

    @Test("Text and multiple selections read whole lines")
    func textAndMultipleSelections() {
        let terminal = ScriptedTerminal(input: [.line("1,3"), .line("1,3")], environment: keyOnly)
        let prompter = Prompter(terminal: terminal)
        #expect(prompter.ask("Path") == "1,3")
        #expect(prompter.chooseMany("Devices", options: ["A", "B", "C"], defaults: []) == [0, 2])
        #expect(terminal.unexpectedReads.isEmpty)
    }

    @Test("Validation asks again until the answer is accepted")
    func validationRetries() {
        let terminal = ScriptedTerminal(input: [.line("abc"), .line("42")], environment: keyOnly)
        let answer = Prompter(terminal: terminal).ask("Port", default: nil) { Int($0) == nil ? "Enter a number." : nil }
        #expect(answer == "42")
        #expect(terminal.plainOutput().contains("Enter a number."))
    }

    @Test("Single-key questions match case-insensitively and return the listed key")
    func askKey() {
        let terminal = ScriptedTerminal(input: [.key(.character("q")), .key(.character("S"))], environment: keyOnly)
        let key = Prompter(terminal: terminal).askKey("Test failed", keys: ["r", "s", "a"], default: "r")
        #expect(key == "s")
        #expect(terminal.plainOutput().contains("Test failed [R/s/a]: "))
        #expect(terminal.plainOutput().contains("Press one of r, s, a."))
    }

    @Test("Secrets are read through the hidden-input path")
    func secret() {
        let terminal = ScriptedTerminal(.secret(" hunter2 "))
        #expect(Prompter(terminal: terminal).askSecret("Password") == " hunter2 ")
        #expect(!terminal.output().contains("hunter2"))
    }

    @Test("Accepting a default rewrites the prompt line to show it")
    func defaultEcho() {
        let terminal = ScriptedTerminal(.line(""))
        #expect(Prompter(terminal: terminal).ask("Xcode scheme", default: "MyApp") == "MyApp")
        #expect(terminal.output() == "Xcode scheme [MyApp]: \u{1B}[1A\u{1B}[2K\rXcode scheme [MyApp]: MyApp\n")
    }

    @Test("Redirected input writes each accepted answer so transcripts stay readable")
    func redirectedTranscript() {
        let terminal = ScriptedTerminal(
            input: [.line(""), .line("y"), .line("2")],
            environment: ScriptedTerminal.redirected
        )
        let prompter = Prompter(terminal: terminal)
        #expect(prompter.ask("Scheme", default: "MyApp") == "MyApp")
        #expect(prompter.confirm("Upload?", default: false) == true)
        #expect(prompter.choose("Track", options: ["internal", "beta"], default: 0) == 1)
        let output = terminal.output()
        #expect(output.contains("Scheme [MyApp]: MyApp\n"))
        #expect(output.contains("Upload? [y/N]: yes\n"))
        #expect(output.contains("Choose 1-2 [1]: 2\n"))
        #expect(!output.contains("\u{1B}"))
    }

    @Test("Typed options map back to their values")
    func typedOptions() {
        enum Platform: String, CustomStringConvertible, CaseIterable {
            case ios, android
            var description: String { rawValue }
        }
        let terminal = ScriptedTerminal(.key(.down), .key(.enter))
        #expect(Prompter(terminal: terminal).choose("Platform", from: Platform.allCases) == .android)
    }
}

@Suite("Prompter menus")
struct PrompterMenuTests {
    @Test("Page jumps use the visible height, including filter rows", arguments: [false, true], [7, 24])
    func pageNavigation(filtering: Bool, terminalRows: Int) {
        let filterKeys: [ScriptedTerminal.Input] = filtering ? [.key(.character("/")), .key(.character("D"))] : []
        let terminal = ScriptedTerminal(
            input: filterKeys + [
                .key(.right), .key(.character(" ")), .key(.right), .key(.left), .key(.character(" ")), .key(.enter),
            ],
            size: TerminalSize(columns: 120, rows: terminalRows)
        )
        let options = (0..<20).map { "Device \($0)" }
        let pageHeight = min(8, terminalRows - (filtering ? 4 : 3))
        #expect(Prompter(terminal: terminal).chooseMany("Devices", options: options, defaults: [0]) == [0])
        #expect(terminal.plainOutput().contains("> [x] Device \(pageHeight)"))
        #expect(terminal.remainingInput.isEmpty)
        #expect(terminal.unexpectedReads.isEmpty)
    }

    @Test("Multiple selection toggles with Space and returns sorted indexes")
    func multipleSelection() {
        let terminal = ScriptedTerminal(
            .key(.down),
            .key(.character(" ")),
            .key(.down),
            .key(.character(" ")),
            .key(.enter)
        )
        #expect(
            Prompter(terminal: terminal).chooseMany("Devices", options: ["A", "B", "C"], defaults: [0]) == [0, 1, 2]
        )
    }

    @Test("Single selection wraps around, and Escape cancels")
    func singleSelectionWrapsAndCancels() {
        let terminal = ScriptedTerminal(.key(.up), .key(.enter), .key(.escape))
        let prompter = Prompter(terminal: terminal)
        #expect(prompter.choose("Platform", options: ["A", "B"], default: 0) == 1)
        #expect(prompter.chooseMany("Devices", options: ["A"], defaults: [0]) == nil)
    }

    @Test("Multiple selection requires at least one option and supports toggling all")
    func requiresSelection() {
        let terminal = ScriptedTerminal(
            .key(.character(" ")),
            .key(.enter),
            .key(.character("a")),
            .key(.character("a")),
            .key(.enter),
            .key(.down),
            .key(.character(" ")),
            .key(.enter)
        )
        #expect(Prompter(terminal: terminal).chooseMany("Devices", options: ["A", "B"], defaults: [0]) == [1])
        #expect(terminal.remainingInput.isEmpty)
    }

    @Test("A finished menu collapses to a one-line answer")
    func collapses() {
        let terminal = ScriptedTerminal(.key(.down), .key(.enter))
        _ = Prompter(terminal: terminal).choose("Setup method", options: ["Create .env", "Export vars"], default: 0)
        let output = terminal.output()
        #expect(output.hasSuffix("Setup method: Export vars\n"))
        #expect(output.contains("> (*) Export vars"))
        #expect(output.contains("Enter select"))
    }

    @Test("Running out of keys cancels instead of hanging")
    func endOfKeys() {
        let terminal = ScriptedTerminal(input: [])
        #expect(Prompter(terminal: terminal).choose("Platform", options: ["A"], default: 0) == nil)
    }
}

@Suite("Prompt boundary regressions")
struct PromptBoundaryTests {
    @Test("Secrets preserve every character returned by the terminal")
    func secretWhitespace() {
        let terminal = ScriptedTerminal(.secret(" \t pass \t "))
        #expect(Prompter(terminal: terminal).askSecret("Password") == " \t pass \t ")
        #expect(!terminal.output().contains("pass"))
    }

    @Test("Extreme numbered answers retry without integer overflow", arguments: [Int.min, Int.max, 0, -1])
    func extremeChoice(_ value: Int) {
        let terminal = ScriptedTerminal(
            input: [.line(String(value)), .line("1")],
            environment: ScriptedTerminal.redirected
        )
        #expect(Prompter(terminal: terminal).choose("Pick", options: ["A"], default: 0) == 0)
        #expect(terminal.remainingInput.isEmpty)
    }

    @Test("Key defaults are resolved through allowed keys")
    func defaultKey() {
        let terminal = ScriptedTerminal(.key(.enter), .key(.character("y")), .key(.enter))
        let prompter = Prompter(terminal: terminal)
        #expect(prompter.askKey("Pick", keys: ["y", "n"], default: "x") == "y")
        #expect(prompter.askKey("Pick", keys: ["y", "n"], default: "Y") == "y")
    }

    @Test("Redirected multiple defaults are sorted and unique")
    func multipleDefaults() {
        let terminal = ScriptedTerminal(input: [.line("")], environment: ScriptedTerminal.redirected)
        #expect(
            Prompter(terminal: terminal).chooseMany("Pick", options: ["A", "B"], defaults: [1, -1, 0, 1, 2]) == [0, 1]
        )
    }
}
