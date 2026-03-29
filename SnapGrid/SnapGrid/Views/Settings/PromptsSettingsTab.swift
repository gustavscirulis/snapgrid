import SwiftUI
import SwiftData

struct PromptsSettingsTab: View {
    @Query(sort: \Space.order) private var spaces: [Space]
    @Environment(\.modelContext) private var modelContext

    @AppStorage("allSpacePrompt") private var allSpacePrompt: String = ""
    @AppStorage("useAllSpacePrompt") private var useAllSpacePrompt: Bool = false

    @State private var editingPrompt: PromptEditTarget?
    @State private var selectedOverrideId: String?

    private var spacesWithOverrides: [Space] {
        spaces.filter { $0.useCustomPrompt }
    }

    private var availableSpaces: [Space] {
        spaces.filter { !$0.useCustomPrompt }
    }

    private var selectedSpace: Space? {
        guard let id = selectedOverrideId else { return nil }
        return spacesWithOverrides.first { $0.id == id }
    }

    var body: some View {
        Form {
            // MARK: - Default Prompt

            Section("Default Prompt") {
                Toggle("Override default prompt", isOn: $useAllSpacePrompt)
                    .onChange(of: useAllSpacePrompt) { _, isOn in
                        if isOn && allSpacePrompt.isEmpty {
                            allSpacePrompt = AIAnalysisService.defaultPromptDescription
                        }
                        if !isOn {
                            allSpacePrompt = ""
                        }
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Text(useAllSpacePrompt ? allSpacePrompt : AIAnalysisService.defaultPromptDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if useAllSpacePrompt {
                        Button("Edit") {
                            editingPrompt = .defaultPrompt(allSpacePrompt)
                        }
                    }
                }
            }

            // MARK: - Space Overrides

            if !spaces.isEmpty {
                Section("Space Overrides") {
                    Text("Additional instructions appended to the default prompt for specific spaces.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    List(selection: $selectedOverrideId) {
                        ForEach(spacesWithOverrides) { space in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(space.name)
                                if let prompt = space.customPrompt, !prompt.isEmpty {
                                    Text(prompt)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .tag(space.id)
                        }
                    }
                    .listStyle(.bordered)
                    .frame(height: max(72, CGFloat(spacesWithOverrides.count) * 40))

                    HStack(spacing: 8) {
                        Menu("Add...") {
                            ForEach(availableSpaces) { space in
                                Button(space.name) {
                                    space.useCustomPrompt = true
                                    if space.customPrompt == nil { space.customPrompt = "" }
                                    try? modelContext.save()
                                    selectedOverrideId = space.id
                                    editingPrompt = .spacePrompt(space.id, space.name, "")
                                }
                            }
                        }
                        .menuIndicator(.hidden)
                        .disabled(availableSpaces.isEmpty)

                        Button("Remove") {
                            guard let space = selectedSpace else { return }
                            space.customPrompt = ""
                            space.useCustomPrompt = false
                            try? modelContext.save()
                            selectedOverrideId = nil
                        }
                        .disabled(selectedSpace == nil)

                        Button("Edit") {
                            guard let space = selectedSpace else { return }
                            editingPrompt = .spacePrompt(space.id, space.name, space.customPrompt ?? "")
                        }
                        .disabled(selectedSpace == nil)

                        Spacer()
                    }
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .textSelection(.enabled)
        .sheet(item: $editingPrompt) { target in
            PromptEditorSheet(target: target) { newText in
                applyEdit(target: target, text: newText)
            }
        }
    }

    // MARK: - Apply Edit

    private func applyEdit(target: PromptEditTarget, text: String) {
        switch target {
        case .defaultPrompt:
            allSpacePrompt = text
            useAllSpacePrompt = !text.isEmpty
        case .spacePrompt(let spaceId, _, _):
            guard let space = spaces.first(where: { $0.id == spaceId }) else { return }
            space.customPrompt = text
            space.useCustomPrompt = !text.isEmpty
            try? modelContext.save()
        }
    }
}

// MARK: - Edit Target

private enum PromptEditTarget: Identifiable {
    case defaultPrompt(String)
    case spacePrompt(String, String, String) // id, name, text

    var id: String {
        switch self {
        case .defaultPrompt: return "default"
        case .spacePrompt(let spaceId, _, _): return spaceId
        }
    }

    var title: String {
        switch self {
        case .defaultPrompt: return "Default Prompt"
        case .spacePrompt(_, let name, _): return name
        }
    }

    var text: String {
        switch self {
        case .defaultPrompt(let text): return text
        case .spacePrompt(_, _, let text): return text
        }
    }
}

// MARK: - Prompt Editor Sheet

private struct PromptEditorSheet: View {
    let target: PromptEditTarget
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String

    init(target: PromptEditTarget, onSave: @escaping (String) -> Void) {
        self.target = target
        self.onSave = onSave
        self._draft = State(initialValue: target.text)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Prompt — \(target.title)")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            TextEditor(text: $draft)
                .font(.caption.monospaced())
                .scrollContentBackground(.hidden)
                .padding(12)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480, height: 360)
    }
}
