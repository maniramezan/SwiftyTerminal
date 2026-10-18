#!/usr/bin/env python3
"""Regression tests for the repository's completeness gates."""
import importlib.util
import json
from pathlib import Path
import tempfile
import sys
import unittest

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location("documentation_gate", Path(__file__).with_name("check-documentation.py"))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class DocumentationGateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.graphs = self.root / "graphs"
        self.graphs.mkdir()

    def graph(self, module, documentation):
        source = self.root / "Sources" / module / "API.swift"
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_text("public func example(value: Int) {}\n")
        symbol = {
            "accessLevel": "public", "kind": {"identifier": "swift.func"},
            "identifier": {"precise": module + ".example"}, "pathComponents": ["example(value:)"],
            "location": {"uri": source.as_uri(), "position": {"line": 0}},
            "functionSignature": {"parameters": [{"name": "value"}]},
            "docComment": {"lines": [{"text": line} for line in documentation]},
        }
        (self.graphs / (module + ".symbols.json")).write_text(json.dumps({"symbols": [symbol]}))

    def test_missing_modules_do_not_pass(self):
        failures, count = gate.check(self.graphs, self.root)
        self.assertEqual(count, 0)
        self.assertTrue(failures)

    def test_missing_summaries_and_parameters_fail(self):
        for module in gate.MODULES:
            self.graph(module, [])
        failures, count = gate.check(self.graphs, self.root)
        self.assertEqual(count, 3)
        self.assertEqual(len(failures), 6)

    def test_documented_source_api_passes(self):
        for module in gate.MODULES:
            self.graph(module, ["An example.", "", "- Parameters:", "  - value: The input value."])
        self.assertEqual(gate.check(self.graphs, self.root), ([], 3))

    def test_empty_parameter_descriptions_fail(self):
        for module in gate.MODULES:
            self.graph(module, ["An example.", "", "- Parameter value: "])
        failures, count = gate.check(self.graphs, self.root)
        self.assertEqual(count, 3)
        self.assertEqual(len(failures), 3)


if __name__ == "__main__":
    unittest.main()
