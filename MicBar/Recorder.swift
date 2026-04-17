import Foundation

final class Recorder {
    private let audioRecorder = AudioRecorder()
    private let log = Logger.shared
    private var startInFlight = false

    var onReady: (() -> Void)?

    /// Starts recording asynchronously. `completion` fires on the main queue with `true` on
    /// success or `false` on failure/timeout. If `AudioRecorder.start()` hangs past `timeout`
    /// (typically a stuck CoreAudio default input device), completion fires with `false` and
    /// the caller can reset UI state. A late-returning orphan engine is cancelled.
    func start(timeout: TimeInterval = 3.0, completion: @escaping (Bool) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))

        if startInFlight {
            log.warning("start rejected: previous start still in-flight (audio subsystem may be stuck, quit and reopen)")
            completion(false)
            return
        }
        startInFlight = true

        let lock = NSLock()
        var fired = false
        func fire(_ ok: Bool) {
            lock.lock()
            let shouldFire = !fired
            fired = true
            lock.unlock()
            if shouldFire { DispatchQueue.main.async { completion(ok) } }
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { fire(false); return }
            var started = false
            do {
                try self.audioRecorder.start()
                started = true
            } catch {
                self.log.warning("failed to start audio recorder: \(error)")
            }
            DispatchQueue.main.async {
                self.startInFlight = false
                guard started else {
                    fire(false)
                    return
                }
                lock.lock()
                let alreadyFired = fired
                lock.unlock()
                if alreadyFired {
                    self.log.warning("audio engine started late after timeout — cancelling orphan engine")
                    self.audioRecorder.cancel()
                } else {
                    self.onReady?()
                    fire(true)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            lock.lock()
            let alreadyFired = fired
            lock.unlock()
            if !alreadyFired {
                self?.log.warning("audio engine start timed out after \(timeout)s — CoreAudio may be stuck")
                fire(false)
            }
        }
    }

    func stop() -> String? {
        log.info("stopping recording")
        let wavData = audioRecorder.stop()
        log.info("captured \(wavData.count) bytes WAV")

        let result = runTranscription(wavData: wavData)
        return result.text
    }

    func forceKill() {
        audioRecorder.cancel()
        log.info("recording cancelled")
    }

    var isRunning: Bool { audioRecorder.isRecording }
    var inputDeviceName: String? { audioRecorder.inputDeviceName }
}
