import XCTest
import Foundation

// MARK: - Duplicated from AudioRecorder.swift (can't import executable target)

private func buildWAVHeader(dataLength: Int) -> Data {
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

// MARK: - WAV Header Tests

final class WAVHeaderTests: XCTestCase {

    func testHeaderIs44Bytes() {
        let header = buildWAVHeader(dataLength: 0)
        XCTAssertEqual(header.count, 44)
    }

    func testRIFFMarker() {
        let header = buildWAVHeader(dataLength: 100)
        XCTAssertEqual(String(data: header[0..<4], encoding: .ascii), "RIFF")
    }

    func testWAVEMarker() {
        let header = buildWAVHeader(dataLength: 100)
        XCTAssertEqual(String(data: header[8..<12], encoding: .ascii), "WAVE")
    }

    func testFmtMarker() {
        let header = buildWAVHeader(dataLength: 100)
        XCTAssertEqual(String(data: header[12..<16], encoding: .ascii), "fmt ")
    }

    func testDataMarker() {
        let header = buildWAVHeader(dataLength: 100)
        XCTAssertEqual(String(data: header[36..<40], encoding: .ascii), "data")
    }

    func testTotalFileSize() {
        let dataLen = 32000  // 1 second of 16kHz mono 16-bit
        let header = buildWAVHeader(dataLength: dataLen)
        // Bytes 4-7: file size - 8 = 36 + dataLen
        let fileSize = header[4..<8].withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(fileSize, UInt32(36 + dataLen))
    }

    func testDataChunkSize() {
        let dataLen = 32000
        let header = buildWAVHeader(dataLength: dataLen)
        // Bytes 40-43: data chunk size
        let chunkSize = header[40..<44].withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(chunkSize, UInt32(dataLen))
    }

    func testSampleRate() {
        let header = buildWAVHeader(dataLength: 0)
        // Bytes 24-27: sample rate
        let sampleRate = header[24..<28].withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(sampleRate, 16000)
    }

    func testChannelCount() {
        let header = buildWAVHeader(dataLength: 0)
        // Bytes 22-23: number of channels
        let channels = header[22..<24].withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(channels, 1)
    }

    func testBitsPerSample() {
        let header = buildWAVHeader(dataLength: 0)
        // Bytes 34-35: bits per sample
        let bits = header[34..<36].withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(bits, 16)
    }

    func testPCMFormat() {
        let header = buildWAVHeader(dataLength: 0)
        // Bytes 20-21: audio format (1 = PCM)
        let format = header[20..<22].withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(format, 1)
    }

    func testByteRate() {
        let header = buildWAVHeader(dataLength: 0)
        // Bytes 28-31: byte rate = sampleRate * channels * bitsPerSample/8
        let byteRate = header[28..<32].withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(byteRate, 32000)  // 16000 * 1 * 2
    }

    func testBlockAlign() {
        let header = buildWAVHeader(dataLength: 0)
        // Bytes 32-33: block align = channels * bitsPerSample/8
        let blockAlign = header[32..<34].withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(blockAlign, 2)  // 1 * 2
    }

    func testZeroDataLength() {
        let header = buildWAVHeader(dataLength: 0)
        let chunkSize = header[40..<44].withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(chunkSize, 0)
        let fileSize = header[4..<8].withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(fileSize, 36)
    }
}
