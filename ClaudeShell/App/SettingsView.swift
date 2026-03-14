import SwiftUI
import SafariServices

struct SettingsView: View {
    @AppStorage("anthropic_api_key") private var apiKey = ""
    @AppStorage("font_size") private var fontSize = 13.0
    @AppStorage("model_id") private var modelId = "claude-sonnet-4-20250514"
    @Environment(\.dismiss) private var dismiss
    @StateObject private var oauthManager = OAuthManager.shared
    @State private var showSafari = false
    @State private var pasteMessage = ""
    @State private var isInstallingClaudeCode = false
    @State private var installOutput = ""

    var body: some View {
        NavigationView {
            Form {
                // MARK: - Claude Pro/Max Section (Primary)
                Section(header: Text("Claude Pro / Max")) {
                    // Sign-in status
                    HStack {
                        Image(systemName: oauthManager.isSignedIn ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(oauthManager.isSignedIn ? .green : .gray)
                        Text(oauthManager.isSignedIn ? "Signed in with Claude Pro" : "Not signed in")
                            .foregroundColor(oauthManager.isSignedIn ? .green : .secondary)
                    }

                    if !oauthManager.statusMessage.isEmpty {
                        Text(oauthManager.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if oauthManager.isSignedIn {
                        // Sign out button
                        Button(action: { oauthManager.signOut() }) {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Sign Out")
                            }
                            .foregroundColor(.red)
                        }
                    } else {
                        // Install Claude Code package (prerequisite)
                        if !NpmManager.shared.isClaudeCodeInstalled {
                            Button(action: installClaudeCodePackage) {
                                HStack {
                                    if isInstallingClaudeCode {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "arrow.down.circle")
                                    }
                                    Text(isInstallingClaudeCode ? "Installing..." : "Install Claude Code Package")
                                }
                            }
                            .disabled(isInstallingClaudeCode)

                            if !installOutput.isEmpty {
                                Text(installOutput)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                        } else {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                    .foregroundColor(.green)
                                Text("Claude Code package installed")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }

                        // Sign in button
                        Button(action: { oauthManager.startOAuthFlow() }) {
                            HStack {
                                if oauthManager.isLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "person.crop.circle.badge.checkmark")
                                }
                                Text("Sign in with Claude Pro/Max")
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(oauthManager.isLoading)
                    }
                }

                // MARK: - API Key Section (Alternative)
                Section(header: Text("Alternative: API Key")) {
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
                    HStack {
                        Text("Auth")
                        Spacer()
                        Text(oauthManager.isSignedIn ? "OAuth (Pro/Max)" :
                             (apiKey.isEmpty ? "Not configured" : "API Key"))
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("How to use")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Option A: Sign in with Pro/Max subscription", systemImage: "a.circle")
                            .fontWeight(.medium)
                        Label("  1. Install Claude Code package", systemImage: "1.circle")
                        Label("  2. Tap Sign in with Claude Pro/Max", systemImage: "2.circle")
                        Label("  3. Log into your Anthropic account", systemImage: "3.circle")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Option B: Use API key (prepaid credits)", systemImage: "b.circle")
                            .fontWeight(.medium)
                        Label("  1. Get an API key from Anthropic", systemImage: "1.circle")
                        Label("  2. Paste it in the field above", systemImage: "2.circle")
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

    private func installClaudeCodePackage() {
        isInstallingClaudeCode = true
        installOutput = "Starting installation..."

        DispatchQueue.global(qos: .userInitiated).async {
            let result = NpmManager.shared.installClaudeCode { line in
                DispatchQueue.main.async {
                    self.installOutput = line.trimmingCharacters(in: .newlines)
                }
            }

            DispatchQueue.main.async {
                self.isInstallingClaudeCode = false
                if result == 0 {
                    self.installOutput = "Claude Code package installed successfully!"
                } else {
                    self.installOutput = "Installation failed. Check your network and try again."
                }
            }
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
