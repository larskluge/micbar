import SwiftUI
import ServiceManagement

struct HistoryView: View {
    @ObservedObject var store: TranscriptStore
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled

    private let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            if store.records.isEmpty {
                Spacer()
                Text("No transcripts yet")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.records) { record in
                            TranscriptCard(record: record, store: store, formatter: timestampFormatter)
                        }
                    }
                    .padding(16)
                }
            }

            Divider()

            // Settings section
            VStack(spacing: 12) {
                Toggle("Launch at Login", isOn: $loginEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: loginEnabled) { newValue in
                        toggleLogin(newValue)
                    }

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            }
            .padding(16)
        }
        .frame(minWidth: 420, minHeight: 300)
    }

    private func toggleLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger.shared.warning("login item toggle error: \(error)")
            loginEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}

struct TranscriptCard: View {
    let record: TranscriptRecord
    @ObservedObject var store: TranscriptStore
    let formatter: DateFormatter

    private var rawBinding: Binding<String> {
        Binding(
            get: { store.records.first(where: { $0.id == record.id })?.rawText ?? record.rawText },
            set: { store.updateRawText(id: record.id, text: $0) }
        )
    }

    private var improvedBinding: Binding<String> {
        Binding(
            get: { store.records.first(where: { $0.id == record.id })?.improvedText ?? "" },
            set: { store.updateImprovedText(id: record.id, text: $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Timestamp
            Text(formatter.string(from: record.timestamp))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            // Raw text
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Transcript")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    Button(action: { copyText(rawBinding.wrappedValue) }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }

                TextEditor(text: rawBinding)
                    .font(.system(size: 13))
                    .frame(minHeight: 40, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
            }

            // Improved text or Improve button
            if record.improvedText != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Improved")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                        Button(action: { copyText(improvedBinding.wrappedValue) }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }

                    TextEditor(text: improvedBinding)
                        .font(.system(size: 13))
                        .frame(minHeight: 40, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                }
            } else if record.isImproving {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Improving...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            } else {
                Button(action: { store.improveTranscript(id: record.id) }) {
                    Text("Improve")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(10)
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
