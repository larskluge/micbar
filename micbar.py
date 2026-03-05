#!/usr/bin/env python3
from AppKit import NSApplication, NSApplicationActivationPolicyAccessory
from Foundation import NSProcessInfo
NSApplication.sharedApplication().setActivationPolicy_(NSApplicationActivationPolicyAccessory)
NSProcessInfo.processInfo().beginActivityWithOptions_reason_(0x00FFFFFF, "Audio recording")
import rumps
import subprocess
import signal
import os
import threading
import logging
import ctypes
import ctypes.util

ICON_MIC = "\U0001F3A4"
ICON_REC = "\U0001F534"
ICON_WAIT = "\u23F3"

logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s [%(levelname)s] %(message)s",
    filename=os.path.expanduser("~/Library/Logs/micbar.log"),
    filemode="a",
)
log = logging.getLogger("micbar")

def _get_qos_class():
    libsys = ctypes.CDLL(ctypes.util.find_library("System"))
    qos = ctypes.c_uint(0)
    rel = ctypes.c_int(0)
    libsys.qos_class_self(ctypes.byref(qos), ctypes.byref(rel))
    QOS_NAMES = {0x21: "USER_INTERACTIVE", 0x19: "USER_INITIATED", 0x15: "DEFAULT", 0x11: "UTILITY", 0x09: "BACKGROUND", 0x00: "UNSPECIFIED"}
    return QOS_NAMES.get(qos.value, f"UNKNOWN({qos.value:#x})")

log.info("=== micbar starting ===")
log.info("PID=%d  PPID=%d", os.getpid(), os.getppid())
log.info("QoS class: %s", _get_qos_class())
log.info("PATH=%s", os.environ.get("PATH", "<unset>"))
log.info("HOME=%s", os.environ.get("HOME", "<unset>"))
log.info("TMPDIR=%s", os.environ.get("TMPDIR", "<unset>"))
log.info("ENV keys: %s", sorted(os.environ.keys()))


class MicBar(rumps.App):
    def __init__(self):
        super().__init__(ICON_MIC, quit_button=None)
        self.proc = None
        log.info("MicBar initialized")
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
            self.title = ICON_REC
            self.menu["Start Recording"].set_callback(None)
            self.menu["Stop -> Clipboard"].set_callback(self.stop_copy)
            self.menu["Stop -> Improve -> Clipboard"].set_callback(self.stop_improve)
        else:
            self.menu["Start Recording"].set_callback(self.start)
            self.menu["Stop -> Clipboard"].set_callback(None)
            self.menu["Stop -> Improve -> Clipboard"].set_callback(None)

    def start(self, _):
        log.info("start: launching mictotext")
        self.proc = subprocess.Popen(
            ["mictotext"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            preexec_fn=os.setsid,
        )
        log.info("start: mictotext PID=%d", self.proc.pid)
        # Log child process tree after a short delay
        threading.Thread(target=self._log_proc_tree, args=(self.proc.pid,), daemon=True).start()
        self.title = ICON_WAIT
        self.menu["Start Recording"].set_callback(None)
        self.menu["Stop -> Clipboard"].set_callback(self.stop_copy)
        self.menu["Stop -> Improve -> Clipboard"].set_callback(self.stop_improve)
        threading.Thread(target=self._wait_for_ready, daemon=True).start()

    def _log_proc_tree(self, pid):
        import time
        time.sleep(2)
        try:
            result = subprocess.run(
                ["ps", "-o", "pid,ppid,pgid,nice,pri,command", "-p",
                 str(pid), "--ppid", str(pid)],
                capture_output=True, text=True
            )
            # Also find ffmpeg
            result2 = subprocess.run(
                ["pgrep", "-P", str(pid)], capture_output=True, text=True
            )
            child_pids = result2.stdout.strip().split()
            all_pids = [str(pid)] + child_pids
            for cpid in child_pids:
                r = subprocess.run(["pgrep", "-P", cpid], capture_output=True, text=True)
                all_pids.extend(r.stdout.strip().split())
            result3 = subprocess.run(
                ["ps", "-o", "pid,ppid,pgid,nice,pri,command", "-p",
                 ",".join(all_pids)],
                capture_output=True, text=True
            )
            log.info("process tree:\n%s", result3.stdout)
        except Exception as e:
            log.exception("_log_proc_tree error: %s", e)

    def _wait_for_ready(self):
        proc = self.proc
        try:
            for line in proc.stderr:
                log.debug("stderr: %s", line.rstrip())
                if b"Recording now" in line:
                    log.info("mictotext ready, recording")
                    self.title = ICON_REC
                    break
            # Drain remaining stderr
            for line in proc.stderr:
                log.debug("stderr: %s", line.rstrip())
        except Exception as e:
            log.exception("_wait_for_ready error: %s", e)

    def _notify(self, title, body):
        body_escaped = body.replace("\\", "\\\\").replace('"', '\\"')
        title_escaped = title.replace("\\", "\\\\").replace('"', '\\"')
        subprocess.run([
            "osascript", "-e",
            f'display notification "{body_escaped}" with title "{title_escaped}"',
        ])

    def _stop_and_get_text(self):
        if not self.proc:
            log.warning("_stop_and_get_text: no proc")
            return None
        pid = self.proc.pid
        log.info("stopping mictotext PID=%d", pid)
        os.killpg(os.getpgid(pid), signal.SIGINT)
        log.debug("SIGINT sent, reading stdout...")
        stdout = self.proc.stdout.read()
        log.debug("stdout: %d bytes", len(stdout))
        rc = self.proc.wait(timeout=30)
        log.info("mictotext exited rc=%d", rc)
        self.proc = None
        text = stdout.decode().strip()
        log.info("transcription (%d chars): %s", len(text), text[:200])
        return text

    def _stop_and_finish(self, postprocess=None):
        self.title = ICON_WAIT
        self._set_recording(False)
        def work():
            log.info("stop called (improve=%s)", postprocess is not None)
            text = self._stop_and_get_text()
            if text and postprocess:
                text = postprocess(text)
            if text:
                subprocess.run(["pbcopy"], input=text, text=True)
                preview = text[:80] + ("…" if len(text) > 80 else "")
                label = "Improved & copied to clipboard" if postprocess else "Copied to clipboard"
                self._notify(label, preview)
                log.info("copied to clipboard, notified")
            else:
                log.warning("no text from transcription")
                self._notify("Recording", "No speech detected")
            self.title = ICON_MIC
        threading.Thread(target=work, daemon=True).start()

    def _improve(self, text):
        result = subprocess.run(
            ["improve-writing"],
            input=text,
            capture_output=True,
            text=True,
            timeout=60,
        )
        return result.stdout.strip() or text

    def stop_copy(self, _):
        self._stop_and_finish()

    def stop_improve(self, _):
        self._stop_and_finish(postprocess=self._improve)


if __name__ == "__main__":
    MicBar().run()
