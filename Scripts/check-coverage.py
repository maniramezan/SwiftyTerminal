#!/usr/bin/env python3
"""Enforce line coverage from SwiftPM's code-coverage JSON.

Usage: check-coverage.py <codecov.json> <repo-root> <minimum-percent>

The gate applies to the Swift sources. The C targets (raw terminal I/O, libedit) only run against a
real TTY, which `Scripts/test-pty.py` exercises in a separate process, so their coverage is
reported but not gated. The demo and release-check executables are excluded.
"""
import json
import os
import sys


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    report, root, minimum = sys.argv[1], os.path.join(sys.argv[2], "Sources") + "/", float(sys.argv[3])
    files = json.load(open(report))["data"][0]["files"]
    totals = {"swift": [0, 0], "c": [0, 0]}
    rows = []
    for entry in files:
        name = entry["filename"]
        if not name.startswith(root) or "/swifty-terminal-demo/" in name or "/swifty-terminal-release-check/" in name:
            continue
        lines = entry["summary"]["lines"]
        kind = "c" if name.endswith(".c") else "swift"
        totals[kind][0] += lines["covered"]
        totals[kind][1] += lines["count"]
        rows.append((name[len(root):], lines["covered"], lines["count"]))

    def percent(covered, count):
        return 100.0 * covered / count if count else 100.0

    swift = percent(*totals["swift"])
    c = percent(*totals["c"])
    lines = ["| File | Lines | Coverage |", "| --- | ---: | ---: |"]
    lines += [f"| `{name}` | {covered}/{count} | {percent(covered, count):.1f}% |" for name, covered, count in sorted(rows)]
    summary = (
        f"**Swift line coverage: {swift:.2f}%** (minimum {minimum:.0f}%)  \n"
        f"C line coverage (TTY paths, exercised by the PTY tests): {c:.2f}%\n\n" + "\n".join(lines) + "\n"
    )
    print(summary)
    step_summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary:
        with open(step_summary, "a") as handle:
            handle.write("## Coverage\n\n" + summary)
    if swift < minimum:
        sys.exit(f"Swift line coverage {swift:.2f}% is below the required {minimum:.0f}%.")


if __name__ == "__main__":
    main()
