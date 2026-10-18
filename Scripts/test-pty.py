#!/usr/bin/env python3
"""Drive `swifty-terminal-demo prompts` through a real pseudo-terminal.

Unit tests cover the prompt logic with ScriptedTerminal; this covers what they cannot: raw-mode
key reading, hidden input, and that the terminal settings are restored afterwards.
Run after `swift build`.
"""
import os
import codecs
import fcntl
import re
import signal
import struct
import sys
import tempfile
import unicodedata
import pty
import select
import subprocess
import termios
import time
import unittest

DEMO = os.environ.get("SWIFTY_TERMINAL_DEMO", ".build/debug/swifty-terminal-demo")


class Screen:
    """Small screen model for the cursor/erase sequences emitted by LiveRegion."""
    def __init__(self, columns, rows):
        self.columns, self.rows = columns, rows
        self.cells = [[" "] * columns for _ in range(rows)]
        self.row = self.column = 0
        self.pending = ""
        self.decoder = codecs.getincrementaldecoder("utf-8")("replace")

    def resize(self, columns, rows):
        self.cells = [row[:columns] + [" "] * max(0, columns - len(row)) for row in self.cells[-rows:]]
        self.cells += [[" "] * columns for _ in range(rows - len(self.cells))]
        self.columns, self.rows = columns, rows
        self.row, self.column = min(self.row, rows - 1), min(self.column, columns - 1)

    def feed(self, chunk):
        self.pending += self.decoder.decode(chunk)
        while self.pending:
            character = self.pending[0]
            if character == "\x1b":
                match = re.match(r"\x1b\[([0-9;]*)([A-Za-z])", self.pending)
                if not match:
                    return
                count = int(match[1] or "1")
                if match[2] == "A":
                    self.row = max(0, self.row - count)
                elif match[2] == "J":
                    for row in range(self.row, self.rows):
                        start = self.column if row == self.row else 0
                        self.cells[row][start:] = [" "] * (self.columns - start)
                elif match[2] == "K":
                    self.cells[self.row] = [" "] * self.columns
                self.pending = self.pending[match.end():]
                continue
            self.pending = self.pending[1:]
            if character == "\r":
                self.column = 0
            elif character == "\n":
                self.row += 1
                if self.row >= self.rows:
                    self.cells.pop(0)
                    self.cells.append([" "] * self.columns)
                    self.row = self.rows - 1
            elif not unicodedata.combining(character) and ord(character) >= 32:
                if self.column >= self.columns:
                    self.column = 0
                    self.row += 1
                if self.row >= self.rows:
                    self.cells.pop(0)
                    self.cells.append([" "] * self.columns)
                    self.row = self.rows - 1
                self.cells[self.row][self.column] = character
                self.column += 2 if unicodedata.east_asian_width(character) in ("W", "F") else 1

    def text(self):
        return ["".join(row).rstrip() for row in self.cells if "".join(row).strip()]


class PTYPromptTests(unittest.TestCase):
    def run_session(self, steps, section="prompts", expected_exit=0, columns=80, rows=24,
                    redirected_stdout=False, screen=None, arguments=()):
        master, slave = pty.openpty()
        original = termios.tcgetattr(slave)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))
        process = subprocess.Popen(
            [DEMO, section, *arguments],
            stdin=slave, stdout=subprocess.DEVNULL if redirected_stdout else slave, stderr=slave,
            env={**os.environ, "NO_COLOR": "1", "TERM": "xterm-256color", "LANG": "en_US.UTF-8"},
        )
        pending = b""
        transcript = bytearray()

        def receive():
            nonlocal pending
            chunk = os.read(master, 65536)
            pending += chunk
            transcript.extend(chunk)
            if screen is not None:
                screen.feed(chunk)

        def expect(text):
            nonlocal pending
            deadline = time.monotonic() + 20
            while text not in pending:
                self.assertLess(time.monotonic(), deadline, f"waiting for {text!r} in {pending!r}")
                if select.select([master], [], [], 0.1)[0]:
                    receive()
            pending = pending.split(text, 1)[1]

        try:
            for wait_for, send in steps:
                expect(wait_for)
                if callable(send):
                    send(master, slave, process)
                elif isinstance(send, int):
                    process.send_signal(send)
                elif send is not None:
                    os.write(master, send)
            self.assertEqual(process.wait(timeout=10), expected_exit)
            while select.select([master], [], [], 0)[0]:
                receive()
            restored = termios.tcgetattr(slave)
            ignored = getattr(termios, "PENDIN", 0)
            original[3] &= ~ignored
            restored[3] &= ~ignored
            self.assertEqual(original, restored, "terminal settings were not restored")
            return bytes(transcript)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)

    def test_full_conversation(self):
        self.run_session([
            (b"Enter select", b"\x1b[B"),
            (b"> (*) Android", b"\r"),
            (b"result: platform=1", None),
            (b"Continue? [Y/n]: ", b"n"),
            (b"result: continue=false", None),
            (b"Enter done", b"/"),
            (b"Filter:", b"pix"),
            (b"Pixel Tablet", b" "),
            (b"> [x] Pixel 9", b"\x1b\r"),
            (b"result: devices=0,3", None),
            (b"Tests failed [R/s/a]: ", b"x"),
            (b"Press one of r, s, a.", b"S"),
            (b"result: action=s", None),
            (b"Scheme [MyApp]: ", b"\r"),
            (b"result: scheme=MyApp", None),
            (b"Password: ", b"hunter2\r"),
            (b"result: secret-length=7", None),
        ])

    def test_escape_cancels_and_restores_terminal(self):
        self.run_session([
            (b"Enter select", b"\x1b"),
            (b"result: platform=cancelled", None),
            (b"Continue? [Y/n]: ", b"\x04"),
            (b"result: continue=cancelled", None),
            (b"Enter done", b"\x03"),
            (b"result: devices=cancelled", None),
            (b"Tests failed [R/s/a]: ", b"\r"),
            (b"result: action=r", None),
            (b"Scheme [MyApp]: ", b"\x04"),
            (b"result: scheme=cancelled", None),
            (b"Password: ", b"\x04"),
            (b"result: secret-length=cancelled", None),
        ])

    def test_secret_is_not_echoed(self):
        output = self.run_session([
            (b"Enter select", b"\r"),
            (b"Continue? [Y/n]: ", b"\r"),
            (b"Enter done", b"\r"),
            (b"Tests failed [R/s/a]: ", b"\r"),
            (b"Scheme [MyApp]: ", b"Other\r"),
            (b"Password: ", b"hunter2\r"),
            (b"result: secret-length=7", None),
        ])
        self.assertNotIn(b"hunter2", output)

    def test_termination_signals_restore_both_input_modes(self):
        for section in ("raw", "secret"):
            for termination in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
                with self.subTest(section=section, termination=termination):
                    self.run_session([(f"ready: {section}".encode(), termination)],
                                     section=section, expected_exit=-termination)

    def test_nested_raw_scope_restores_on_throw(self):
        self.run_session([(b"raw restored after throw", None)], section="raw-throw")

    def test_stderr_dimensions_with_redirected_stdout(self):
        self.run_session([(b"size=31,12", None)], section="size", columns=31, rows=12,
                         redirected_stdout=True)

    def test_live_region_survives_small_screen_and_resize(self):
        screen = Screen(20, 6)

        def resize(master, slave, process):
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 3, 12, 0, 0))
            screen.resize(12, 3)
            os.write(master, b"x")

        self.run_session([(b"frame-one", resize), (b"frame-two", b"x"), (b"layout-done", None)],
                         section="layout", columns=20, rows=6, redirected_stdout=True, screen=screen)
        self.assertEqual(screen.text(), ["layout-done"])

    def test_line_editor_reading_completion_and_persistent_history(self):
        with tempfile.TemporaryDirectory() as directory:
            history = os.path.join(directory, "history")
            if sys.platform == "darwin":
                first = [(b"edit> ", b"tap_e\t\r"), (b"edited: tap_element", None),
                         (b"edit> ", b"\x1b[A\r"), (b"edited: tap_element", None)]
            else:
                first = [(b"edit> ", b"tap_element\r"), (b"edited: tap_element", None),
                         (b"edit> ", b"status\r"), (b"edited: status", None)]
            self.run_session(first, section="line-editor", arguments=(history,))
            if sys.platform == "darwin":
                self.assertTrue(os.path.isfile(history))
                self.run_session([(b"edit> ", b"\x1b[A\r"), (b"edited: tap_element", None),
                                  (b"edit> ", b"\x04"), (b"edited: EOF", None)],
                                 section="line-editor", arguments=(history,))


if __name__ == "__main__":
    unittest.main()
