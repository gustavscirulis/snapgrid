import SwiftUI
import SwiftData

struct SpacesSettingsTab: View {
    @Query(sort: \Space.order) private var spaces: [Space]
    @Environment(\.modelContext) private var modelContext
    @State private var newSpaceName: String = ""
    @State private var selectedSpaceId: String? = nil

    // Global "All" space prompt
    @AppStorage("allSpacePrompt") private var allSpacePrompt: String = ""
    @AppStorage("useAllSpacePrompt") private var useAllSpacePrompt: Bool = false

    /// Currently viewed space (nil = "All")
    private var selectedSpace: Space? {
        guard let id = selectedSpaceId else { return nil }
        return spaces.first(where: { $0.id == id })
    }

    var body: some View {
        HSplitView {
            // Left: space list
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $selectedSpaceId) {
                    // "All" item
                    Button {
                        selectedSpaceId = nil
                    } label: {
                        HStack {
                            Text("All")
                                .fontWeight(selectedSpaceId == nil ? .semibold : .regular)
                            Spacer()
                            if useAllSpacePrompt {
                                Text("custom")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.snapAccent.opacity(0.8))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selectedSpaceId == nil ? Color.accentColor.opacity(0.15) : Color.clear)

                    ForEach(spaces) { space in
                        Button {
                            selectedSpaceId = space.id
                        } label: {
                            HStack {
                                Text(space.name)
                                    .fontWeight(selectedSpaceId == space.id ? .semibold : .regular)
                                Spacer()
                                if space.useCustomPrompt {
                                    Text("custom")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.snapAccent.opacity(0.8))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selectedSpaceId == space.id ? Color.accentColor.opacity(0.15) : Color.clear)
                    }
                }
                .listStyle(.sidebar)

                // Add space
                HStack {
                    TextField("New space", text: $newSpaceName)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        guard !newSpaceName.isEmpty else { return }
                        let space = Space(name: newSpaceName, order: spaces.count)
                        modelContext.insert(space)
                        try? modelContext.save()
                        newSpaceName = ""
                        selectedSpaceId = space.id
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(newSpaceName.isEmpty)
                }
                .padding(8)
            }
            .frame(minWidth: 160, maxWidth: 200)

            // Right: space detail
            Form {
                if let space = selectedSpace {
                    // Individual space settings
                    Section("Space: \(space.name)") {
                        TextField("Name", text: Binding(
                            get: { space.name },
                            set: {
                                space.name = $0
                                try? modelContext.save()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    Section("Custom Instructions") {
                        Toggle("Use custom prompt for this space", isOn: Binding(
                            get: { space.useCustomPrompt },
                            set: {
                                space.useCustomPrompt = $0
                                try? modelContext.save()
                            }
                        ))

                        if space.useCustomPrompt {
                            TextEditor(text: Binding(
                                get: { space.customPrompt ?? "" },
                                set: {
                                    space.customPrompt = $0
                                    try? modelContext.save()
                                }
                            ))
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.snapBorder, lineWidth: 1)
                            )
                        } else {
                            Text("Using the built-in default prompt.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        Button("Delete Space", role: .destructive) {
                            modelContext.delete(space)
                            try? modelContext.save()
                            selectedSpaceId = nil
                        }
                    }
                } else {
                    // "All" space settings
                    Section("Default Analysis Prompt") {
                        Toggle("Use custom prompt for all items", isOn: $useAllSpacePrompt)

                        if useAllSpacePrompt {
                            TextEditor(text: $allSpacePrompt)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(minHeight: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.snapBorder, lineWidth: 1)
                                )
                        } else {
                            Text("Using the built-in default prompt.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 280)
        }
    }
}
