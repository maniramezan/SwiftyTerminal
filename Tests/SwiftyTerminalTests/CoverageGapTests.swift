import Foundation
import SwiftyTerminal
import SwiftyTerminalLineEditor
import SwiftyTerminalTesting
import Testing

@Suite("Console")
struct ConsoleTests {
    @Test("Writes dividers, info lines, tables and alerts to the chosen stream")
    func structuredOutput() {
        let terminal = ScriptedTerminal(input: [])
        let console = Console(terminal: terminal, stream: .standardError)
        console.divider(width: 3)
        console.info("Note")
        console.print()
        console.table(headers: ["A", "B"], rows: [["1", "2"]])
        console.alert(.success, title: "Done")
        #expect(terminal.output(.standardOutput).isEmpty)
        let lines = terminal.output(.standardError).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[0] == "───")
        #expect(lines[1] == "ℹ Note")
        #expect(lines[2] == "")
        #expect(lines[3] == "A  B")
        #expect(lines[5] == "1  2")
        #expect(lines[6].hasPrefix("╭─ ✔ Done"))
    }

    @Test("Alerts of every kind use their own glyph")
    func alertKinds() {
        let symbols = Symbols.ascii
        for (kind, glyph) in [(Alert.Kind.info, "[i]"), (.warning, "[!]"), (.error, "[x]"), (.success, "[ok]")] {
            #expect(Alert(kind: kind, title: "T").render(styler: .plain, symbols: symbols)[0].contains(glyph))
        }
    }

    @Test("Tables without headers or columns render rows only")
    func tableEdges() {
        #expect(Table(headers: [], rows: []).render(styler: .plain, unicode: true).isEmpty)
        #expect(
            Table(headers: [], rows: [["a", "b"], ["ccc"]]).render(styler: .plain, unicode: true) == [
                "a    b", "ccc",
            ]
        )
    }
}

@Suite("Prompting conveniences")
struct PromptingConvenienceTests {
    @Test("Typed multiple choice returns the chosen values in order")
    func typedChooseMany() {
        let terminal = ScriptedTerminal(.key(.character("a")), .key(.enter))
        let picked = Prompter(terminal: terminal).chooseMany("Steps", from: ["build", "test"], defaults: ["test"])
        #expect(picked == ["build", "test"])
    }

    @Test("Empty option lists and empty key sets return nil without reading")
    func emptyOptions() {
        let terminal = ScriptedTerminal(input: [])
        let prompter = Prompter(terminal: terminal)
        #expect(prompter.choose("X", options: [], default: 0) == nil)
        #expect(prompter.chooseMany("X", options: [], defaults: []) == nil)
        #expect(prompter.askKey("X", keys: [], default: nil) == nil)
        #expect(terminal.output().isEmpty)
    }

    @Test("say writes a styled status line")
    func say() {
        let terminal = ScriptedTerminal(input: [])
        Prompter(terminal: terminal, colorMode: .always).say("Setting up")
        #expect(terminal.output() == "\u{1B}[1m\u{1B}[36mSetting up\u{1B}[0m\n")
    }

    @Test("Redirected secrets end the prompt line without echoing the value")
    func redirectedSecret() {
        let terminal = ScriptedTerminal(input: [.secret("hunter2")], environment: ScriptedTerminal.redirected)
        #expect(Prompter(terminal: terminal).askSecret("Password") == "hunter2")
        #expect(terminal.output() == "Password: \n")
    }

    @Test("A menu given a scripted line records the mismatch and cancels")
    func mismatchedRead() {
        let terminal = ScriptedTerminal(input: [.line("yes")])
        #expect(Prompter(terminal: terminal).choose("Go?", options: ["a", "b"], default: 0) == nil)
        #expect(terminal.unexpectedReads.count == 1)
        #expect(terminal.remainingInput == [.line("yes")])
    }
}

@Suite("Standard streams")
struct StandardStreamTests {
    @Test("The current environment reflects the process variables")
    func currentEnvironment() {
        let environment = TerminalEnvironment.current()
        #expect(environment.variables == ProcessInfo.processInfo.environment)
        #expect(StandardTerminal(environment: environment).environment == environment)
    }

    @Test("Terminal size is always positive")
    func size() {
        let size = StandardTerminal().size
        #expect(size.columns > 0)
        #expect(size.rows > 0)
    }

    @Test("Writing an empty string to either stream is harmless")
    func emptyWrites() {
        let terminal = StandardTerminal()
        terminal.write("", to: .standardOutput)
        terminal.write("", to: .standardError)
        StandardTerminal.lineBufferStandardOutput()
    }
}

@Suite("LineEditor")
struct LineEditorTests {
    @Test("History saves to and loads from the configured file")
    func history() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "swifty-terminal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appending(path: "history").path
        let editor = LineEditor(historyPath: path)
        editor.loadHistory()
        editor.saveHistory()
        #expect(editor.historyPath == path)
        LineEditor().saveHistory()
        LineEditor().loadHistory()
    }

    @Test("Completions can be replaced repeatedly")
    func completions() {
        let editor = LineEditor()
        editor.setCompletions(commands: ["tap", "tap_element"], arguments: ["tap": ["x=", "y="]])
        editor.setCompletions(commands: ["/help", "/quit"])
        editor.setCompletions(commands: [])
    }
}
