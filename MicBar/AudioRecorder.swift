import AVFoundation

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var buffer = Data()
    private let log = Logger.shared
    private let lock = NSLock()

    var isRecording: Bool { engine.isRunning }

    func start() throws {
        buffer = Data()

        // Fully tear down previous session to avoid stale internal state
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine.reset()

        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        log.info("audio input: \(hwFormat.sampleRate)Hz, \(hwFormat.channelCount)ch")

        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            throw AudioRecorderError.noInputDevice
        }

        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            throw AudioRecorderError.converterFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] pcmBuffer, _ in
            guard let self = self else { return }
            self.convert(pcmBuffer, using: converter, targetFormat: targetFormat)
        }

        try engine.start()
        log.info("audio engine started")
    }

    func stop() -> Data {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        log.info("audio engine stopped, \(buffer.count) bytes captured")

        lock.lock()
        let pcmData = buffer
        buffer = Data()
        lock.unlock()

        var wav = buildWAVHeader(dataLength: pcmData.count)
        wav.append(pcmData)
        return wav
    }

    func cancel() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        buffer = Data()
        lock.unlock()
        log.info("audio engine cancelled")
    }

    private func convert(_ pcmBuffer: AVAudioPCMBuffer, using converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        let frameCapacity = AVAudioFrameCount(Double(pcmBuffer.frameLength) * 16000.0 / pcmBuffer.format.sampleRate) + 1
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }

        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return pcmBuffer
        }

        if let error = error {
            log.warning("audio conversion error: \(error)")
            return
        }

        guard outputBuffer.frameLength > 0 else { return }

        let byteCount = Int(outputBuffer.frameLength) * 2  // 16-bit = 2 bytes per sample
        lock.lock()
        outputBuffer.int16ChannelData!.pointee.withMemoryRebound(to: UInt8.self, capacity: byteCount) { ptr in
            buffer.append(ptr, count: byteCount)
        }
        lock.unlock()
    }
}

func buildWAVHeader(dataLength: Int) -> Data {
    var header = Data(capacity: 44)
    let totalSize = UInt32(36 + dataLength)
    let sampleRate: UInt32 = 16000
    let channels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let byteRate: UInt32 = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
    let blockAlign: UInt16 = channels * (bitsPerSample / 8)

    header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
    header.append(contentsOf: withUnsafeBytes(of: totalSize.littleEndian) { Array($0) })
    header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
    header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
    header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // subchunk size
    header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // PCM
    header.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
    header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
    header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
    header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
    header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
    header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
    header.append(contentsOf: withUnsafeBytes(of: UInt32(dataLength).littleEndian) { Array($0) })

    return header
}

enum AudioRecorderError: Error, LocalizedError {
    case noInputDevice
    case converterFailed

    var errorDescription: String? {
        switch self {
        case .noInputDevice: return "No audio input device available"
        case .converterFailed: return "Failed to create audio format converter"
        }
    }
}
