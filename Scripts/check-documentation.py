#!/usr/bin/env python3
"""Require summaries and parameter descriptions for source-declared public Swift APIs.

Compiler-generated declarations and declarations outside our three library targets are excluded.
Protocol witnesses are checked like other source declarations, rather than silently inheriting a
passing result from a requirement. DocC itself separately validates links and markup.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlparse

MODULES = ("SwiftyTerminal", "SwiftyTerminalLineEditor", "SwiftyTerminalTesting")


def check(graph_directory, root):
    failures = []
    checked = set()
    for module in MODULES:
        graphs = sorted(graph_directory.glob(module + "*.symbols.json"))
        graphs = [path for path in graphs if path.name == module + ".symbols.json" or path.name.startswith(module + "@")]
        if not graphs:
            failures.append(f"Missing symbol graphs for {module}")
            continue
        count = 0
        for graph in graphs:
            for symbol in json.loads(graph.read_text())["symbols"]:
                if symbol.get("accessLevel") not in ("public", "open"):
                    continue
                if symbol["kind"]["identifier"] == "swift.extension":
                    continue
                location = symbol.get("location", {})
                source = Path(unquote(urlparse(location.get("uri", "")).path)).resolve()
                if not source.is_relative_to(root / "Sources" / module):
                    continue
                identifier = symbol["identifier"]["precise"]
                if identifier in checked:
                    continue
                checked.add(identifier)
                count += 1
                line = location["position"]["line"] + 1
                label = f"{source.relative_to(root)}:{line}: {'/'.join(symbol['pathComponents'])}"
                documentation = [item["text"] for item in symbol.get("docComment", {}).get("lines", [])]
                if not documentation or not documentation[0].strip():
                    failures.append(label + ": missing summary")
                for parameter in symbol.get("functionSignature", {}).get("parameters", []):
                    name = parameter.get("internalName", parameter["name"])
                    pattern = r"^\s*-\s*(?:Parameter\s+)?" + re.escape(name) + r"\s*:\s*\S"
                    if not any(re.search(pattern, text) for text in documentation):
                        failures.append(label + f": missing description for parameter '{name}'")
        if count == 0:
            failures.append(f"No source-declared public API found for {module}")
    return failures, len(checked)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--symbol-graphs", type=Path)
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    directory = arguments.symbol_graphs
    if directory is None:
        result = subprocess.run(
            ["swift", "package", "dump-symbol-graph", "--skip-synthesized-members", "--skip-inherited-docs"],
            cwd=root, capture_output=True, text=True,
        )
        if result.returncode:
            sys.exit(result.stdout + result.stderr)
        match = re.search(r"Files written to (.+)", result.stdout + result.stderr)
        if not match:
            sys.exit("SwiftPM did not report a symbol-graph directory; documentation was not checked.")
        directory = Path(match[1].strip())
    failures, count = check(directory, root)
    if failures:
        sys.exit("\n".join(failures))
    print(f"Documentation completeness: {count} public declarations, all summaries and parameters documented.")


if __name__ == "__main__":
    main()
