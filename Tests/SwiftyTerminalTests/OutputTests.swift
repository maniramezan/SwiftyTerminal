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

@Suite("Rendering boundary regressions")
struct RenderingBoundaryTests {
    @Test("Live frames strip cursor commands and keep safe styling and hyperlinks")
    func escapeSafety() {
        let terminal = ScriptedTerminal(input: [])
        var region = LiveRegion(terminal: terminal, stream: .standardError)
        let styler = Styler(isEnabled: true)
        region.render([
            "a\u{1B}[2Ab\u{1B}[2J\u{1B}]0;title\u{07}c", styler.bold("safe"),
            styler.hyperlink("link", url: "https://example.com"),
        ])
        region.commit(["d\u{1B}[2Je"])
        let output = terminal.output(.standardError)
        #expect(output.hasPrefix("abc\n"))
        #expect(!output.contains("\u{1B}[2A"))
        #expect(!output.contains("\u{1B}[2J"))
        #expect(!output.contains("]0;title"))
        #expect(output.contains(styler.bold("safe")))
        #expect(output.contains(styler.hyperlink("link", url: "https://example.com")))
        #expect(output.hasSuffix("de\n"))
    }

    @Test("Live frames reserve a screen row and constrain width")
    func frameBounds() {
        let terminal = ScriptedTerminal(input: [], size: TerminalSize(columns: 8, rows: 3))
        var region = LiveRegion(terminal: terminal, stream: .standardError)
        region.render(["1234567890", "two", "three", "four"])
        region.clear()
        #expect(terminal.output(.standardError) == "123456…\ntwo\n\u{1B}[2A\r\u{1B}[J")
    }

    @Test("Alerts and menus respect even zero and tiny bounds", arguments: [0, 1, 2, 8, 13, 14])
    func smallBounds(_ bound: Int) {
        let lines = Alert(kind: .error, title: "Failure", lines: ["Explanation"])
            .render(styler: .plain, symbols: .ascii, maximumWidth: bound)
        #expect(lines.allSatisfy { TextMetrics.displayWidth($0) <= bound })
        let menu = SelectionMenu(title: "Pick", options: ["A", "B"], allowsMultiple: false)
        #expect(menu.render(styler: .plain, maximumRows: bound).count <= bound)
    }

    @Test("ASCII truncation stays ASCII")
    func asciiTruncation() {
        let terminal = ScriptedTerminal(
            input: [],
            environment: TerminalEnvironment(variables: ["LANG": "C"]),
            size: TerminalSize(columns: 8, rows: 3)
        )
        var region = LiveRegion(terminal: terminal, stream: .standardError)
        region.render(["long title to truncate"])
        #expect(terminal.output(.standardError).unicodeScalars.allSatisfy { $0.isASCII })
    }
}

extension RenderingBoundaryTests {
    @Test("Styled tables omit empty final columns and trailing cell spaces")
    func styledTableWhitespace() {
        let lines = Table(headers: ["First", "Last"], rows: [["value ", ""], [" ", " "]])
            .render(styler: Styler(isEnabled: true), unicode: false)
        #expect(TextMetrics.strippingEscapes(lines[2]) == "value")
        #expect(lines[3].isEmpty)
    }

    @Test("Malformed escape strings and incomplete styles cannot escape a live line")
    func malformedEscapes() {
        let terminal = ScriptedTerminal(input: [])
        var region = LiveRegion(terminal: terminal, stream: .standardError)
        region.render([
            "safe\u{1B}[123", "a\u{1B}Pdiscard\u{1B}\\b", "\u{1B}[31mred", "\u{1B}]8;;https://example.com\u{1B}\\link",
        ])
        let output = terminal.output(.standardError)
        #expect(output.hasPrefix("safe\nab\n\u{1B}[31mred\u{1B}[0m\n"))
        #expect(output.hasSuffix("link\u{1B}]8;;\u{1B}\\\n"))
    }
}
