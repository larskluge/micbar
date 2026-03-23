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
    var answerText: String?
    var isAnswering: Bool = false
    var answerError: String?
}

enum RecordingState {
    case idle, waiting, recording, processing
}

class TranscriptStore: ObservableObject {
    @Published var records: [TranscriptRecord] = []
    @Published var recordingState: RecordingState = .idle

    func addTranscript(raw: String, improved: String?, improveError: String? = nil, answer: String? = nil, answerError: String? = nil) {
        let record = TranscriptRecord(
            id: UUID(),
            timestamp: Date(),
            rawText: raw,
            improvedText: improved,
            isImproving: false,
            improveError: improveError,
            answerText: answer,
            isAnswering: false,
            answerError: answerError
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

    func updateAnswerText(id: UUID, text: String) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].answerText = text
        records[idx].isAnswering = false
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

    func answerQuestion(id: UUID) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].isAnswering = true
        records[idx].answerError = nil
        let raw = records[idx].rawText

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = runAnswerQuestion(raw)
            DispatchQueue.main.async {
                guard let self = self,
                      let idx = self.records.firstIndex(where: { $0.id == id }) else { return }
                if let answer = result.text {
                    self.records[idx].answerText = answer
                } else {
                    self.records[idx].answerError = result.error
                }
                self.records[idx].isAnswering = false
            }
        }
    }
}
