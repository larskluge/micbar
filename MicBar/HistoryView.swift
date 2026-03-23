import SwiftUI
import ServiceManagement

struct HistoryView: View {
    @ObservedObject var store: TranscriptStore
    var onRecord: () -> Void
    var onStop: () -> Void
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TranscriptsTab(store: store)
                .tabItem { Label("History", systemImage: "clock") }
                .tag(0)

            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(1)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if selectedTab == 0 {
                HStack {
                    Spacer()
                    RecordingControls(state: store.recordingState, onRecord: onRecord, onStop: onStop)
                }
                .padding(.trailing, 12)
                .frame(height: 0)
                .offset(y: -24)
            }
        }
        .frame(minWidth: 600, idealWidth: 900, minHeight: 500, idealHeight: 700)
    }
}

struct TranscriptsTab: View {
    @ObservedObject var store: TranscriptStore

    private let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    var body: some View {
        if store.records.isEmpty {
            VStack {
                Spacer()
                Text("No transcripts yet")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.records) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(timestampFormatter.string(from: record.timestamp))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                .padding(.leading, 14)
                            TranscriptCard(record: record, store: store)
                        }
                    }
                }
                .padding(20)
            }
        }
    }
}

struct SettingsTab: View {
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @StateObject private var checker = DependencyChecker()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                DependenciesSection(checker: checker)

                Section("General") {
                    Toggle("Launch at Login", isOn: $loginEnabled)
                        .onChange(of: loginEnabled) { newValue in
                            toggleLogin(newValue)
                        }
                }
            }
            .formStyle(.grouped)

            Spacer()

            Button("Quit MicBar") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .font(.system(size: 12))
            .padding(.bottom, 20)
        }
        .onAppear { checker.checkAll() }
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
    @State private var copiedField: String?

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

    private var answerBinding: Binding<String> {
        Binding(
            get: { store.records.first(where: { $0.id == record.id })?.answerText ?? "" },
            set: { store.updateAnswerText(id: record.id, text: $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Raw text
            textBlock(label: "Transcript", text: rawBinding, copyValue: rawBinding.wrappedValue)

            // Improved text or Improve button
            if record.improvedText != nil {
                textBlock(label: "Improved", text: improvedBinding, copyValue: improvedBinding.wrappedValue)
                if record.rawEdited {
                    Button(action: { store.improveTranscript(id: record.id) }) {
                        Text("Re-improve")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
            }

            // Answer text or Answer button
            if record.answerText != nil {
                textBlock(label: "Answer", text: answerBinding, copyValue: answerBinding.wrappedValue)
            } else if record.isAnswering {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Answering...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            }

            // Action buttons row
            if !record.isImproving && !record.isAnswering {
                HStack(spacing: 8) {
                    if record.improvedText == nil {
                        Button(action: { store.improveTranscript(id: record.id) }) {
                            Text("Improve")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if record.answerText == nil {
                        Button(action: { store.answerQuestion(id: record.id) }) {
                            Text("Answer")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if let error = record.improveError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            .lineLimit(2)
                    }

                    if let error = record.answerError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func textBlock(label: String, text: Binding<String>, copyValue: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            HStack(alignment: .top, spacing: 8) {
                AutoExpandingTextEditor(text: text)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.15))
                    .cornerRadius(4)

                Button(action: { copyText(copyValue, field: label) }) {
                    Image(systemName: copiedField == label ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(copiedField == label ? .green : .secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .animation(.easeInOut(duration: 0.15), value: copiedField)
            }
        }
    }

    private func copyText(_ text: String, field: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedField = field
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedField == field { copiedField = nil }
        }
    }
}

struct DependenciesSection: View {
    @ObservedObject var checker: DependencyChecker

    var body: some View {
        Section {
            if checker.isChecking && checker.results.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(checker.results) { dep in
                    DependencyTree(dep: dep)
                }
            }
        } header: {
            HStack {
                Text("Dependencies")
                Spacer()
                if checker.isChecking && !checker.results.isEmpty {
                    ProgressView().controlSize(.mini)
                } else {
                    Button(action: { checker.checkAll() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct DependencyTree: View {
    let dep: DependencyStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Parent row
            DependencyRow(dep: dep, isParent: true)

            // Children
            if !dep.children.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(dep.children) { child in
                        HStack(spacing: 6) {
                            Text("\u{2514}")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Color(nsColor: .separatorColor))
                            DependencyRow(dep: child, isParent: false)
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
    }
}

struct DependencyRow: View {
    let dep: DependencyStatus
    let isParent: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundColor(dep.found ? .green : .red)
                .padding(.top, dep.description != nil && isParent ? -8 : 0)

            VStack(alignment: .leading, spacing: 1) {
                Text(dep.name)
                    .font(.system(size: isParent ? 13 : 12, weight: isParent ? .medium : .regular))
                    .foregroundColor(isParent ? .primary : .secondary)

                if let description = dep.description, isParent {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                }
            }

            if let path = dep.path {
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if let error = dep.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
        }
    }
}

struct RecordingControls: View {
    let state: RecordingState
    var onRecord: () -> Void
    var onStop: () -> Void

    var body: some View {
        switch state {
        case .idle:
            Button(action: onRecord) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.red))
                    .contentShape(Circle())
            }
            .buttonStyle(.borderless)

        case .waiting:
            ProgressView()
                .controlSize(.small)

        case .recording:
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.accentColor))
                    .contentShape(Circle())
            }
            .buttonStyle(.borderless)

        case .processing:
            ProgressView()
                .controlSize(.small)
        }
    }
}

struct AutoExpandingTextEditor: View {
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Hidden Text that sizes naturally to drive the container height
            Text(text.isEmpty ? " " : text)
                .font(.system(size: 13))
                .padding(.horizontal, 5)
                .padding(.vertical, 8)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(0)

            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
        }
        .frame(minHeight: 32)
    }
}
