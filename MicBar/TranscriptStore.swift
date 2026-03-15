import Foundation
import Combine

struct TranscriptRecord: Identifiable {
    let id: UUID
    let timestamp: Date
    var rawText: String
    var improvedText: String?
    var isImproving: Bool
}

class TranscriptStore: ObservableObject {
    @Published var records: [TranscriptRecord] = []

    func addTranscript(raw: String, improved: String?) {
        let record = TranscriptRecord(
            id: UUID(),
            timestamp: Date(),
            rawText: raw,
            improvedText: improved,
            isImproving: false
        )
        records.insert(record, at: 0)
    }

    func updateRawText(id: UUID, text: String) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].rawText = text
    }

    func updateImprovedText(id: UUID, text: String) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].improvedText = text
        records[idx].isImproving = false
    }

    func improveTranscript(id: UUID) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].isImproving = true
        let raw = records[idx].rawText

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = runImproveWriting(raw)
            DispatchQueue.main.async {
                guard let self = self,
                      let idx = self.records.firstIndex(where: { $0.id == id }) else { return }
                if let improved = result {
                    self.records[idx].improvedText = improved
                }
                self.records[idx].isImproving = false
            }
        }
    }
}
