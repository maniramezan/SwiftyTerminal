import Foundation
import SwiftyTerminal
import SwiftyTerminalTesting

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

struct ExpectedFailure: Error {}

nonisolated func expect(_ condition: Bool, _ message: String) throws {
    guard condition else { throw CheckFailure(description: message) }
}

nonisolated func animatedTerminal() -> ScriptedTerminal {
    ScriptedTerminal(input: [], environment: ScriptedTerminal.interactive)
}

nonisolated func nonThrowingOperation() async throws {
    let terminal = animatedTerminal()
    let value = await withSpinner("Non-throwing", terminal: terminal, showsResult: true) {
        try? await Task.sleep(for: .milliseconds(250))
        return 42
    }
    try expect(value == 42, "non-throwing overload returned \(value)")
    let output = terminal.plainOutput(.standardError)
    try expect(output.contains("Non-throwing"), "spinner never animated: \(output)")
    try expect(output.contains("✔ Non-throwing"), "missing success line: \(output)")
}

nonisolated func throwingOperation() async throws {
    let terminal = animatedTerminal()
    let value = try await withSpinner("Throwing", terminal: terminal) {
        try await Task.sleep(for: .milliseconds(250))
        async let first: Int = {
            try await Task.sleep(for: .milliseconds(5))
            return 1
        }()
        async let second: Int = {
            try await Task.sleep(for: .milliseconds(10))
            return 2
        }()
        let offset = try await first + second - 3
        return try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 1...8 {
                group.addTask {
                    try await Task.sleep(for: .milliseconds(index))
                    return index
                }
            }
            return try await group.reduce(offset, +)
        }
    }
    try expect(value == 36, "throwing overload returned \(value)")
}

nonisolated func operationThatThrows() async throws {
    let terminal = animatedTerminal()
    do {
        _ = try await withSpinner("Failing", terminal: terminal, showsResult: true) { () async throws -> Int in
            try await Task.sleep(for: .milliseconds(250))
            throw ExpectedFailure()
        }
        throw CheckFailure(description: "the operation's error was swallowed")
    } catch is ExpectedFailure {
        let output = terminal.plainOutput(.standardError)
        try expect(output.contains("✖ Failing"), "missing failure line: \(output)")
    }
}

nonisolated func nestedSpinners() async throws {
    let terminal = animatedTerminal()
    let value = try await withSpinner("Outer", terminal: terminal) {
        let inner = await withSpinner("Inner", terminal: terminal) { 1 }
        return try await withSpinner("Sibling", terminal: terminal) {
            try await Task.sleep(for: .milliseconds(1))
            return inner + 1
        }
    }
    try expect(value == 2, "nested spinners returned \(value)")
}

nonisolated func standardTerminalLoop() async throws {
    var total = 0
    for index in 0..<500 {
        total += try await withSpinner("Default terminal", colorMode: .never) {
            try await Task.sleep(for: .zero)
            return index
        }
        total -= await withSpinner("Default terminal") { index }
    }
    try expect(total == 0, "default-terminal loop drifted to \(total)")
}

nonisolated func runChecks() async -> Int32 {
    let checks: [(name: String, run: () async throws -> Void)] = [
        ("non-throwing operation", nonThrowingOperation),
        ("throwing operation", throwingOperation),
        ("operation that throws", operationThatThrows),
        ("nested spinners", nestedSpinners),
        ("standard terminal loop", standardTerminalLoop),
    ]
    var failures: Int32 = 0
    for check in checks {
        do {
            try await check.run()
            print("ok: \(check.name)")
        } catch {
            print("FAILED: \(check.name): \(error)")
            failures += 1
        }
    }
    return failures
}

let failures = await runChecks()
print(failures == 0 ? "release check passed" : "release check failed: \(failures) check(s)")
exit(failures == 0 ? 0 : 1)
