# ``SwiftyTerminal``

Rich terminal UX for Swift command-line tools, with plain-text fallbacks for CI and redirected I/O.

## Overview

SwiftyTerminal gives command-line tools one consistent way to style output, ask questions and show
progress. Every component takes a ``Terminal``, decides what to draw from a
``TerminalEnvironment``, and degrades to line-based input and plain output when stdin or stdout is
not a terminal, so the same command works interactively, in pipelines and in CI.

- Questions return `nil` when the user cancels (Esc, Ctrl-C in a menu, Ctrl-D) or input ends.
- Progress is written to stderr, so machine-readable stdout (`--json`) stays clean.
- Color follows `--color`-style ``ColorMode`` values plus `NO_COLOR`, `FORCE_COLOR` and `TERM=dumb`.

Use `SwiftyTerminalTesting`'s `ScriptedTerminal` to test prompts and progress without a TTY, and
`SwiftyTerminalLineEditor` for REPL input with history and tab completion.

## Topics

### Getting started

- <doc:UsingSwiftyTerminal>

### Terminal and environment

- ``Terminal``
- ``StandardTerminal``
- ``TerminalEnvironment``
- ``TerminalStream``
- ``TerminalSize``
- ``ColorMode``
- ``ColorDepth``
- ``Key``
- ``LiveRegion``

### Styling

- ``TerminalTheme``
- ``TerminalColor``
- ``Styler``
- ``ANSIStyle``
- ``styled(_:_:)``
- ``TextMetrics``
- ``Symbols``

### Prompts

- ``Prompting``
- ``Prompter``
- ``SelectionMenu``
- ``SelectionParser``

### Progress

- ``Spinner``
- ``withSpinner(_:terminal:colorMode:theme:showsResult:operation:)-1vwj3``
- ``withSpinner(_:terminal:colorMode:theme:showsResult:operation:)-8bo4c``
- ``ProgressBar``
- ``StepList``
- ``LiveTail``
- ``formatElapsed(_:)``

### Output

- ``Console``
- ``Table``
- ``Alert``
