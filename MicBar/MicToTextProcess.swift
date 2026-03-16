import Foundation

final class MicToTextProcess {
    private let recorder = AudioRecorder()
    private let log = Logger.shared

    var onReady: (() -> Void)?

    func start() -> Bool {
        do {
            try recorder.start()
        } catch {
            log.warning("failed to start audio recorder: \(error)")
            return false
        }

        // Native recording is ready immediately — no subprocess startup delay
        DispatchQueue.main.async { self.onReady?() }
        return true
    }

    func stop() -> String? {
        log.info("stopping recording")
        let wavData = recorder.stop()
        log.info("captured \(wavData.count) bytes WAV")

        let result = runTranscription(wavData: wavData)
        return result.text
    }

    func forceKill() {
        recorder.cancel()
        log.info("recording cancelled")
    }

    var isRunning: Bool { recorder.isRecording }
}
