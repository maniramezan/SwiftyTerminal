#!/usr/bin/env python3
"""Drive `swifty-terminal-demo prompts` through a real pseudo-terminal.

Unit tests cover the prompt logic with ScriptedTerminal; this covers what they cannot: raw-mode
key reading, hidden input, and that the terminal settings are restored afterwards.
Run after `swift build`.
"""
import os
import pty
import select
import subprocess
import termios
import time
import unittest

DEMO = os.environ.get("SWIFTY_TERMINAL_DEMO", ".build/debug/swifty-terminal-demo")


class PTYPromptTests(unittest.TestCase):
    def run_session(self, steps):
        master, slave = pty.openpty()
        original = termios.tcgetattr(slave)
        process = subprocess.Popen(
            [DEMO, "prompts"],
            stdin=slave, stdout=slave, stderr=slave,
            env={**os.environ, "NO_COLOR": "1", "TERM": "xterm-256color", "LANG": "en_US.UTF-8"},
        )
        pending = b""

        def expect(text):
            nonlocal pending
            deadline = time.monotonic() + 20
            while text not in pending:
                self.assertLess(time.monotonic(), deadline, f"waiting for {text!r} in {pending!r}")
                if select.select([master], [], [], 0.1)[0]:
                    pending += os.read(master, 65536)
            pending = pending.split(text, 1)[1]

        try:
            for wait_for, send in steps:
                expect(wait_for)
                if send is not None:
                    os.write(master, send)
            process.wait(timeout=10)
            restored = termios.tcgetattr(slave)
            # macOS sets PENDIN when terminal input settings change.
            ignored = getattr(termios, "PENDIN", 0)
            original[3] &= ~ignored
            restored[3] &= ~ignored
            self.assertEqual(original, restored, "terminal settings were not restored")
            return pending
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(slave)

    def test_full_conversation(self):
        self.run_session([
            (b"Enter select", b"\x1b[B"),          # down arrow
            (b"> (*) Android", b"\r"),
            (b"result: platform=1", None),
            (b"Continue? [Y/n]: ", b"n"),
            (b"result: continue=false", None),
            (b"Enter done", b"/"),                 # start filtering
            (b"Filter:", b"pix"),
            (b"Pixel Tablet", b" "),               # toggle Pixel 9
            (b"> [x] Pixel 9", b"\x1b\r"),         # clear filter, then Enter right away
            (b"result: devices=0,3", None),
            (b"Tests failed [R/s/a]: ", b"x"),     # invalid key, then valid
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
            (b"Continue? [Y/n]: ", b"\x04"),       # Ctrl-D
            (b"result: continue=cancelled", None),
            (b"Enter done", b"\x03"),              # Ctrl-C cancels a menu
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


if __name__ == "__main__":
    unittest.main()
