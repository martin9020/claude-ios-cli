import SwiftUI

struct TerminalView: View {
    @StateObject private var shell = ShellBridge()
    @StateObject private var shellTerminal = TerminalEmulator()
    @StateObject private var claudeTerminal = TerminalEmulator()
    @State private var activeTab = 0  // 0 = shell, 1 = claude
    @State private var inputText = ""
    @State private var commandHistory: [String] = []
    @State private var historyIndex = -1
    @State private var showSettings = false
    @AppStorage("anthropic_api_key") private var savedApiKey = ""
    @FocusState private var inputFocused: Bool

    private let monoFont = Font.system(size: 13, design: .monospaced)
    private let promptColor = Color.green
    private let claudePromptColor = Color.purple
    private let outputColor = Color.white
    private let errorColor = Color.red
    private let systemColor = Color.cyan
    private let toolColor = Color.orange
    private let bgColor = Color(red: 0.05, green: 0.05, blue: 0.1)

    /// The active terminal emulator for the current tab
    private var terminal: TerminalEmulator {
        activeTab == 0 ? shellTerminal : claudeTerminal
    }

    var body: some View {
        VStack(spacing: 0) {
            // Status bar with tabs
            HStack(spacing: 0) {
                // Tab buttons
                tabButton("Shell", tab: 0, icon: "terminal.fill", color: .green)
                tabButton("Claude", tab: 1, icon: "brain", color: .purple)

                Spacer()

                Text(shell.currentDirectory)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .frame(maxWidth: 120)

                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 15))
                }
                .padding(.trailing, 12)
            }
            .background(Color(red: 0.1, green: 0.1, blue: 0.15))

            // Terminal output — shows active tab's terminal
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(terminal.lines) { line in
                            terminalLine(line)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .onChange(of: terminal.lines.count) { _ in
                    if let lastLine = terminal.lines.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(lastLine.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(bgColor)
            .onTapGesture {
                inputFocused = true
            }

            // Input bar
            HStack(spacing: 8) {
                Text(promptString)
                    .font(monoFont)
                    .foregroundColor(activeTab == 1 ? claudePromptColor : promptColor)
                    .fixedSize()

                TextField("", text: $inputText)
                    .font(monoFont)
                    .foregroundColor(.white)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .focused($inputFocused)
                    .onSubmit {
                        executeCommand()
                    }

                HStack(spacing: 12) {
                    Button(action: { insertText("\t") }) {
                        Image(systemName: "arrow.right.to.line")
                            .foregroundColor(.gray)
                    }
                    Button(action: navigateHistoryUp) {
                        Image(systemName: "arrow.up")
                            .foregroundColor(.gray)
                    }
                    Button(action: navigateHistoryDown) {
                        Image(systemName: "arrow.down")
                            .foregroundColor(.gray)
                    }
                    Button(action: executeCommand) {
                        Image(systemName: "return")
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(red: 0.08, green: 0.08, blue: 0.12))

            // Quick command bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(action: copyLog) {
                        Text("copy")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(red: 0.2, green: 0.18, blue: 0.1))
                            .cornerRadius(4)
                    }

                    if activeTab == 1 {
                        quickButton("/exit", command: "/exit")
                        quickButton("/clear", command: "/clear")
                        quickButton("/help", command: "/help")
                        quickButton("/status", command: "/status")
                        quickButton("review ", command: "review ")
                        quickButton("explain ", command: "explain ")
                        quickButton("edit ", command: "edit ")
                        quickButton("create ", command: "create ")
                    } else {
                        quickButton("ls", command: "ls -la")
                        quickButton("pwd", command: "pwd")
                        quickButton("clear", command: "clear")
                        quickButton("help", command: "help")
                        quickButton("cat ", command: "cat ")
                        quickButton("|", command: "| ")
                        quickButton(">", command: "> ")
                        quickButton("&&", command: " && ")
                        quickButton("~", command: "~/")
                        quickButton("..", command: "cd ..")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .background(Color(red: 0.06, green: 0.06, blue: 0.1))
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .onDisappear {
                    syncApiKey()
                }
        }
        .onAppear {
            showWelcome()
            syncApiKey()
            setupToolProgress()
            // Auto-enter Claude mode for the Claude tab
            enterClaudeTab()
            inputFocused = true
        }
    }

    // MARK: - Tab Button

    private func tabButton(_ label: String, tab: Int, icon: String, color: Color) -> some View {
        Button(action: { switchTab(tab) }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            .foregroundColor(activeTab == tab ? color : .gray)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(activeTab == tab ? color.opacity(0.15) : Color.clear)
        }
    }

    private func switchTab(_ tab: Int) {
        activeTab = tab
        if tab == 1 && !shell.claudeMode {
            enterClaudeTab()
        }
        if tab == 0 {
            shell.claudeMode = false
        }
    }

    private func enterClaudeTab() {
        if claudeTerminal.lines.isEmpty {
            DispatchQueue.global(qos: .userInitiated).async {
                shell.claudeMode = true
                let banner = shell.enterClaudeMode()
                DispatchQueue.main.async {
                    claudeTerminal.addOutput(banner)
                }
            }
        } else {
            shell.claudeMode = true
        }
    }

    // MARK: - Views

    @ViewBuilder
    private func terminalLine(_ line: TerminalEmulator.TerminalLine) -> some View {
        let color: Color = {
            switch line.type {
            case .prompt: return promptColor
            case .input: return .white
            case .output: return outputColor
            case .error: return errorColor
            case .system: return systemColor
            case .tool: return toolColor
            }
        }()

        Text(line.text)
            .font(monoFont)
            .foregroundColor(color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quickButton(_ label: String, command: String) -> some View {
        Button(action: {
            if command.hasSuffix(" ") || command.hasPrefix(" ") {
                inputText += command
            } else if command.isEmpty {
                inputText = ""
            } else {
                inputText = command
                executeCommand()
            }
        }) {
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(red: 0.15, green: 0.15, blue: 0.2))
                .cornerRadius(4)
        }
    }

    // MARK: - Properties

    private var promptString: String {
        if activeTab == 1 {
            return "claude>"
        }
        let dir = shell.currentDirectory
        let shortDir = dir == "/" ? "~" : (dir as NSString).lastPathComponent
        return "\(shortDir) $"
    }

    // MARK: - Actions

    private func executeCommand() {
        let command = inputText.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return }

        terminal.addPrompt("\(promptString) \(command)")

        if commandHistory.last != command {
            commandHistory.append(command)
        }
        historyIndex = -1
        inputText = ""

        // --- Claude tab ---
        if activeTab == 1 {
            if command == "clear" || command == "/clear" {
                claudeTerminal.clear()
                if command == "/clear" { ClaudeEngine.shared.clearHistory() }
                return
            }

            if command == "/exit" {
                // Switch back to shell tab instead of exiting
                shell.claudeMode = false
                claudeTerminal.addSystem("Switched to Shell tab")
                activeTab = 0
                return
            }

            shell.claudeMode = true
            claudeTerminal.addSystem("Thinking...")

            DispatchQueue.global(qos: .userInitiated).async {
                let response = self.shell.handleClaudeInput(command)
                DispatchQueue.main.async {
                    if let idx = self.claudeTerminal.lines.lastIndex(where: { $0.text == "Thinking..." }) {
                        self.claudeTerminal.lines.remove(at: idx)
                    }
                    if !response.isEmpty {
                        self.claudeTerminal.addOutput(response)
                    }
                }
            }
            return
        }

        // --- Shell tab ---
        if command == "clear" {
            shellTerminal.clear()
            return
        }

        // "claude" in shell tab → switch to Claude tab
        let parts = command.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if parts.first == "claude" {
            if parts.count == 1 {
                activeTab = 1
                shell.claudeMode = true
                if claudeTerminal.lines.isEmpty { enterClaudeTab() }
                return
            } else if parts.count >= 2 && !["config", "status"].contains(parts[1]) {
                // One-shot stays in shell tab
                let message = parts.dropFirst().joined(separator: " ")
                shellTerminal.addSystem("Thinking...")
                DispatchQueue.global(qos: .userInitiated).async {
                    let response = self.shell.claudeOneShot(message)
                    DispatchQueue.main.async {
                        if let idx = self.shellTerminal.lines.lastIndex(where: { $0.text == "Thinking..." }) {
                            self.shellTerminal.lines.remove(at: idx)
                        }
                        if !response.isEmpty { self.shellTerminal.addOutput(response) }
                    }
                }
                return
            }
        }

        // Regular shell command
        DispatchQueue.global(qos: .userInitiated).async {
            self.shell.clearOutput()
            self.shell.execute(command)
            let output = self.shell.flushOutput()
            DispatchQueue.main.async {
                if !output.isEmpty { self.shellTerminal.addOutput(output) }
            }
        }
    }

    private func navigateHistoryUp() {
        guard !commandHistory.isEmpty else { return }
        if historyIndex < 0 {
            historyIndex = commandHistory.count - 1
        } else if historyIndex > 0 {
            historyIndex -= 1
        }
        inputText = commandHistory[historyIndex]
    }

    private func navigateHistoryDown() {
        guard historyIndex >= 0 else { return }
        if historyIndex < commandHistory.count - 1 {
            historyIndex += 1
            inputText = commandHistory[historyIndex]
        } else {
            historyIndex = -1
            inputText = ""
        }
    }

    private func insertText(_ text: String) {
        inputText += text
    }

    private func copyLog() {
        let fullLog = terminal.lines.map { $0.text }.joined(separator: "\n")
        UIPasteboard.general.string = fullLog
        terminal.addSystem("Copied \(terminal.lines.count) lines to clipboard")
    }

    private func syncApiKey() {
        if OAuthManager.shared.isSignedIn { return }
        if !savedApiKey.isEmpty {
            shell.execute("export ANTHROPIC_API_KEY=\(savedApiKey)")
            shell.clearOutput()
        }
    }

    private func setupToolProgress() {
        shell.toolProgressCallback = { [self] message in
            DispatchQueue.main.async {
                self.claudeTerminal.addTool(message)
            }
        }
    }

    private func showWelcome() {
        shellTerminal.addSystem("ClaudeShell v1.0 — Claude Code for iOS")
        if OAuthManager.shared.isSignedIn {
            shellTerminal.addSystem("Signed in with Claude Pro/Max ✓")
        } else if !savedApiKey.isEmpty {
            shellTerminal.addSystem("API key configured ✓")
        } else {
            shellTerminal.addSystem("Configure auth in Settings (gear icon)")
        }
        shellTerminal.addSystem("Type 'help' for commands, or tap Claude tab")
        shellTerminal.addSystem("")
    }
}

struct TerminalView_Previews: PreviewProvider {
    static var previews: some View {
        TerminalView()
            .preferredColorScheme(.dark)
    }
}
