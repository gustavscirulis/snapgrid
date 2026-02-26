import SwiftUI

struct GeneralSettingsTab: View {
    @AppStorage("aiProvider") private var selectedProvider: String = AIProvider.openai.rawValue
    @AppStorage("openaiModel") private var openaiModel: String = "gpt-4o"
    @AppStorage("anthropicModel") private var anthropicModel: String = "claude-sonnet-4-20250514"
    @AppStorage("geminiModel") private var geminiModel: String = "gemini-2.0-flash"
    @AppStorage("openrouterModel") private var openrouterModel: String = "openai/gpt-4o"

    @State private var apiKeyInput: String = ""
    @State private var hasKey: Bool = false
    @State private var showSaved: Bool = false
    @State private var saveError: String?

    private var provider: AIProvider {
        AIProvider(rawValue: selectedProvider) ?? .openai
    }

    var body: some View {
        Form {
            Section("AI Provider") {
                Picker("Provider", selection: $selectedProvider) {
                    ForEach(AIProvider.allCases, id: \.rawValue) { p in
                        Text(p.displayName).tag(p.rawValue)
                    }
                }

                HStack {
                    SecureField("API Key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)

                    if hasKey {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Remove") {
                            try? KeychainService.delete(service: provider.keychainService)
                            hasKey = false
                            apiKeyInput = ""
                        }
                    }

                    Button("Save") {
                        guard !apiKeyInput.isEmpty else { return }
                        do {
                            try KeychainService.set(key: apiKeyInput, forService: provider.keychainService)
                            hasKey = true
                            apiKeyInput = ""
                            saveError = nil
                            showSaved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showSaved = false }
                        } catch {
                            saveError = error.localizedDescription
                        }
                    }
                    .disabled(apiKeyInput.isEmpty)
                }

                if showSaved {
                    Text("API key saved to Keychain")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if let saveError {
                    Text(saveError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                modelPicker
            }

            Section("Appearance") {
                Text("Theme follows system appearance")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { checkForKey() }
        .onChange(of: selectedProvider) { checkForKey() }
    }

    @ViewBuilder
    private var modelPicker: some View {
        switch provider {
        case .openai:
            TextField("Model", text: $openaiModel)
                .textFieldStyle(.roundedBorder)
        case .anthropic:
            TextField("Model", text: $anthropicModel)
                .textFieldStyle(.roundedBorder)
        case .gemini:
            TextField("Model", text: $geminiModel)
                .textFieldStyle(.roundedBorder)
        case .openrouter:
            TextField("Model", text: $openrouterModel)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func checkForKey() {
        hasKey = KeychainService.exists(service: provider.keychainService)
    }
}
