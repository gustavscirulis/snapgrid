import SwiftUI
import SwiftData

struct GuidanceSettingsTab: View {
    @Query(sort: \Space.order) private var spaces: [Space]
    @Environment(\.modelContext) private var modelContext

    @AppStorage("allSpacePrompt") private var allSpaceGuidance: String = ""
    @AppStorage("useAllSpacePrompt") private var useAllSpaceGuidance: Bool = false

    @State private var editingTarget: GuidanceEditTarget?
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
            // MARK: - Default Guidance

            Section("Analysis Guidance") {
                Toggle("Use custom guidance", isOn: $useAllSpaceGuidance)
                    .onChange(of: useAllSpaceGuidance) { _, isOn in
                        if isOn && allSpaceGuidance.isEmpty {
                            allSpaceGuidance = AIAnalysisService.defaultGuidance
                        }
                        if !isOn {
                            allSpaceGuidance = ""
                        }
                        persistToSpacesJson()
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Text(useAllSpaceGuidance ? allSpaceGuidance : AIAnalysisService.defaultGuidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if useAllSpaceGuidance {
                        Button("Edit") {
                            editingTarget = .defaultGuidance(allSpaceGuidance)
                        }
                    }
                }
            }

            // MARK: - Space Overrides

            if !spaces.isEmpty {
                Section("Per-Space Guidance") {
                    Text("When set, replaces the default for that space.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    List(selection: $selectedOverrideId) {
                        ForEach(spacesWithOverrides) { space in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(space.name)
                                if let guidance = space.customPrompt, !guidance.isEmpty {
                                    Text(guidance)
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
                    .onDoubleClick(handler: {
                        guard let space = selectedSpace else { return }
                        editingTarget = .spaceGuidance(space.id, space.name, space.customPrompt ?? "")
                    })

                    HStack(spacing: 8) {
                        Menu("Add...") {
                            ForEach(availableSpaces) { space in
                                Button(space.name) {
                                    space.useCustomPrompt = true
                                    if space.customPrompt == nil { space.customPrompt = "" }
                                    try? modelContext.save()
                                    persistToSpacesJson()
                                    selectedOverrideId = space.id
                                    editingTarget = .spaceGuidance(space.id, space.name, "")
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
                            persistToSpacesJson()
                            selectedOverrideId = nil
                        }
                        .disabled(selectedSpace == nil)

                        Button("Edit") {
                            guard let space = selectedSpace else { return }
                            editingTarget = .spaceGuidance(space.id, space.name, space.customPrompt ?? "")
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
        .sheet(item: $editingTarget) { target in
            GuidanceEditorSheet(target: target) { newText in
                applyEdit(target: target, text: newText)
            }
        }
    }

    // MARK: - Apply Edit

    private func applyEdit(target: GuidanceEditTarget, text: String) {
        switch target {
        case .defaultGuidance:
            allSpaceGuidance = text
            useAllSpaceGuidance = !text.isEmpty
            persistToSpacesJson()
        case .spaceGuidance(let spaceId, _, _):
            guard let space = spaces.first(where: { $0.id == spaceId }) else { return }
            space.customPrompt = text
            space.useCustomPrompt = !text.isEmpty
            try? modelContext.save()
            persistToSpacesJson()
        }
    }

    /// Write current spaces + all-space guidance to spaces.json so iOS picks up changes via iCloud.
    private func persistToSpacesJson() {
        MetadataSidecarService.shared.writeSpaces(Array(spaces))
    }
}

// MARK: - Edit Target

private enum GuidanceEditTarget: Identifiable {
    case defaultGuidance(String)
    case spaceGuidance(String, String, String) // id, name, text

    var id: String {
        switch self {
        case .defaultGuidance: return "default"
        case .spaceGuidance(let spaceId, _, _): return spaceId
        }
    }

    var title: String {
        switch self {
        case .defaultGuidance: return "Default Guidance"
        case .spaceGuidance(_, let name, _): return name
        }
    }

    var text: String {
        switch self {
        case .defaultGuidance(let text): return text
        case .spaceGuidance(_, _, let text): return text
        }
    }
}

// MARK: - NSTextView wrapper (TextEditor in sheets breaks Cmd+C/V)

private struct NativeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: NSFont

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.font = font
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.delegate = context.coordinator
        textView.string = text
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        // Add placeholder label
        let label = NSTextField(labelWithString: placeholder)
        label.font = font
        label.textColor = .tertiaryLabelColor
        label.tag = 999
        label.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: textView.topAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 12),
        ])
        label.isHidden = !text.isEmpty

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
        textView.subviews.first(where: { $0.tag == 999 })?.isHidden = !text.isEmpty

        // Make text view first responder so Edit menu (Cmd+C/V/X) works
        if !context.coordinator.hasFocused, let window = textView.window {
            window.makeFirstResponder(textView)
            context.coordinator.hasFocused = true
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: NativeTextEditor
        var hasFocused = false
        init(_ parent: NativeTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

// MARK: - Guidance Editor Sheet

private struct GuidanceEditorSheet: View {
    let target: GuidanceEditTarget
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String

    init(target: GuidanceEditTarget, onSave: @escaping (String) -> Void) {
        self.target = target
        self.onSave = onSave
        self._draft = State(initialValue: target.text)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Guidance — \(target.title)")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            NativeTextEditor(
                text: $draft,
                placeholder: "e.g., Focus on typography, color palettes, and layout patterns",
                font: .monospacedSystemFont(ofSize: 11, weight: .regular)
            )

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
