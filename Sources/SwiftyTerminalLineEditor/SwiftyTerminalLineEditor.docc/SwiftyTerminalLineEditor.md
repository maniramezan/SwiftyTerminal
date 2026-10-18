# ``SwiftyTerminalLineEditor``

Read command lines with editing, history, and completion on macOS, with plain line input on Linux.

## Overview

Create a ``LineEditor``, configure completion candidates, load history once, then save history when
the REPL ends. Calls block the current thread. Every editor shares one lock because libedit's
history and completion tables are process-wide; a pending read excludes configuration changes.

```swift
import SwiftyTerminalLineEditor

let editor = LineEditor(historyPath: "/tmp/my-cli-history")
editor.setCompletions(commands: ["help", "status", "quit"])
editor.loadHistory()
while let line = editor.readLine(prompt: "tool> ") {
    if line == "quit" { break }
    print(line)
}
editor.saveHistory()
```

On Linux, input uses `getline` even when libedit development headers are installed. History and
completion configuration are no-ops there. History operations currently ignore missing files and
other persistence errors, so callers should not rely on successful persistence for correctness.

For prompts and output, see [SwiftyTerminal](https://maniramezan.github.io/SwiftyTerminal/documentation/swiftyterminal).
For scripted tests, see [SwiftyTerminalTesting](https://maniramezan.github.io/SwiftyTerminal/documentation/swiftyterminaltesting).

## Topics

### Editing input

- ``LineEditor``
