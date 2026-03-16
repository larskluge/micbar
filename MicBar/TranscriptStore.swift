import Foundation
import Combine

struct TranscriptRecord: Identifiable {
    let id: UUID
    let timestamp: Date
    var rawText: String
    var improvedText: String?
    var isImproving: Bool
    var improveError: String?
    var rawEdited: Bool = false
}

enum RecordingState {
    case idle, waiting, recording, processing
}

class TranscriptStore: ObservableObject {
    @Published var records: [TranscriptRecord] = []
    @Published var recordingState: RecordingState = .idle

    func addTranscript(raw: String, improved: String?, improveError: String? = nil) {
        let record = TranscriptRecord(
            id: UUID(),
            timestamp: Date(),
            rawText: raw,
            improvedText: improved,
            isImproving: false,
            improveError: improveError
        )
        records.insert(record, at: 0)
    }

    func updateRawText(id: UUID, text: String) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].rawText = text
        records[idx].rawEdited = true
    }

    func updateImprovedText(id: UUID, text: String) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].improvedText = text
        records[idx].isImproving = false
    }

    func improveTranscript(id: UUID) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].isImproving = true
        records[idx].improveError = nil
        records[idx].rawEdited = false
        let raw = records[idx].rawText

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = runImproveWriting(raw)
            DispatchQueue.main.async {
                guard let self = self,
                      let idx = self.records.firstIndex(where: { $0.id == id }) else { return }
                if let improved = result.text {
                    self.records[idx].improvedText = improved
                } else {
                    self.records[idx].improveError = result.error
                }
                self.records[idx].isImproving = false
            }
        }
    }
}
