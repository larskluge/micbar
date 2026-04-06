import Foundation

final class Recorder {
    private let audioRecorder = AudioRecorder()
    private let log = Logger.shared

    var onReady: (() -> Void)?

    func start() -> Bool {
        do {
            try audioRecorder.start()
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
