import SwiftUI
import ServiceManagement

struct HistoryView: View {
    @ObservedObject var store: TranscriptStore
    @ObservedObject var languageSettings: LanguageSettings
    var onRecord: () -> Void
    var onStop: () -> Void
    @State private var selectedTab: Int

    init(store: TranscriptStore, languageSettings: LanguageSettings = .shared, onRecord: @escaping () -> Void, onStop: @escaping () -> Void, initialTab: Int = 0) {
        self.store = store
        self.languageSettings = languageSettings
        self.onRecord = onRecord
        self.onStop = onStop
        self._selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TranscriptsTab(store: store, languageSettings: languageSettings)
                .tabItem { Label("History", systemImage: "clock") }
                .tag(0)

            SettingsTab(languageSettings: languageSettings)
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
    @ObservedObject var languageSettings: LanguageSettings

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
                            TranscriptCard(record: record, store: store, languageSettings: languageSettings)
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
    @ObservedObject var languageSettings: LanguageSettings

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

                LanguagesSection(settings: languageSettings)
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

struct LanguagesSection: View {
    @ObservedObject var settings: LanguageSettings
    @State private var searchText = ""

    private var searchResults: [Language] {
        guard !searchText.isEmpty else { return [] }
        return LanguageSettings.allLanguages.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) &&
            !settings.selectedLanguages.contains($0.name)
        }
    }

    var body: some View {
        Section("Translation Languages") {
            LabeledContent {} label: {
                VStack(alignment: .leading, spacing: 10) {
                    // Selected languages as removable chips
                    if !settings.orderedSelectedLanguages.isEmpty {
                        WrappingHStack(items: settings.orderedSelectedLanguages) { lang in
                            Button(action: { settings.toggle(lang.name) }) {
                                HStack(spacing: 4) {
                                    Text("\(lang.flag) \(lang.name)")
                                        .font(.system(size: 11, weight: .medium))
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.accentColor.opacity(0.15))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Search field with proper placeholder
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        TextField(text: $searchText, prompt: Text("Add a language...").foregroundColor(Color(nsColor: .placeholderTextColor))) {
                            EmptyView()
                        }
                        .font(.system(size: 12))
                        .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.35))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )

                    // Search results dropdown
                    if !searchText.isEmpty {
                        if searchResults.isEmpty {
                            Text("No languages match \"\(searchText)\"")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.leading, 4)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(searchResults.prefix(6)) { lang in
                                    Button(action: {
                                        settings.toggle(lang.name)
                                        searchText = ""
                                    }) {
                                        HStack(spacing: 6) {
                                            Text(lang.flag)
                                                .font(.system(size: 14))
                                            Text(lang.name)
                                                .font(.system(size: 12))
                                            Spacer()
                                            Image(systemName: "plus")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(.accentColor)
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 8)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    if lang.id != searchResults.prefix(6).last?.id {
                                        Divider().padding(.leading, 30)
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct WrappingHStack<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content
    @State private var totalHeight: CGFloat = 0

    init(items: [Item], @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            generateContent(in: geometry)
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in geometry: GeometryProxy) -> some View {
        var width: CGFloat = 0
        var height: CGFloat = 0

        return ZStack(alignment: .topLeading) {
            ForEach(items) { item in
                content(item)
                    .padding(.trailing, 4)
                    .padding(.bottom, 4)
                    .alignmentGuide(.leading) { d in
                        if abs(width - d.width) > geometry.size.width {
                            width = 0
                            height -= d.height + 4
                        }
                        let result = width
                        if item == items.last {
                            width = 0
                        } else {
                            width -= d.width
                        }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item == items.last {
                            height = 0
                        }
                        return result
                    }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: HeightPreferenceKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(HeightPreferenceKey.self) { totalHeight = $0 }
    }
}

private struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct TranscriptCard: View {
    let record: TranscriptRecord
    @ObservedObject var store: TranscriptStore
    @ObservedObject var languageSettings: LanguageSettings
    @State private var copiedField: String?

    private var rawBinding: Binding<String> {
        Binding(
            get: { store.records.first(where: { $0.id == record.id })?.rawText ?? record.rawText },
            set: { store.updateRawText(id: record.id, text: $0) }
        )
    }

    private func chainBinding(entryId: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let rec = store.records.first(where: { $0.id == record.id }),
                      let entry = rec.chain.first(where: { $0.id == entryId }) else { return "" }
                return entry.text
            },
            set: { store.updateChainText(recordId: record.id, entryId: entryId, text: $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Raw transcript
            textBlock(label: "Transcript", text: rawBinding, copyValue: rawBinding.wrappedValue)

            // Chain of operations
            ForEach(record.chain) { entry in
                let binding = chainBinding(entryId: entry.id)
                textBlock(label: entry.label, text: binding, copyValue: binding.wrappedValue)
            }

            // Pending operation
            if let pending = record.pendingLabel {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(pending)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            }

            // Action buttons (always at the bottom, operate on latest text)
            if !record.isBusy {
                HStack(spacing: 8) {
                    Button(action: { store.improveText(id: record.id) }) {
                        Text("Improve")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: { store.summarize(id: record.id) }) {
                        Text("Summarize")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: { store.keyPoints(id: record.id) }) {
                        Text("Key Points")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: { store.answerQuestion(id: record.id) }) {
                        Text("Answer")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    ForEach(languageSettings.orderedSelectedLanguages) { lang in
                        Button(action: { store.translate(id: record.id, language: lang.name) }) {
                            Text("\(lang.flag) \(lang.name)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if let error = record.pendingError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .lineLimit(2)
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
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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

            if let cmd = dep.installCommand, isParent {
                HStack(spacing: 4) {
                    Text(cmd)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .textSelection(.enabled)

                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cmd, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    }) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(copied ? .green : Color(nsColor: .tertiaryLabelColor))
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: copied)
                }
                .padding(.leading, 18)
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
