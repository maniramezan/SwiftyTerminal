import SwiftyTerminal
import Testing

@Suite("SelectionMenu")
struct SelectionMenuTests {
    private let devices = ["iPhone 17", "iPhone 17 Pro", "iPad Air", "Pixel 9", "Pixel Tablet"]

    @Test("j/k and arrows move focus with wrap-around; digits jump")
    func navigation() {
        var menu = SelectionMenu(title: "Device", options: devices, allowsMultiple: false)
        _ = menu.handle(.character("k"))
        #expect(menu.focused == 4)
        _ = menu.handle(.down)
        #expect(menu.focused == 0)
        _ = menu.handle(.character("3"))
        #expect(menu.focused == 2)
        _ = menu.handle(.end)
        #expect(menu.focused == 4)
        _ = menu.handle(.home)
        #expect(menu.focused == 0)
        #expect(menu.handle(.enter) == .submitted([0]))
    }

    @Test("Slash filters case-insensitively; typing letters does not navigate")
    func filtering() {
        var menu = SelectionMenu(title: "Device", options: devices, allowsMultiple: false)
        _ = menu.handle(.character("/"))
        for character in "pIX" {
            _ = menu.handle(.character(character))
        }
        #expect(menu.filter == "pIX")
        #expect(menu.visibleIndexes == [3, 4])
        #expect(menu.focused == 3)
        _ = menu.handle(.down)
        #expect(menu.handle(.enter) == .submitted([4]))
    }

    @Test("Escape clears the filter first, then cancels")
    func escapeClearsFilter() {
        var menu = SelectionMenu(title: "Device", options: devices, allowsMultiple: false)
        _ = menu.handle(.character("/"))
        _ = menu.handle(.character("z"))
        #expect(menu.visibleIndexes.isEmpty)
        #expect(menu.handle(.enter) == nil)
        #expect(menu.handle(.escape) == nil)
        #expect(menu.filter == nil)
        #expect(menu.handle(.escape) == .cancelled)
    }

    @Test("Backspace on an empty filter leaves filter mode")
    func backspace() {
        var menu = SelectionMenu(title: "Device", options: devices, allowsMultiple: false)
        _ = menu.handle(.character("/"))
        _ = menu.handle(.character("a"))
        _ = menu.handle(.backspace)
        #expect(menu.filter == "")
        _ = menu.handle(.backspace)
        #expect(menu.filter == nil)
    }

    @Test("While filtering, letters extend the filter; otherwise a toggles all")
    func toggleAllVersusFilter() {
        var menu = SelectionMenu(title: "Devices", options: devices, allowsMultiple: true)
        _ = menu.handle(.character("/"))
        _ = menu.handle(.character("i"))
        _ = menu.handle(.character("P"))
        _ = menu.handle(.character("a"))
        #expect(menu.filter == "iPa")
        #expect(menu.visibleIndexes == [2])
        _ = menu.handle(.character(" "))
        _ = menu.handle(.escape)
        #expect(menu.handle(.enter) == .submitted([2]))
        _ = menu.handle(.character("a"))
        #expect(menu.selected == Set(devices.indices))
        _ = menu.handle(.character("a"))
        #expect(menu.selected.isEmpty)
    }

    @Test("Ctrl-C and Ctrl-D cancel")
    func interrupt() {
        var menu = SelectionMenu(title: "Device", options: devices, allowsMultiple: true)
        #expect(menu.handle(.interrupt) == .cancelled)
        #expect(menu.handle(.endOfInput) == .cancelled)
    }

    @Test("The viewport keeps the focused row visible and reports position")
    func viewport() {
        var menu = SelectionMenu(title: "Device", options: devices, allowsMultiple: false, viewportHeight: 2)
        _ = menu.handle(.end)
        let lines = menu.render(styler: .plain)
        #expect(
            lines == [
                "Device", "  ( ) Pixel 9", "> (*) Pixel Tablet",
                "Up/Down move | Left/Right page | / filter | Enter select | Esc cancel (5/5)",
            ]
        )
    }

    @Test("Left/Right and PageUp/PageDown jump a viewport and stop at the ends", arguments: [false, true])
    func pageNavigation(allowsMultiple: Bool) {
        var menu = SelectionMenu(
            title: "Device",
            options: devices,
            allowsMultiple: allowsMultiple,
            defaults: [1],
            viewportHeight: 2
        )
        _ = menu.handle(.right)
        #expect(menu.focused == 3)
        _ = menu.handle(.right)
        #expect(menu.focused == 4)
        _ = menu.handle(.right)
        #expect(menu.focused == 4)
        _ = menu.handle(.left)
        #expect(menu.focused == 2)
        _ = menu.handle(.pageUp)
        #expect(menu.focused == 0)
        _ = menu.handle(.left)
        #expect(menu.focused == 0)
        _ = menu.handle(.pageDown)
        #expect(menu.focused == 2)
        #expect(menu.selected == (allowsMultiple ? [1] : []))
        #expect(menu.render(styler: .plain).last?.contains("Left/Right page") == true)
    }

    @Test("Paging follows filtered choices and preserves selections")
    func filteredPageNavigation() {
        var menu = SelectionMenu(
            title: "Device",
            options: devices,
            allowsMultiple: true,
            defaults: [0],
            viewportHeight: 1
        )
        _ = menu.handle(.character("/"))
        for character in "iP" {
            _ = menu.handle(.character(character))
        }
        #expect(menu.visibleIndexes == [0, 1, 2])
        _ = menu.handle(.right)
        #expect(menu.focused == 1)
        _ = menu.handle(.right)
        #expect(menu.focused == 2)
        _ = menu.handle(.character(" "))
        _ = menu.handle(.left)
        #expect(menu.focused == 1)
        #expect(menu.handle(.enter) == .submitted([0, 2]))
        _ = menu.handle(.character("z"))
        _ = menu.handle(.right)
        _ = menu.handle(.left)
        #expect(menu.visibleIndexes.isEmpty)
        #expect(menu.handle(.enter) == nil)
    }

    @Test("Menus that fit the viewport omit the paging hint")
    func noPagingHint() {
        let menu = SelectionMenu(title: "Device", options: devices, allowsMultiple: true)
        #expect(menu.render(styler: .plain).last?.contains("Left/Right page") == false)
    }

    @Test("Rendering respects the terminal height")
    func maximumRows() {
        let menu = SelectionMenu(title: "Device", options: devices, allowsMultiple: true, defaults: [1])
        let lines = menu.render(styler: .plain, maximumRows: 4)
        #expect(lines.count == 4)
        #expect(lines[1] == "  [ ] iPhone 17")
        #expect(lines[2] == "> [x] iPhone 17 Pro")
    }
}

@Suite("SelectionParser")
struct SelectionParserTests {
    @Test(
        "Parses lists, ranges and all",
        arguments: [
            ("1,3", [0, 2]), ("2-4", [1, 2, 3]), ("all", [0, 1, 2, 3]), ("3 1 3", [0, 2]), (" 4 ", [3]),
        ] as [(String, [Int])]
    )
    func parses(text: String, expected: [Int]) {
        #expect(SelectionParser.parse(text, count: 4) == expected)
    }

    @Test("Rejects out-of-range, reversed and malformed input", arguments: ["0", "5", "3-2", "1-2-3", "x", ""])
    func rejects(text: String) {
        #expect(SelectionParser.parse(text, count: 4) == nil)
    }
}
