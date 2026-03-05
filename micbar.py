#!/usr/bin/env python3
import rumps
import subprocess
import signal
import os


class MicBar(rumps.App):
    def __init__(self):
        super().__init__("\U0001F3A4", quit_button=None)
        self.proc = None
        self.menu = [
            rumps.MenuItem("Start Recording", callback=self.start),
            rumps.MenuItem("Stop -> Clipboard", callback=self.stop_copy),
            rumps.MenuItem("Stop -> Improve -> Clipboard", callback=self.stop_improve),
            None,
            rumps.MenuItem("Quit", callback=rumps.quit_application),
        ]
        self.menu["Stop -> Clipboard"].set_callback(None)
        self.menu["Stop -> Improve -> Clipboard"].set_callback(None)

    def _set_recording(self, on):
        if on:
            self.title = "\U0001F534"
            self.menu["Start Recording"].set_callback(None)
            self.menu["Stop -> Clipboard"].set_callback(self.stop_copy)
            self.menu["Stop -> Improve -> Clipboard"].set_callback(self.stop_improve)
        else:
            self.title = "\U0001F3A4"
            self.menu["Start Recording"].set_callback(self.start)
            self.menu["Stop -> Clipboard"].set_callback(None)
            self.menu["Stop -> Improve -> Clipboard"].set_callback(None)

    def start(self, _):
        self.proc = subprocess.Popen(
            ["mictotext"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            preexec_fn=os.setsid,
        )
        self._set_recording(True)

    def _stop_and_get_text(self):
        if not self.proc:
            return None
        # Send SIGINT to the process group (same as Ctrl-C)
        os.killpg(os.getpgid(self.proc.pid), signal.SIGINT)
        stdout, _ = self.proc.communicate(timeout=30)
        self.proc = None
        self._set_recording(False)
        return stdout.decode().strip()

    def stop_copy(self, _):
        text = self._stop_and_get_text()
        if text:
            subprocess.run(["pbcopy"], input=text, text=True)
            preview = text[:80] + ("…" if len(text) > 80 else "")
            rumps.notification("Copied to clipboard", "", preview)

    def stop_improve(self, _):
        text = self._stop_and_get_text()
        if text:
            result = subprocess.run(
                ["improve-writing"],
                input=text,
                capture_output=True,
                text=True,
                timeout=60,
            )
            improved = result.stdout.strip() or text
            subprocess.run(["pbcopy"], input=improved, text=True)
            preview = improved[:80] + ("…" if len(improved) > 80 else "")
            rumps.notification("Improved & copied to clipboard", "", preview)


if __name__ == "__main__":
    MicBar().run()
