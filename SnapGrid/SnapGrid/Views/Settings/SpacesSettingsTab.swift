import SwiftUI
import SwiftData

struct SpacesSettingsTab: View {
    @Query(sort: \Space.order) private var spaces: [Space]
    @Environment(\.modelContext) private var modelContext
    @State private var newSpaceName: String = ""

    var body: some View {
        Form {
            Section("Spaces") {
                if spaces.isEmpty {
                    Text("No spaces created yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(spaces) { space in
                        SpaceRow(space: space, onDelete: {
                            modelContext.delete(space)
                            try? modelContext.save()
                        })
                    }
                }

                HStack {
                    TextField("New space name", text: $newSpaceName)
                        .textFieldStyle(.roundedBorder)
                    Button("Create") {
                        guard !newSpaceName.isEmpty else { return }
                        let space = Space(name: newSpaceName, order: spaces.count)
                        modelContext.insert(space)
                        try? modelContext.save()
                        newSpaceName = ""
                    }
                    .disabled(newSpaceName.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct SpaceRow: View {
    @Bindable var space: Space
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Name", text: $space.name)
                    .textFieldStyle(.roundedBorder)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            Toggle("Use custom prompt", isOn: $space.useCustomPrompt)

            if space.useCustomPrompt {
                TextEditor(text: Binding(
                    get: { space.customPrompt ?? "" },
                    set: { space.customPrompt = $0 }
                ))
                .font(.system(size: 12))
                .frame(height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.snapBorder, lineWidth: 1)
                )
            }
        }
        .padding(.vertical, 4)
    }
}
