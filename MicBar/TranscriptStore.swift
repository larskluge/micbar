import Foundation
import Combine
import AppKit

struct ChainEntry: Identifiable, Equatable {
    let id: UUID
    let label: String
    let text: String
}

enum TranscriptSource {
    case recording
    case pasted
}

struct TranscriptRecord: Identifiable {
    let id: UUID
    let timestamp: Date
    var rawText: String
    var source: TranscriptSource = .recording
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

    func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let record = TranscriptRecord(
            id: UUID(),
            timestamp: Date(),
            rawText: text,
            source: .pasted
        )
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

    private func ollamaConfig(systemPrompt: String) -> OllamaConfig {
        OllamaConfig(
            model: OllamaSettings.shared.selectedModel,
            systemPrompt: systemPrompt
        )
    }

    func improveText(id: UUID) {
        let useLocal = OllamaSettings.shared.useLocal
        runLLMOperation(id: id, pendingLabel: "Improving\(useLocal ? " locally" : "")...", chainLabel: "Improved") { input in
            if useLocal {
                return runOllamaCall(input, label: "improve-local", config: self.ollamaConfig(systemPrompt: ImproveWritingConfig().systemPrompt))
            }
            return runImproveWriting(input)
        }
    }

    func answerQuestion(id: UUID) {
        let useLocal = OllamaSettings.shared.useLocal
        runLLMOperation(id: id, pendingLabel: "Answering\(useLocal ? " locally" : "")...", chainLabel: "Answer") { input in
            if useLocal {
                return runOllamaCall(input, label: "answer-local", config: self.ollamaConfig(systemPrompt: AnswerQuestionConfig().systemPrompt))
            }
            return runAnswerQuestion(input)
        }
    }

    func summarize(id: UUID) {
        let useLocal = OllamaSettings.shared.useLocal
        runLLMOperation(id: id, pendingLabel: "Summarizing\(useLocal ? " locally" : "")...", chainLabel: "Summary") { input in
            if useLocal {
                return runOllamaCall(input, label: "summarize-local", config: self.ollamaConfig(systemPrompt: SummarizeConfig().systemPrompt))
            }
            return runSummarize(input)
        }
    }

    func keyPoints(id: UUID) {
        let useLocal = OllamaSettings.shared.useLocal
        runLLMOperation(id: id, pendingLabel: "Extracting key points\(useLocal ? " locally" : "")...", chainLabel: "Key Points") { input in
            if useLocal {
                return runOllamaCall(input, label: "keypoints-local", config: self.ollamaConfig(systemPrompt: KeyPointsConfig().systemPrompt))
            }
            return runKeyPoints(input)
        }
    }

    private func runLLMOperation(id: UUID, pendingLabel: String, chainLabel: String, operation: @escaping (String) -> ImproveResult) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].pendingLabel = pendingLabel
        records[idx].pendingError = nil
        let input = records[idx].latestText

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = operation(input)
            DispatchQueue.main.async {
                guard let self = self,
                      let idx = self.records.firstIndex(where: { $0.id == id }) else { return }
                if let text = result.text {
                    self.records[idx].chain.append(ChainEntry(id: UUID(), label: chainLabel, text: text))
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
