import SwiftyTerminal
import Testing

@Suite("TerminalEnvironment")
struct TerminalEnvironmentTests {
    private func environment(_ variables: [String: String], tty: Bool = true) -> TerminalEnvironment {
        TerminalEnvironment(variables: variables, isInputTerminal: tty, isOutputTerminal: tty, isErrorTerminal: false)
    }

    @Test("Auto color follows the stream, NO_COLOR, FORCE_COLOR and TERM=dumb")
    func autoColor() {
        #expect(environment([:]).isColorEnabled(for: .standardOutput))
        #expect(!environment([:]).isColorEnabled(for: .standardError))
        #expect(!environment([:], tty: false).isColorEnabled(for: .standardOutput))
        #expect(!environment(["NO_COLOR": "1"]).isColorEnabled(for: .standardOutput))
        #expect(environment(["NO_COLOR": ""]).isColorEnabled(for: .standardOutput))
        #expect(environment(["FORCE_COLOR": "1"], tty: false).isColorEnabled(for: .standardOutput))
        #expect(!environment(["FORCE_COLOR": "0"], tty: false).isColorEnabled(for: .standardOutput))
        #expect(!environment(["NO_COLOR": "1", "FORCE_COLOR": "1"]).isColorEnabled(for: .standardOutput))
        #expect(!environment(["TERM": "dumb"]).isColorEnabled(for: .standardOutput))
    }

    @Test("Explicit color modes override the environment")
    func explicitModes() {
        #expect(environment(["NO_COLOR": "1"], tty: false).isColorEnabled(for: .standardOutput, mode: .always))
        #expect(!environment(["FORCE_COLOR": "1"]).isColorEnabled(for: .standardOutput, mode: .never))
    }

    @Test("Unicode support comes from a UTF-8 locale")
    func unicode() {
        #expect(environment(["LANG": "en_US.UTF-8"]).supportsUnicode)
        #expect(environment(["LC_ALL": "C.utf8"]).supportsUnicode)
        #expect(!environment(["LANG": "C"]).supportsUnicode)
        #expect(!environment(["LANG": "en_US.UTF-8", "TERM": "dumb"]).supportsUnicode)
        #expect(Symbols.for(environment(["LANG": "C"])) == .ascii)
    }

    @Test("Menus need interactive stdin and stdout that understand cursor movement")
    func interactiveSelection() {
        #expect(environment([:]).supportsInteractiveSelection)
        #expect(!environment(["TERM": "dumb"]).supportsInteractiveSelection)
        #expect(!environment([:], tty: false).supportsInteractiveSelection)
    }
}

@Suite("Styler")
struct StylerTests {
    @Test("Applies SGR codes only when enabled")
    func apply() {
        let styler = Styler(isEnabled: true)
        #expect(styler.apply("hi", .bold, .cyan) == "\u{1B}[1m\u{1B}[36mhi\u{1B}[0m")
        #expect(styler.apply("", .bold).isEmpty)
        #expect(Styler.plain.red("hi") == "hi")
        #expect("hi".styled(.green, using: styler) == "\u{1B}[32mhi\u{1B}[0m")
        #expect(styled("hi", .bold) == Styler.standardOutput.apply("hi", .bold))
    }

    @Test("Hyperlinks use OSC 8 when styled and fall back to text with the URL")
    func hyperlink() {
        #expect(
            Styler(isEnabled: true).hyperlink("docs", url: "https://x.dev")
                == "\u{1B}]8;;https://x.dev\u{1B}\\docs\u{1B}]8;;\u{1B}\\"
        )
        #expect(Styler.plain.hyperlink("docs", url: "https://x.dev") == "docs (https://x.dev)")
        #expect(Styler.plain.hyperlink("https://x.dev", url: "https://x.dev") == "https://x.dev")
    }
}

@Suite("TextMetrics")
struct TextMetricsTests {
    @Test("Strips CSI and OSC sequences")
    func strip() {
        let styled = Styler(isEnabled: true)
        #expect(TextMetrics.strippingEscapes(styled.bold("a") + "\u{1B}[2K" + styled.hyperlink("b", url: "u")) == "ab")
    }

    @Test(
        "Measures display width",
        arguments: [("abc", 3), ("日本", 4), ("🚀x", 3), ("e\u{301}", 1), ("\u{1B}[1mbold\u{1B}[0m", 4), ("❤️", 2)]
            as [(String, Int)]
    )
    func width(text: String, expected: Int) {
        #expect(TextMetrics.displayWidth(text) == expected)
    }

    @Test("Truncates by columns and removes control characters")
    func truncate() {
        #expect(TextMetrics.truncate("abcdef", toWidth: 4) == "abc…")
        #expect(TextMetrics.truncate("abc", toWidth: 4) == "abc")
        #expect(TextMetrics.truncate("日本語テキスト", toWidth: 5) == "日本…")
        #expect(TextMetrics.truncate("a\tb\u{7}c", toWidth: 10) == "abc")
        #expect(TextMetrics.padRight("日", toWidth: 4) == "日  ")
    }
}

@Suite("Key")
struct KeyTests {
    @Test(
        "Decodes raw key bytes",
        arguments: [
            ([0x1B], Key.escape), ([0x1B, 0x5B, 0x41], .up), ([0x1B, 0x4F, 0x42], .down), ([0x1B, 0x5B, 0x43], .right),
            ([0x1B, 0x5B, 0x44], .left), ([0x1B, 0x5B, 0x33, 0x7E], .delete), ([0x1B, 0x5B, 0x35, 0x7E], .pageUp),
            ([0x1B, 0x5B, 0x31, 0x3B, 0x35, 0x41], .up), ([0x0D], .enter), ([0x0A], .enter), ([0x7F], .backspace),
            ([0x03], .interrupt), ([0x04], .endOfInput), ([], .endOfInput), ([0x09], .tab), ([0x61], .character("a")),
            ([0x20], .character(" ")), ([0xC3, 0xA9], .character("é")), ([0x01], .unknown), ([0x1B, 0x78], .unknown),
        ] as [([UInt8], Key)]
    )
    func decode(bytes: [UInt8], expected: Key) {
        #expect(Key(bytes: bytes) == expected)
    }
}

@Suite("Environment and escape regressions")
struct EnvironmentBoundaryTests {
    @Test("Locale variables follow precedence and ignore empty values")
    func localePrecedence() {
        #expect(!TerminalEnvironment(variables: ["LC_ALL": "C", "LANG": "en_US.UTF-8"]).supportsUnicode)
        #expect(!TerminalEnvironment(variables: ["LC_CTYPE": "C", "LANG": "en_US.UTF-8"]).supportsUnicode)
        #expect(TerminalEnvironment(variables: ["LC_ALL": "", "LC_CTYPE": "C.UTF-8", "LANG": "C"]).supportsUnicode)
    }

    @Test("Invisible formats and emoji variations have explicit widths")
    func widths() {
        #expect(TextMetrics.displayWidth("\u{200B}\u{200D}\u{FE0F}") == 0)
        #expect(TextMetrics.displayWidth("1\u{20E3}") == 2)
        #expect(TextMetrics.displayWidth("☀\u{FE0E}") == 1)
        #expect(TextMetrics.displayWidth("👩‍💻") == 2)
        #expect(TextMetrics.displayWidth("\u{17000}") == 2)
    }

    @Test("A custom ellipsis cannot inject terminal controls")
    func ellipsis() {
        #expect(TextMetrics.truncate("long text", toWidth: 5, ellipsis: "\u{1B}[2A!\n") == "long!")
    }
}
