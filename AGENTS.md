# SwiftyTerminal — Agent Guide

Shared terminal UX for Swift CLIs (amoo, ShipIt and future tools). Anything a CLI shows or asks on a
terminal belongs here rather than in a consumer, so the tools look and behave alike.

## Layout

| Path | Contents |
| --- | --- |
| `Sources/CSwiftyTerminal` | C: raw-mode key reads (with a one-byte pushback after a lone Escape), hidden-input line reads that restore echo on SIGINT, terminal size, stdout/stderr writes through stdio. |
| `Sources/SwiftyTerminal/Environment` | `TerminalEnvironment` (TTY flags + env vars → color, Unicode, cursor-control decisions), `ColorMode`. |
| `Sources/SwiftyTerminal/Style` | `ANSIStyle`, `Styler` (incl. OSC 8 hyperlinks), `TextMetrics` (escape stripping, display width, truncation). |
| `Sources/SwiftyTerminal/IO` | `Terminal` protocol, `StandardTerminal`, `Key` decoding, `LiveRegion` (redraw-in-place block). |
| `Sources/SwiftyTerminal/Prompts` | `Prompting`, `Prompter`, `SelectionMenu` (pure menu state machine), `SelectionParser`. |
| `Sources/SwiftyTerminal/Progress` | `Spinner`/`withSpinner`, `ProgressBar`, `StepList`, `LiveTail`, `Symbols`, `formatElapsed`. |
| `Sources/SwiftyTerminal/Output` | `Console`, `Table`, `Alert`. |
| `Sources/SwiftyTerminalLineEditor` (+ C target) | libedit `readline`, history, tab completion; plain `getline` fallback without libedit (Linux). |
| `Sources/SwiftyTerminalTesting` | `ScriptedTerminal`. |
| `Sources/swifty-terminal-demo` | Component tour; `Scripts/test-pty.py` drives its `prompts` section in a real PTY. |

## Build & test

```bash
make build       # swift build -Xswiftc -warnings-as-errors
make test        # Swift Testing unit tests
make test-pty    # real pseudo-terminal: raw keys, hidden input, termios restored
make lint        # swift-format lint --strict (run after the final edit)
make linux-ci    # Docker, swift:6.2.4-noble — run after touching C or #if os code
make check       # all of the above
```

## Rules

- **Decide from `TerminalEnvironment`, never from globals.** Every component takes a `Terminal`, so
  tests construct the environment they need. Do not call `isatty`/`getenv` outside
  `TerminalEnvironment.current()`.
- **Progress goes to stderr; prompts and `Console` default to stdout.** Consumers rely on stdout
  staying machine-readable in `--json` modes.
- **Every interactive path needs a non-interactive fallback** that works with redirected input and
  `TERM=dumb`, and every question returns `nil` on cancel/EOF instead of throwing or exiting.
- **Keep logic pure and render separately**: menu key handling and frame rendering live in value
  types (`SelectionMenu`, `Table`, `Alert`) with tests; I/O types stay thin.
- **Terminal state must always be restored**, including on Ctrl-C. Any new raw-mode or echo change
  goes in the C target next to the existing restore logic and gets a case in `Scripts/test-pty.py`.
- Keep the demo's prompt text and `result:` lines in sync with `Scripts/test-pty.py`.
- Tests use Swift Testing (`@Test`, `#expect`).
- Versioning: bare SemVer tags, no `v` prefix. Consumers pin `branch: "main"` until `0.1.0`.
