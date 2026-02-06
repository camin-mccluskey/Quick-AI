import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var selectedModel: String = UserDefaults.standard.string(forKey: "selectedModel")
        ?? "google/gemini-2.0-flash-001"

    private let models = [
        ("google/gemini-2.0-flash-001", "Gemini 2.0 Flash"),
        ("google/gemini-2.5-flash", "Gemini 2.5 Flash"),
        ("anthropic/claude-3.5-sonnet", "Claude 3.5 Sonnet"),
        ("openai/gpt-4o-mini", "GPT-4o Mini"),
    ]

    var body: some View {
        Form {
            Section("OpenRouter API") {
                SecureField("API Key", text: $apiKey)
                    .onAppear {
                        apiKey = KeychainManager.load(key: "openrouter-api-key") ?? ""
                    }
                    .onChange(of: apiKey) {
                        if apiKey.isEmpty {
                            KeychainManager.delete(key: "openrouter-api-key")
                        } else {
                            KeychainManager.save(key: "openrouter-api-key", value: apiKey)
                        }
                    }

                Text("Get a key at [openrouter.ai](https://openrouter.ai/keys)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Model") {
                Picker("Model", selection: $selectedModel) {
                    ForEach(models, id: \.0) { id, name in
                        Text(name).tag(id)
                    }
                }
                .onChange(of: selectedModel) {
                    UserDefaults.standard.set(selectedModel, forKey: "selectedModel")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 220)
    }
}
