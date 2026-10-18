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
make coverage    # tests with coverage; fails below 90% Swift line coverage (C is covered by test-pty)
make docc        # DocC with warnings as errors: document every public symbol and parameter
make lint        # swift-format lint --strict (run after the final edit)
make linux-ci    # Docker, swift:6.2.4-noble — run after touching C or #if os code
make check       # all of the above
make format      # swift-format in place (fixes lint failures)
```

Run `make lint` and `make test` after the final edit; run `make test-pty` and `make linux-ci` after
changing anything in the C targets or platform-conditional code.

Run a subset of tests:

```bash
swift test -Xswiftc -warnings-as-errors --filter SelectionMenuTests            # one suite
swift test -Xswiftc -warnings-as-errors --filter PrompterTests/<testFunction>   # one test
```

## Architecture notes

- **`Terminal` is the single seam.** Every component (`Prompter`, `Console`, `Spinner`, `StepList`, …)
  takes a `Terminal`; `StandardTerminal` calls into `CSwiftyTerminal`, and `ScriptedTerminal`
  (`SwiftyTerminalTesting`) replays keys/lines and records output. Unit tests exercise rendering and
  key handling only through `ScriptedTerminal`, so new behavior should be reachable through that
  protocol rather than through new global state.
- **Why C exists:** raw-mode key reads, no-echo reads that restore termios on SIGINT, and stdio-ordered
  writes cannot be done safely from Swift alone. `Scripts/test-pty.py` is the only thing that
  exercises them (against `swifty-terminal-demo`), which is why `make coverage` gates Swift lines only.
- **Coverage gate:** `make coverage` fails below 90% Swift line coverage (`MINIMUM_LINE_COVERAGE`);
  new Swift code needs tests in `Tests/SwiftyTerminalTests`.
- **Public API is documented under `--warnings-as-errors`:** `make docc` fails on any undocumented
  public symbol or parameter. `docs/` is generated and git-ignored.
- **Platforms:** macOS 15+ and Linux (Swift 6.2, language mode 6). `SwiftyTerminalLineEditor` links
  libedit only on macOS and falls back to `getline` elsewhere, so `#if os` changes need `make linux-ci`.

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
