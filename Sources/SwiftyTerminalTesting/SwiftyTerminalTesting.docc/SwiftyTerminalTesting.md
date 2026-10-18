# ``SwiftyTerminalTesting``

Test terminal conversations and rendering with scripted input and captured output.

## Overview

``ScriptedTerminal`` implements `SwiftyTerminal.Terminal`. Its default environment enables menus
without adding color escapes. Construct a redirected environment to exercise numbered-list input.
Input kinds must match: a request for a line when a key was scripted returns nil and records an
unexpected read without consuming the action.

```swift
import SwiftyTerminal
import SwiftyTerminalTesting

let terminal = ScriptedTerminal(.key(.down), .key(.enter))
let answer = Prompter(terminal: terminal).choose("Platform", options: ["iOS", "Android"], default: 0)
assert(answer == 1)
assert(terminal.remainingInput.isEmpty)
assert(terminal.unexpectedReads.isEmpty)
```

Inspect ``ScriptedTerminal/output(_:)`` to assert exact escape sequences, or
``ScriptedTerminal/plainOutput(_:)`` to inspect text. Plain output strips escapes; it does not
emulate cursor movement. Real terminal restoration, screen geometry, and libedit behavior need
PTY integration tests.

Return to [SwiftyTerminal](https://maniramezan.github.io/SwiftyTerminal/documentation/swiftyterminal)
or read about [line editing](https://maniramezan.github.io/SwiftyTerminal/documentation/swiftyterminallineeditor).

## Topics

### Scripted conversations

- ``ScriptedTerminal``
