import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case dark, light, auto

    var label: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .auto: "Auto"
        }
    }

    var icon: String {
        switch self {
        case .dark: "moon.fill"
        case .light: "sun.max.fill"
        case .auto: "circle.lefthalf.filled"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .auto: nil
        }
    }
}

struct GeneralSettingsTab: View {
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.dark.rawValue
    @AppStorage("aiProvider") private var selectedProvider: String = AIProvider.openai.rawValue
    @AppStorage("openaiModel") private var openaiModel: String = ModelDiscoveryService.autoModelValue
    @AppStorage("anthropicModel") private var anthropicModel: String = ModelDiscoveryService.autoModelValue
    @AppStorage("geminiModel") private var geminiModel: String = ModelDiscoveryService.autoModelValue
    @AppStorage("openrouterModel") private var openrouterModel: String = "openai/gpt-4o"

    @State private var apiKeyInput: String = ""
    @State private var hasKey: Bool = false
    @State private var saveError: String?
    @State private var keyWarning: String?
    @State private var discoveredModels: [DiscoveredModel] = []
    @State private var isLoadingModels = false

    private var provider: AIProvider {
        AIProvider(rawValue: selectedProvider) ?? .openai
    }

    private var keyPlaceholder: String {
        switch provider {
        case .openai: return "sk-..."
        case .anthropic: return "sk-ant-..."
        case .gemini: return "AIza..."
        case .openrouter: return "sk-or-..."
        }
    }

    private var keyGenerationURL: URL {
        switch provider {
        case .openai: return URL(string: "https://platform.openai.com/api-keys")!
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")!
        case .openrouter: return URL(string: "https://openrouter.ai/keys")!
        }
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Mode", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Label(mode.label, systemImage: mode.icon)
                            .tag(mode.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }

            Section("AI Analysis") {
                Picker("Provider", selection: $selectedProvider) {
                    ForEach(AIProvider.allCases, id: \.rawValue) { p in
                        Text(p.displayName).tag(p.rawValue)
                    }
                }

                if hasKey {
                    LabeledContent("API Key") {
                        Button("Remove", role: .destructive) {
                            try? KeychainService.delete(service: provider.keychainService)
                            hasKey = false
                            apiKeyInput = ""
                            discoveredModels = []
                            KeySyncService.syncToiCloud()
                        }
                    }
                } else {
                    HStack {
                        SecureField("API Key", text: $apiKeyInput, prompt: Text(keyPlaceholder))
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            saveApiKey()
                        }
                        .disabled(apiKeyInput.isEmpty)
                    }

                    Link("Get \(provider.displayName) API key", destination: keyGenerationURL)
                        .font(.caption)
                }

                if let keyWarning {
                    Text(keyWarning)
                        .font(.caption)
                        .foregroundStyle(.orange)
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
            KeySyncService.syncToiCloud()
        }
        .onChange(of: openaiModel) { KeySyncService.syncToiCloud() }
        .onChange(of: anthropicModel) { KeySyncService.syncToiCloud() }
        .onChange(of: geminiModel) { KeySyncService.syncToiCloud() }
        .onChange(of: openrouterModel) { KeySyncService.syncToiCloud() }
    }

    // MARK: - Model Picker

    @ViewBuilder
    private var modelPicker: some View {
        let binding = modelBinding(for: provider)

        if !hasKey {
            Text("Add an API key to choose a model.")
                .foregroundStyle(.secondary)
        } else if isLoadingModels {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Loading models…")
                    .foregroundStyle(.secondary)
            }
        } else if !discoveredModels.isEmpty {
            Picker("Model", selection: binding) {
                if provider != .openrouter {
                    Text("Use latest (\(discoveredModels.first?.id ?? "…"))")
                        .tag(ModelDiscoveryService.autoModelValue)
                }
                Divider()
                ForEach(discoveredModels) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
        } else {
            TextField("Model ID", text: binding)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Helpers

    private func modelBinding(for provider: AIProvider) -> Binding<String> {
        switch provider {
        case .openai: return $openaiModel
        case .anthropic: return $anthropicModel
        case .gemini: return $geminiModel
        case .openrouter: return $openrouterModel
        }
    }

    private func saveApiKey() {
        guard !apiKeyInput.isEmpty else { return }
        keyWarning = validateKeyPrefix(apiKeyInput, provider: provider)
        do {
            try KeychainService.set(key: apiKeyInput, forService: provider.keychainService)
            hasKey = true
            apiKeyInput = ""
            saveError = nil
            ModelDiscoveryService.shared.clearCache(for: provider)
            Task { await loadModels() }
            NotificationCenter.default.post(name: .apiKeySaved, object: nil)
            KeySyncService.syncToiCloud()
        } catch {
            saveError = error.localizedDescription
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
