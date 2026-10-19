# SwiftyTerminal

[![CI](https://github.com/maniramezan/SwiftyTerminal/actions/workflows/ci.yml/badge.svg)](https://github.com/maniramezan/SwiftyTerminal/actions/workflows/ci.yml)

Rich terminal UX for Swift command-line tools: colors, prompts, spinners, progress, step lists,
live command output, tables and alert boxes, with plain-text fallbacks for CI and redirected I/O.
Shared by amoo and ShipIt.

```swift
.package(url: "https://github.com/maniramezan/SwiftyTerminal.git", branch: "main")
```

| Product | Contents |
| --- | --- |
| `SwiftyTerminal` | Everything below. No system-library dependencies. |
| `SwiftyTerminalLineEditor` | libedit line editing with history and tab completion, for REPLs. |
| `SwiftyTerminalTesting` | `ScriptedTerminal`, a fake terminal for testing prompts and progress. |

Requires Swift 6.2 and macOS 15 or Linux.

## Try the demo

Run the demo from a checkout with Swift 6.2 or later:

```bash
swift run swifty-terminal-demo
```

Choose a component from the menu to try it, then return to the menu to explore another.
Each prompt and progress component has its own entry. Select Exit or cancel the menu to quit.
Choose Color theme to change the accent for the rest of the demo.
Redirected input and `TERM=dumb` use a numbered menu.

You can also run a section directly:

```bash
swift run swifty-terminal-demo output
swift run swifty-terminal-demo progress
swift run swifty-terminal-demo prompts
swift run swifty-terminal-demo line-editor
```

Use `swift run swifty-terminal-demo all` for the sequential tour.

## Prompts

```swift
let prompter = Prompter()
let scheme = prompter.ask("Xcode scheme", default: "MyApp")
let password = prompter.askSecret("Keystore password")
let upload = prompter.confirm("Upload to TestFlight?", default: false)
let action = prompter.askKey("Tests failed", keys: ["r", "s", "a"], default: "r")
let track = prompter.choose("Play track", options: ["internal", "beta", "production"], default: 0)
let devices = prompter.chooseMany("Devices", options: deviceNames, defaults: [0])
```

`ask` reads free text, `askSecret` hides input, and `confirm` accepts a single `y` or `n` key.

On a terminal, `choose` and `chooseMany` are arrow-key menus (radio buttons and checkboxes) with
Up/Down to move, Left/Right (or PageUp/PageDown) to jump a page, and `/` to filter long lists.
They collapse to a one-line answer when done. When input is redirected
or `TERM=dumb`, they fall back to numbered lists (`1,3`, `2-4`, `all`), so `printf '2\ny\n' | tool`
works. Every question returns `nil` when the user cancels (Esc, Ctrl-C in a menu, Ctrl-D).

Depend on the `Prompting` protocol in command logic and pass a fake in tests, or test the prompts
themselves with `ScriptedTerminal`:

```swift
let terminal = ScriptedTerminal(.key(.down), .key(.enter))
#expect(Prompter(terminal: terminal).choose("Platform", options: ["iOS", "Android"], default: 0) == 1)
```

## Progress

All progress output goes to stderr, so `--json` stdout stays clean, and it only animates when stderr
is a terminal.

```swift
let inspection = try await withSpinner("Inspecting project") { try await inspector.inspect() }

let bar = ProgressBar("Uploading")
await bar.update(completed: sent, total: size)
await bar.succeed("Uploaded build 42")

let steps = StepList(["Build", "Test", "Upload"])
await steps.start("Build"); await steps.succeed("Build")
await steps.finish()

let tail = LiveTail("xcodebuild", visibleLineCount: 5)
await tail.start()
for try await line in output { await tail.append(line + "\n") }
await tail.succeed()
```

The live tail displays the last five lines and replays retained output on failure.
Live tails bound retained output by line and byte count and coalesce redraws. Secret prompts preserve
leading and trailing spaces in passwords.

Spinners wait 150 ms before drawing, so fast operations never flicker. Without a terminal, step lists
and live tails write plain lines that read well in CI logs.

## Output

```swift
let console = Console(colorMode: options.color)
console.header("Doctor")
console.check("Xcode 26.1", passed: true)
console.keyValue("Shipfile", path)
console.warning("Signing identity expires in 9 days")
console.table(headers: ["Device", "State"], rows: rows)
console.alert(.error, title: "Upload failed", lines: [reason], nextSteps: ["Run shipit doctor"])
```

`Console` accepts `.auto`, `.always`, or `.never` for its color mode.
Color follows `NO_COLOR`, `FORCE_COLOR`, `TERM=dumb` and whether the stream is a terminal, decided per
stream. Glyphs and box drawing fall back to ASCII when the effective locale is not UTF-8
(`LC_ALL`, then `LC_CTYPE`, then `LANG`). `TextMetrics` measures
and truncates by display width, so CJK text and emoji line up.

## Color themes

Pass one `TerminalTheme` to prompts, output and progress components:

```swift
let theme = TerminalTheme(accent: .magenta)
let console = Console(theme: theme)
let prompter = Prompter(theme: theme)
let bar = ProgressBar("Uploading", theme: theme)
```

Themes accept `ANSIStyle` foreground colors, including bright variants. Customize `success`,
`error`, `warning` and `info` independently; omitted roles keep their defaults. `Spinner`,
`withSpinner`, `StepList`, `LiveTail` and `Styler` also accept `theme:`. Use `Styler.accent`,
`success`, `error`, `warning` and `info` to apply the same palette to custom text.

A CLI can build its theme from a user flag, saved preference or color-selection prompt, then pass
it to its components. Themes are values scoped to each component. They do not enable color:
`ColorMode` and terminal capabilities still determine whether styling is emitted. Explicit color
methods such as `Styler.red` keep their requested color.

## Development

```bash
make check
make demo
make docc
```

`make check` runs lint, tests with the coverage gate, real-PTY tests, DocC, and Linux validation
through Docker. `make demo` opens the component menu. `make docc` documents all three products and
checks API summaries and parameters.

CI runs lint, unit tests with a 90% Swift line-coverage gate on macOS, unit and real-PTY tests on
Linux (Swift 6.2.4 and 6.4.1), and builds the DocC site, which is published to
[GitHub Pages](https://maniramezan.github.io/SwiftyTerminal/) from `main`. Dependabot updates Swift
packages and GitHub Actions weekly.
