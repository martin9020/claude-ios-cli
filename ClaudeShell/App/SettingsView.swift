import SwiftUI

struct SettingsView: View {
    @AppStorage("anthropic_api_key") private var apiKey = ""
    @AppStorage("font_size") private var fontSize = 13.0
    @AppStorage("model_id") private var modelId = "claude-sonnet-4-20250514"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Claude API")) {
                    SecureField("API Key (sk-ant-...)", text: $apiKey)
                        .font(.system(.body, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    Picker("Model", selection: $modelId) {
                        Text("Claude Opus 4.6").tag("claude-opus-4-6")
                        Text("Claude Sonnet 4.6").tag("claude-sonnet-4-6")
                        Text("Claude Haiku 4.5").tag("claude-haiku-4-5-20251001")
                    }
                }

                Section(header: Text("Terminal")) {
                    HStack {
                        Text("Font Size")
                        Slider(value: $fontSize, in: 10...20, step: 1)
                        Text("\(Int(fontSize))pt")
                            .font(.system(.caption, design: .monospaced))
                    }
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Shell")
                        Spacer()
                        Text("ClaudeShell (embedded POSIX)")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Sandbox")) {
                    Button("Show Sandbox Path") {
                        if let docs = FileManager.default.urls(
                            for: .documentDirectory, in: .userDomainMask).first {
                            UIPasteboard.general.string = docs.path
                        }
                    }
                    Text("Files are stored in the app's Documents directory.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
