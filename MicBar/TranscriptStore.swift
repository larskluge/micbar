import Foundation
import Combine

struct ChainEntry: Identifiable, Equatable {
    let id: UUID
    let label: String
    let text: String
}

struct TranscriptRecord: Identifiable {
    let id: UUID
    let timestamp: Date
    var rawText: String
    var chain: [ChainEntry] = []
    var pendingLabel: String?
    var pendingError: String?

    /// The text that the next operation should work on: last chain entry or rawText.
    var latestText: String {
        chain.last?.text ?? rawText
    }

    var isBusy: Bool {
        pendingLabel != nil
    }
}

enum RecordingState {
    case idle, waiting, recording, processing
}

class TranscriptStore: ObservableObject {
    @Published var records: [TranscriptRecord] = []
    @Published var recordingState: RecordingState = .idle

    func addTranscript(raw: String, improved: String?, improveError: String? = nil, answer: String? = nil, answerError: String? = nil) {
        var record = TranscriptRecord(
            id: UUID(),
            timestamp: Date(),
            rawText: raw
        )
        if let improved = improved {
            record.chain.append(ChainEntry(id: UUID(), label: "Improved", text: improved))
        }
        if let error = improveError {
            record.pendingError = error
        }
        if let answer = answer {
            record.chain.append(ChainEntry(id: UUID(), label: "Answer", text: answer))
        }
        if let error = answerError, record.pendingError == nil {
            record.pendingError = error
        }
        records.insert(record, at: 0)
    }

    func updateRawText(id: UUID, text: String) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].rawText = text
    }

    func updateChainText(recordId: UUID, entryId: UUID, text: String) {
        guard let idx = records.firstIndex(where: { $0.id == recordId }),
              let entryIdx = records[idx].chain.firstIndex(where: { $0.id == entryId }) else { return }
        let old = records[idx].chain[entryIdx]
        records[idx].chain[entryIdx] = ChainEntry(id: old.id, label: old.label, text: text)
    }

    func improveText(id: UUID) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].pendingLabel = "Improving..."
        records[idx].pendingError = nil
        let input = records[idx].latestText

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = runImproveWriting(input)
            DispatchQueue.main.async {
                guard let self = self,
                      let idx = self.records.firstIndex(where: { $0.id == id }) else { return }
                if let improved = result.text {
                    self.records[idx].chain.append(ChainEntry(id: UUID(), label: "Improved", text: improved))
                } else {
                    self.records[idx].pendingError = result.error
                }
                self.records[idx].pendingLabel = nil
            }
        }
    }

    func answerQuestion(id: UUID) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].pendingLabel = "Answering..."
        records[idx].pendingError = nil
        let input = records[idx].latestText

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = runAnswerQuestion(input)
            DispatchQueue.main.async {
                guard let self = self,
                      let idx = self.records.firstIndex(where: { $0.id == id }) else { return }
                if let answer = result.text {
                    self.records[idx].chain.append(ChainEntry(id: UUID(), label: "Answer", text: answer))
                } else {
                    self.records[idx].pendingError = result.error
                }
                self.records[idx].pendingLabel = nil
            }
        }
    }

    func summarize(id: UUID) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].pendingLabel = "Summarizing..."
        records[idx].pendingError = nil
        let input = records[idx].latestText

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = runSummarize(input)
            DispatchQueue.main.async {
                guard let self = self,
                      let idx = self.records.firstIndex(where: { $0.id == id }) else { return }
                if let summary = result.text {
                    self.records[idx].chain.append(ChainEntry(id: UUID(), label: "Summary", text: summary))
                } else {
                    self.records[idx].pendingError = result.error
                }
                self.records[idx].pendingLabel = nil
            }
        }
    }

    func keyPoints(id: UUID) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].pendingLabel = "Extracting key points..."
        records[idx].pendingError = nil
        let input = records[idx].latestText

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = runKeyPoints(input)
            DispatchQueue.main.async {
                guard let self = self,
                      let idx = self.records.firstIndex(where: { $0.id == id }) else { return }
                if let points = result.text {
                    self.records[idx].chain.append(ChainEntry(id: UUID(), label: "Key Points", text: points))
                } else {
                    self.records[idx].pendingError = result.error
                }
                self.records[idx].pendingLabel = nil
            }
        }
    }

    func translate(id: UUID, language: String) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        let flag = LanguageSettings.flagForLanguage[language] ?? ""
        records[idx].pendingLabel = "Translating to \(language)..."
        records[idx].pendingError = nil
        let input = records[idx].latestText

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = runTranslate(input, targetLanguage: language)
            DispatchQueue.main.async {
                guard let self = self,
                      let idx = self.records.firstIndex(where: { $0.id == id }) else { return }
                if let translated = result.text {
                    self.records[idx].chain.append(ChainEntry(id: UUID(), label: "\(flag) \(language)", text: translated))
                } else {
                    self.records[idx].pendingError = result.error
                }
                self.records[idx].pendingLabel = nil
            }
        }
    }
}
