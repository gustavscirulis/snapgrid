import SwiftUI

struct GeneralSettingsTab: View {
    @AppStorage("aiProvider") private var selectedProvider: String = AIProvider.openai.rawValue
    @AppStorage("openaiModel") private var openaiModel: String = ModelDiscoveryService.autoModelValue
    @AppStorage("anthropicModel") private var anthropicModel: String = ModelDiscoveryService.autoModelValue
    @AppStorage("geminiModel") private var geminiModel: String = ModelDiscoveryService.autoModelValue
    @AppStorage("openrouterModel") private var openrouterModel: String = "openai/gpt-4o"
    @AppStorage("appTheme") private var themeSetting: String = AppTheme.system.rawValue

    @State private var apiKeyInput: String = ""
    @State private var hasKey: Bool = false
    @State private var showApiKey: Bool = false
    @State private var showSaved: Bool = false
    @State private var saveError: String?
    @State private var keyWarning: String?
    @State private var discoveredModels: [DiscoveredModel] = []
    @State private var isLoadingModels = false

    private var provider: AIProvider {
        AIProvider(rawValue: selectedProvider) ?? .openai
    }

    private var theme: AppTheme {
        AppTheme(rawValue: themeSetting) ?? .system
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $themeSetting) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { t in
                        Label(t.label, systemImage: t.icon).tag(t.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("AI Provider") {
                Picker("Provider", selection: $selectedProvider) {
                    ForEach(AIProvider.allCases, id: \.rawValue) { p in
                        Text(p.displayName).tag(p.rawValue)
                    }
                }

                HStack {
                    Group {
                        if showApiKey {
                            TextField("API Key", text: $apiKeyInput)
                        } else {
                            SecureField("API Key", text: $apiKeyInput)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Button {
                        showApiKey.toggle()
                    } label: {
                        Image(systemName: showApiKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    if hasKey {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Remove") {
                            try? KeychainService.delete(service: provider.keychainService)
                            hasKey = false
                            apiKeyInput = ""
                            discoveredModels = []
                        }
                    }

                    Button("Save") {
                        guard !apiKeyInput.isEmpty else { return }
                        // Prefix validation — SettingsPanel.tsx:335-364,405-409
                        keyWarning = validateKeyPrefix(apiKeyInput, provider: provider)
                        do {
                            try KeychainService.set(key: apiKeyInput, forService: provider.keychainService)
                            hasKey = true
                            apiKeyInput = ""
                            saveError = nil
                            showSaved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showSaved = false }
                            ModelDiscoveryService.shared.clearCache(for: provider)
                            Task { await loadModels() }
                            NotificationCenter.default.post(name: .apiKeySaved, object: nil)
                        } catch {
                            saveError = error.localizedDescription
                        }
                    }
                    .disabled(apiKeyInput.isEmpty)
                }

                if let keyWarning {
                    Text(keyWarning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if showSaved {
                    Text("API key saved")
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


        }
        .formStyle(.grouped)
        .onAppear {
            checkForKey()
            Task { await loadModels() }
        }
        .onChange(of: selectedProvider) {
            checkForKey()
            discoveredModels = []
            Task { await loadModels() }
        }
    }

    @ViewBuilder
    private var modelPicker: some View {
        let binding = modelBinding(for: provider)

        if isLoadingModels {
            HStack {
                Text("Model")
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("Loading...")
                    .foregroundStyle(.secondary)
            }
        } else if !discoveredModels.isEmpty {
            Picker("Model", selection: binding) {
                if provider != .openrouter {
                    Text("Use latest (\(discoveredModels.first?.id ?? "..."))")
                        .tag(ModelDiscoveryService.autoModelValue)
                }
                Divider()
                ForEach(discoveredModels) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
        } else {
            // Fallback: manual text field when no models loaded
            TextField("Model", text: binding)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func modelBinding(for provider: AIProvider) -> Binding<String> {
        switch provider {
        case .openai: return $openaiModel
        case .anthropic: return $anthropicModel
        case .gemini: return $geminiModel
        case .openrouter: return $openrouterModel
        }
    }

    private func loadModels() async {
        guard hasKey else { return }
        isLoadingModels = true
        defer { isLoadingModels = false }

        do {
            discoveredModels = try await ModelDiscoveryService.shared.fetchModels(for: provider)
        } catch {
            discoveredModels = []
        }
    }

    private func checkForKey() {
        hasKey = KeychainService.exists(service: provider.keychainService)
    }

    /// Prefix validation per SettingsPanel.tsx:335-364
    private func validateKeyPrefix(_ key: String, provider: AIProvider) -> String? {
        switch provider {
        case .openai where !key.hasPrefix("sk-"):
            return "OpenAI keys typically start with \"sk-\""
        case .anthropic where !key.hasPrefix("sk-ant-"):
            return "Anthropic keys typically start with \"sk-ant-\""
        case .gemini where !key.hasPrefix("AIza"):
            return "Gemini keys typically start with \"AIza\""
        case .openrouter where !key.hasPrefix("sk-or-"):
            return "OpenRouter keys typically start with \"sk-or-\""
        default:
            return nil
        }
    }
}
