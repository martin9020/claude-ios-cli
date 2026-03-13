import SwiftUI
import SafariServices

struct SettingsView: View {
    @AppStorage("anthropic_api_key") private var apiKey = ""
    @AppStorage("font_size") private var fontSize = 13.0
    @AppStorage("model_id") private var modelId = "claude-sonnet-4-20250514"
    @Environment(\.dismiss) private var dismiss
    @State private var showSafari = false
    @State private var pasteMessage = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Claude API")) {
                    // API Key status
                    HStack {
                        Image(systemName: apiKey.isEmpty ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundColor(apiKey.isEmpty ? .red : .green)
                        Text(apiKey.isEmpty ? "No API key configured" : "API key configured")
                            .foregroundColor(apiKey.isEmpty ? .red : .green)
                    }

                    SecureField("API Key (sk-ant-...)", text: $apiKey)
                        .font(.system(.body, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    // Paste from clipboard button
                    Button(action: pasteFromClipboard) {
                        HStack {
                            Image(systemName: "doc.on.clipboard")
                            Text("Paste API Key from Clipboard")
                        }
                    }

                    if !pasteMessage.isEmpty {
                        Text(pasteMessage)
                            .font(.caption)
                            .foregroundColor(pasteMessage.contains("Error") ? .red : .green)
                    }

                    // Get API key button — opens Anthropic console in-app
                    Button(action: { showSafari = true }) {
                        HStack {
                            Image(systemName: "safari")
                            Text("Get API Key from Anthropic")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Picker("Model", selection: $modelId) {
                        Text("Claude Sonnet 4.6").tag("claude-sonnet-4-6")
                        Text("Claude Haiku 4.5").tag("claude-haiku-4-5-20251001")
                        Text("Claude Opus 4.6").tag("claude-opus-4-6")
                    }

                    // Clear key
                    if !apiKey.isEmpty {
                        Button(action: {
                            apiKey = ""
                            pasteMessage = ""
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Remove API Key")
                            }
                            .foregroundColor(.red)
                        }
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

                Section(header: Text("How to get your API key")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("1. Tap \"Get API Key\" above", systemImage: "1.circle")
                        Label("2. Sign in to Anthropic", systemImage: "2.circle")
                        Label("3. Go to API Keys", systemImage: "3.circle")
                        Label("4. Create a new key & copy it", systemImage: "4.circle")
                        Label("5. Come back & tap \"Paste\"", systemImage: "5.circle")
                    }
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
            .sheet(isPresented: $showSafari) {
                SafariView(url: URL(string: "https://console.anthropic.com/settings/keys")!)
            }
        }
    }

    private func pasteFromClipboard() {
        if let clipboard = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if clipboard.hasPrefix("sk-ant-") {
                apiKey = clipboard
                pasteMessage = "API key pasted successfully!"
            } else if clipboard.isEmpty {
                pasteMessage = "Error: Clipboard is empty"
            } else {
                pasteMessage = "Error: Doesn't look like an API key (should start with sk-ant-)"
            }
        } else {
            pasteMessage = "Error: Nothing in clipboard"
        }
    }
}

/// Wrapper for SFSafariViewController to use in SwiftUI
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = .systemPurple
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
