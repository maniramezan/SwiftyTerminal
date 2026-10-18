import SwiftyTerminal
import SwiftyTerminalLineEditor
import SwiftyTerminalTesting
import Testing

@Suite("Output")
struct OutputTests {
    @Test("Console writes status lines with Unicode glyphs")
    func statusLines() {
        let terminal = ScriptedTerminal(input: [])
        let console = Console(terminal: terminal)
        console.success("Built")
        console.warning("Slow")
        console.check("Xcode", passed: false)
        console.keyValue("Scheme", "MyApp", keyWidth: 8)
        #expect(terminal.output() == "✔ Built\n⚠ Slow\n  ✖ Xcode\n  Scheme   MyApp\n")
    }

    @Test("Console falls back to ASCII glyphs outside a UTF-8 locale")
    func asciiGlyphs() {
        let terminal = ScriptedTerminal(input: [], environment: TerminalEnvironment(variables: ["LANG": "C"]))
        Console(terminal: terminal).error("Failed")
        #expect(terminal.output() == "[x] Failed\n")
    }

    @Test("Console honors an explicit color mode")
    func colorMode() {
        let terminal = ScriptedTerminal(input: [], environment: ScriptedTerminal.redirected)
        Console(terminal: terminal, colorMode: .always).header("Doctor")
        #expect(terminal.output() == "\n\u{1B}[1m\u{1B}[36m=== Doctor ===\u{1B}[0m\n")
    }

    @Test("Tables align by display width without trailing spaces")
    func table() {
        let lines = Table(headers: ["Name", "Platform"], rows: [["日本", "iOS"], ["Pixel 9", "Android"]])
            .render(styler: .plain, unicode: false)
        #expect(lines == ["Name     Platform", "-------  --------", "日本     iOS", "Pixel 9  Android"])
    }

    @Test("Alerts box the title, body and numbered next steps")
    func alert() {
        let lines = Alert(kind: .error, title: "Upload failed", lines: ["Key rejected."], nextSteps: ["Run doctor"])
            .render(styler: .plain, symbols: .ascii)
        #expect(
            lines == [
                "+- [x] Upload failed -+",
                "| Key rejected.       |",
                "|                     |",
                "| Next steps:         |",
                "|   1. Run doctor     |",
                "+---------------------+",
            ]
        )
        #expect(Set(lines.map(TextMetrics.displayWidth)).count == 1)
    }

    @Test("Alerts stay within the maximum width")
    func alertWidth() {
        let lines = Alert(kind: .info, title: "T", lines: [String(repeating: "x", count: 200)])
            .render(styler: .plain, symbols: .unicode, maximumWidth: 40)
        #expect(lines.allSatisfy { TextMetrics.displayWidth($0) == 40 })
    }

    @Test("Live regions rewind over the previous frame")
    func liveRegion() {
        let terminal = ScriptedTerminal(input: [])
        var region = LiveRegion(terminal: terminal, stream: .standardError)
        region.render(["a", "b"])
        region.render(["c"])
        region.commit(["done"])
        #expect(terminal.output(.standardError) == "a\nb\n\u{1B}[2A\r\u{1B}[Jc\n\u{1B}[1A\r\u{1B}[Jdone\n")
    }

    @Test("Completion prefers prefixes and optionally falls back to substrings")
    func completionMatching() {
        #expect(LineEditor.completionMatches("tap_element", text: "tap", preferPrefix: true))
        #expect(!LineEditor.completionMatches("tap_element", text: "elem", preferPrefix: true))
        #expect(LineEditor.completionMatches("tap_element", text: "elem", preferPrefix: false))
    }
}
