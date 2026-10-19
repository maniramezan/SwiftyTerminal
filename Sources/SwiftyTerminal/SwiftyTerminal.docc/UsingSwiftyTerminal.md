# Using SwiftyTerminal

Build testable prompts and progress indicators while keeping machine-readable output separate.

## Create a conversation

Import `SwiftyTerminal` in your executable target. Add `SwiftyTerminalTesting` to a test target when
you want to exercise rendering or input without a terminal.

```swift
import SwiftyTerminal
import SwiftyTerminalTesting

let terminal = ScriptedTerminal(
    input: [.line("2")],
    environment: ScriptedTerminal.redirected
)
let answer = Prompter(terminal: terminal).choose("Platform", options: ["iOS", "Android"], default: 0)
assert(answer == 1)
```

``Prompter/askSecret(_:)`` preserves spaces in credentials. Numbered questions reject invalid
answers and retry. Empty answers use valid defaults; multi-selection results are sorted and unique.
Cancellation and EOF return nil. Ctrl-C typed in a raw menu is a cancellation key; termination
signals delivered to a process restore its input mode before the previous signal disposition runs.
Free-text input uses canonical terminal input and its normal signal behavior.

## Keep progress on stderr

``Console`` and prompts default to stdout. Progress indicators default to stderr, allowing a
consumer to print JSON on stdout while stderr remains attached to the terminal. Size lookup follows
the chosen stream and falls back to another attached standard stream when necessary.

```swift
import SwiftyTerminal
import SwiftyTerminalTesting

func showProgress() async {
    let terminal = ScriptedTerminal(input: [], environment: ScriptedTerminal.redirected)
    let bar = ProgressBar("Uploading", terminal: terminal)
    await bar.update(completed: 3, total: 10)
    await bar.succeed("Uploaded")
    assert(terminal.output().isEmpty)
    assert(terminal.output(.standardError).contains("Uploaded"))
}
```

Without a terminal, a ProgressBar writes only its final result and a Spinner writes nothing.
StepList writes transitions, while LiveTail forwards command chunks immediately. With a terminal,
LiveTail limits retained lines and bytes, handles carriage-return progress updates, and coalesces
redraws. A very long line is truncated in retained output. Set `maximumRetainedBytes` when you need
a different memory limit.

## End asynchronous indicators

Prefer ``withSpinner(_:terminal:colorMode:theme:showsResult:isolation:operation:)`` for one operation;
it cleans up on both success and errors, including cooperative cancellation. With manually managed
indicators, call `stop`, `succeed`, `fail`, or `finish` before releasing the last reference. Cancellation
of a calling task alone does not stop an unstructured animation task. Avoid overlapping independent
live regions on the same stream; coordinate progress and prompt ownership in the consumer.

```swift
import SwiftyTerminal
import SwiftyTerminalTesting

func inspect() async throws -> Int {
    let terminal = ScriptedTerminal(input: [], environment: ScriptedTerminal.redirected)
    return try await withSpinner("Inspecting", terminal: terminal) {
        try Task.checkCancellation()
        return 42
    }
}
```

## Choose a color theme

Create a ``TerminalTheme`` from user preferences and pass the same value to your components.
The default palette uses cyan accents, green success, red errors, yellow warnings and blue information.
Each role accepts a ``TerminalColor``: a named color, a bright variant, or an RGB value with
`UInt8` channels from 0 through 255.

```swift
import SwiftyTerminal

let theme = TerminalTheme(accent: .rgb(120, 80, 255), success: .brightGreen)
let console = Console(theme: theme)
let prompter = Prompter(theme: theme)
let bar = ProgressBar("Uploading", theme: theme)
console.header("Deploy")
```

``Spinner``, ``withSpinner(_:terminal:colorMode:theme:showsResult:isolation:operation:)``,
``StepList`` and ``LiveTail`` also accept `theme:`. For custom text, create a ``Styler`` with the
same theme and use its `accent`, `success`, `error`, `warning` and `info` methods. Explicit methods
such as `red` still use that named color. Pure renderers such as ``SelectionMenu`` and ``Alert``
use the theme carried by their styler.

Themes are values, with no process-wide setting. Changing a theme affects components created with
the updated value; an existing ``Prompter`` can update its `styler.theme`. Color policies still apply:
a custom theme does not override `NO_COLOR`, redirected streams or ``ColorMode/never``.

``TerminalEnvironment/colorDepth`` uses `COLORTERM=truecolor` or `24bit`, or a `TERM` ending in
`-direct`, to select direct RGB output. A `TERM` containing `256color` selects the xterm palette;
otherwise RGB colors use the nearest standard sixteen-color entry. `TERM=dumb` always uses
sixteen-color depth. Detection is case-insensitive and independent of color enablement.

Fallbacks minimize squared RGB distance. The 256-color fallback uses the fixed color cube and
grayscale entries, avoiding the configurable first sixteen slots. The sixteen-color fallback
assumes the standard palette, so its appearance depends on the terminal's palette settings.
Named colors always retain their original palette entries.

For custom text, use `styler.apply("Brand", color: .rgb(120, 80, 255), styles: [.bold])`.
A styler initialized with a stream detects depth from the supplied environment. A styler initialized
with `isEnabled` defaults to ``ColorDepth/trueColor`` and accepts an explicit `colorDepth`.
For terminals that support RGB without advertising it, set `COLORTERM=truecolor` in their environment.
See the [xterm color controls](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html) for the escape sequences.

Theme roles use ``TerminalColor`` rather than ``ANSIStyle``. Inferred literals such as `.cyan`
continue to work; explicitly typed theme-color variables should use ``TerminalColor``.
Existing ``ANSIStyle`` text styling APIs remain available.

## Choose terminal capabilities

``TerminalEnvironment`` decides color per stream. An explicit ``ColorMode`` overrides the automatic
policy. Unicode follows the first non-empty locale in `LC_ALL`, `LC_CTYPE`, `LANG` order.
`TERM=dumb` uses ASCII glyphs, plain progress, and numbered choices. Short questions can still read
a single key when stdin is a terminal; redirected stdin always uses complete lines.

Live regions reserve a row for their final newline and remove cursor commands embedded in content.
Safe SGR styling and OSC 8 hyperlinks are retained. Tables and alerts use display width rather than
Swift character counts. Emoji presentation can differ between terminal applications.

See the [testing product](https://maniramezan.github.io/SwiftyTerminal/documentation/swiftyterminaltesting)
and [line-editor product](https://maniramezan.github.io/SwiftyTerminal/documentation/swiftyterminallineeditor)
for their complete API references and platform behavior.
