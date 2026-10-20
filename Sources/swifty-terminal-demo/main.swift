import Dispatch
import Foundation
import SwiftyTerminal
import SwiftyTerminalLineEditor

let section = CommandLine.arguments.dropFirst().first ?? "menu"
var theme = TerminalTheme.default
var prompter = Prompter(theme: theme)
var console = Console(theme: theme)

func runSingleSelection() {
    let platform = prompter.choose("Platform", options: ["iOS", "Android", "Both"], default: 0)
    console.print("result: platform=\(platform.map(String.init) ?? "cancelled")")
}

func runConfirmation() {
    let proceed = prompter.confirm("Continue?", default: true)
    console.print("result: continue=\(proceed.map(String.init) ?? "cancelled")")
}

func runMultipleSelection() {
    let devices = prompter.chooseMany(
        "Devices",
        options: ["iPhone 17", "iPhone 17 Pro", "iPad Air", "Pixel 9", "Pixel Tablet"],
        defaults: [0]
    )
    console.print("result: devices=\(devices.map { $0.map(String.init).joined(separator: ",") } ?? "cancelled")")
}

func runKeyChoice() {
    let action = prompter.askKey("Tests failed", keys: ["r", "s", "a"], default: "r")
    console.print("result: action=\(action.map(String.init) ?? "cancelled")")
}

func runTextInput() {
    let scheme = prompter.ask("Scheme", default: "MyApp")
    console.print("result: scheme=\(scheme ?? "cancelled")")
}

func runSecretInput() {
    let secret = prompter.askSecret("Password")
    console.print("result: secret-length=\(secret.map { String($0.count) } ?? "cancelled")")
}

func runPrompts() {
    runSingleSelection()
    runConfirmation()
    runMultipleSelection()
    runKeyChoice()
    runTextInput()
    runSecretInput()
}

nonisolated func runSpinner() async {
    let terminal = StandardTerminal()
    guard terminal.environment.isInputTerminal else {
        terminal.writeLine("Spinner demo requires a terminal; skipping.", to: .standardError)
        return
    }
    await withSpinner("Inspecting project", terminal: terminal, theme: theme, showsResult: true) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                terminal.withRawInput {
                    terminal.writeLine("Press any key to dismiss the spinner.", to: .standardError)
                    _ = terminal.readKey()
                }
                continuation.resume()
            }
        }
    }
}

func runProgressBar() async {
    let bar = ProgressBar("Uploading", theme: theme)
    for step in 0...20 {
        await bar.update(completed: Double(step), total: 20)
        try? await Task.sleep(for: .milliseconds(60))
    }
    await bar.succeed("Uploaded build")
}

func runSteps() async {
    let steps = StepList(["Build", "Test", "Upload"], theme: theme)
    for title in ["Build", "Test"] {
        await steps.start(title)
        try? await Task.sleep(for: .milliseconds(700))
        await steps.succeed(title)
    }
    await steps.skip("Upload", detail: "dry run")
    await steps.finish()
}

func runLiveTail() async {
    let tail = LiveTail("Compiling", theme: theme, visibleLineCount: 3)
    await tail.start()
    for file in ["AppDelegate", "ContentView", "Model", "Store", "Settings", "Networking"] {
        await tail.append("CompileSwift normal arm64 \(file).swift\n")
        try? await Task.sleep(for: .milliseconds(250))
    }
    await tail.succeed()
}

func runProgress() async {
    await runSpinner()
    await runProgressBar()
    await runSteps()
    await runLiveTail()
}

func runOutput() {
    console.header("Doctor")
    console.check("Xcode 26.1", passed: true)
    console.check("Android SDK", passed: false)
    console.keyValue("Shipfile", "./Shipfile.yml")
    console.warning("Signing identity expires in 9 days")
    let docs = console.styler.hyperlink("SwiftyTerminal", url: "https://github.com/maniramezan/SwiftyTerminal")
    console.info("Docs: \(docs)")
    console.print()
    console.table(
        headers: ["Device", "Platform", "State"],
        rows: [["iPhone 17", "iOS 26.1", "Booted"], ["Pixel 9", "Android 16", "Offline"]]
    )
    console.print()
    console.alert(
        .error,
        title: "Upload failed",
        lines: ["App Store Connect rejected the API key."],
        nextSteps: ["Check ASC_KEY_ID", "Run shipit doctor"]
    )
}

func runLineEditor(historyPath: String? = nil) {
    let editor = LineEditor(historyPath: historyPath)
    editor.setCompletions(commands: ["tap_element", "status", "exit"])
    editor.loadHistory()
    console.print("Try typing tap_element or status. Type exit and press Enter to leave the line editor.")
    console.print("On macOS, use Tab for completion and Up/Down for history. Ctrl-D on an empty line also exits.")
    while true {
        guard let line = editor.readLine(prompt: "edit> ") else {
            console.print("edited: EOF")
            break
        }
        if line == "exit" { break }
        console.print("edited: \(line)")
    }
    editor.saveHistory()
}

private func parseRGB(_ text: String) -> TerminalColor? {
    let parts = text.split(separator: ",", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }
    let channels = parts.compactMap { UInt8($0.trimmingCharacters(in: .whitespaces)) }
    guard channels.count == 3 else { return nil }
    return .rgb(channels[0], channels[1], channels[2])
}

func runThemePicker() {
    let colors: [(name: String, color: TerminalColor)] = [
        ("Cyan", .cyan), ("Blue", .blue), ("Magenta", .magenta), ("Green", .green),
        ("Yellow", .yellow), ("Red", .red), ("White", .white),
    ]
    let current = colors.firstIndex { $0.color == theme.accent } ?? colors.count
    guard let choice = prompter.choose("Accent color", options: colors.map(\.name) + ["Custom RGB"], default: current)
    else {
        return
    }
    let name: String
    if choice == colors.count {
        guard
            let answer = prompter.ask(
                "RGB color (red,green,blue)",
                default: "120,80,255",
                validate: { parseRGB($0) == nil ? "Enter three numbers from 0 to 255, separated by commas." : nil }
            ), let color = parseRGB(answer)
        else { return }
        theme.accent = color
        name = "RGB (\(answer))"
    } else {
        theme.accent = colors[choice].color
        name = colors[choice].name
    }
    prompter = Prompter(theme: theme)
    console = Console(theme: theme)
    console.header("Accent: \(name)")
}

func runMenu() async {
    let demos: [(title: String, run: @MainActor () async -> Void)] = [
        ("Single selection", { runSingleSelection() }),
        ("Multiple selection", { runMultipleSelection() }),
        ("Confirmation", { runConfirmation() }),
        ("Key choice", { runKeyChoice() }),
        ("Text input", { runTextInput() }),
        ("Hidden password input", { runSecretInput() }),
        ("Spinner", { await runSpinner() }),
        ("Progress bar", { await runProgressBar() }),
        ("Step list", { await runSteps() }),
        ("Live output", { await runLiveTail() }),
        ("Tables, alerts and styled output", { runOutput() }),
        ("Line editor", { runLineEditor() }),
        ("Color theme", { runThemePicker() }),
    ]
    console.header("SwiftyTerminal demo")
    var selection = 0
    while let choice = prompter.choose("Try a component", options: demos.map(\.title) + ["Exit"], default: selection) {
        guard choice < demos.count else { return }
        selection = choice
        console.print()
        await demos[choice].run()
        console.print()
    }
}

switch section {
case "raw":
    let terminal = StandardTerminal()
    terminal.withRawInput {
        terminal.writeLine("ready: raw")
        _ = terminal.readKey()
    }
case "secret":
    _ = prompter.askSecret("ready: secret")
case "size":
    let size = StandardTerminal().size(for: .standardError)
    StandardTerminal().writeLine("size=\(size.columns),\(size.rows)", to: .standardError)
case "layout":
    let terminal = StandardTerminal()
    terminal.withRawInput {
        var region = LiveRegion(terminal: terminal, stream: .standardError)
        region.render(["frame-one"] + Array(repeating: String(repeating: "x", count: 200), count: 30))
        _ = terminal.readKey()
        region.render(["frame-two"] + Array(repeating: String(repeating: "y", count: 200), count: 30))
        _ = terminal.readKey()
        region.commit(["layout-done"])
    }
case "line-editor":
    runLineEditor(historyPath: CommandLine.arguments.dropFirst(2).first)
case "raw-throw":
    struct Failure: Error {}
    let terminal = StandardTerminal()
    do {
        try terminal.withRawInput {
            try terminal.withRawInput { throw Failure() }
        }
    } catch {
        console.print("raw restored after throw")
    }

case "prompts":
    runPrompts()
case "progress":
    await runProgress()
case "output":
    runOutput()
case "all":
    runOutput()
    await runProgress()
    runPrompts()
default:
    await runMenu()
}
