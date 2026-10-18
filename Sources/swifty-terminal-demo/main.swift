import SwiftyTerminal

// Shows every component. `Scripts/test-pty.py` drives the `prompts` section through a real
// pseudo-terminal, so keep its prompt text and `result:` lines in sync with that script.

let section = CommandLine.arguments.dropFirst().first ?? "all"
let prompter = Prompter()
let console = Console()

@MainActor func runPrompts() {
    let platform = prompter.choose("Platform", options: ["iOS", "Android", "Both"], default: 0)
    console.print("result: platform=\(platform.map(String.init) ?? "cancelled")")
    let proceed = prompter.confirm("Continue?", default: true)
    console.print("result: continue=\(proceed.map(String.init) ?? "cancelled")")
    let devices = prompter.chooseMany(
        "Devices",
        options: ["iPhone 17", "iPhone 17 Pro", "iPad Air", "Pixel 9", "Pixel Tablet"],
        defaults: [0]
    )
    console.print("result: devices=\(devices.map { $0.map(String.init).joined(separator: ",") } ?? "cancelled")")
    let action = prompter.askKey("Tests failed", keys: ["r", "s", "a"], default: "r")
    console.print("result: action=\(action.map(String.init) ?? "cancelled")")
    let scheme = prompter.ask("Scheme", default: "MyApp")
    console.print("result: scheme=\(scheme ?? "cancelled")")
    let secret = prompter.askSecret("Password")
    console.print("result: secret-length=\(secret.map { String($0.count) } ?? "cancelled")")
}

@MainActor func runProgress() async {
    _ = await withSpinner("Inspecting project", showsResult: true) {
        try? await Task.sleep(for: .seconds(1))
    }
    let bar = ProgressBar("Uploading")
    for step in 0...20 {
        await bar.update(completed: Double(step), total: 20)
        try? await Task.sleep(for: .milliseconds(60))
    }
    await bar.succeed("Uploaded build")

    let steps = StepList(["Build", "Test", "Upload"])
    for title in ["Build", "Test"] {
        await steps.start(title)
        try? await Task.sleep(for: .milliseconds(700))
        await steps.succeed(title)
    }
    await steps.skip("Upload", detail: "dry run")
    await steps.finish()

    let tail = LiveTail("Compiling", visibleLineCount: 3)
    await tail.start()
    for file in ["AppDelegate", "ContentView", "Model", "Store", "Settings", "Networking"] {
        await tail.append("CompileSwift normal arm64 \(file).swift\n")
        try? await Task.sleep(for: .milliseconds(250))
    }
    await tail.succeed()
}

@MainActor func runOutput() {
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

switch section {
case "prompts":
    runPrompts()
case "progress":
    await runProgress()
case "output":
    runOutput()
default:
    runOutput()
    await runProgress()
    runPrompts()
}
