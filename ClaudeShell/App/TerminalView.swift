import SwiftUI

struct TerminalView: View {
    @StateObject private var shell = ShellBridge()
    @StateObject private var terminal = TerminalEmulator()
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
    private let bgColor = Color(red: 0.05, green: 0.05, blue: 0.1)

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.green)
                Text("ClaudeShell")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                Text(shell.currentDirectory)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 16))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(red: 0.1, green: 0.1, blue: 0.15))

            // Terminal output
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
                    .foregroundColor(shell.claudeMode ? claudePromptColor : promptColor)
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

                // Quick action buttons
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

            // Quick command bar — context-dependent
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if shell.claudeMode {
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
                        quickButton("claude", command: "claude")
                        quickButton("ctrl+c", command: "") // Cancel
                        quickButton("|", command: "| ")
                        quickButton(">", command: "> ")
                        quickButton("&&", command: " && ")
                        quickButton("~", command: "~/")
                        quickButton("/", command: "/")
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
            inputFocused = true
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
                // Insert into current input
                inputText += command
            } else if command.isEmpty {
                // Cancel / clear
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
        if shell.claudeMode {
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

        // Show prompt + command in terminal
        terminal.addPrompt("\(promptString) \(command)")

        // Add to history
        if commandHistory.last != command {
            commandHistory.append(command)
        }
        historyIndex = -1

        // Clear input
        inputText = ""

        // --- Claude mode: route input to Claude ---
        if shell.claudeMode {
            // Handle clear in claude mode too
            if command == "clear" || command == "/clear" {
                terminal.clear()
                if command == "/clear" {
                    ClaudeEngine.shared.clearHistory()
                }
                return
            }

            terminal.addSystem("Thinking...")

            DispatchQueue.global(qos: .userInitiated).async {
                let response = self.shell.handleClaudeInput(command)

                DispatchQueue.main.async {
                    // Remove "Thinking..." line
                    if let lastIdx = self.terminal.lines.lastIndex(where: { $0.text == "Thinking..." }) {
                        self.terminal.lines.remove(at: lastIdx)
                    }

                    if !response.isEmpty {
                        self.terminal.addOutput(response)
                    }
                }
            }
            return
        }

        // --- Normal shell mode ---

        // Handle clear specially
        if command == "clear" {
            terminal.clear()
            return
        }

        // Check if user typed "claude" to enter interactive mode
        // "claude" alone or "claude" with no real subcommand
        let parts = command.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if parts.first == "claude" {
            if parts.count == 1 {
                // No args: enter interactive Claude mode
                DispatchQueue.global(qos: .userInitiated).async {
                    let banner = self.shell.enterClaudeMode()
                    DispatchQueue.main.async {
                        self.terminal.addOutput(banner)
                    }
                }
                return
            } else if parts.count >= 2 && !["config", "status"].contains(parts[1]) {
                // One-shot: "claude fix this bug" / "claude review main.swift"
                let message = parts.dropFirst().joined(separator: " ")
                terminal.addSystem("Thinking...")

                DispatchQueue.global(qos: .userInitiated).async {
                    let response = self.shell.claudeOneShot(message)

                    DispatchQueue.main.async {
                        if let lastIdx = self.terminal.lines.lastIndex(where: { $0.text == "Thinking..." }) {
                            self.terminal.lines.remove(at: lastIdx)
                        }
                        if !response.isEmpty {
                            self.terminal.addOutput(response)
                        }
                    }
                }
                return
            }
            // "claude config" / "claude status" fall through to shell
        }

        // Execute on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            // Clear output buffer before executing
            self.shell.clearOutput()

            // Execute command
            self.shell.execute(command)

            // Capture output
            let output = self.shell.outputBuffer
            self.shell.clearOutput()

            DispatchQueue.main.async {
                if !output.isEmpty {
                    self.terminal.addOutput(output)
                }
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

    private func syncApiKey() {
        // Load API key from Settings into shell environment
        if !savedApiKey.isEmpty {
            shell.execute("export ANTHROPIC_API_KEY=\(savedApiKey)")
            shell.clearOutput()
        }
    }

    private func showWelcome() {
        terminal.addSystem("ClaudeShell v1.0 — Claude Code for iOS")
        terminal.addSystem("Type 'help' for commands, 'claude' to start AI chat")
        terminal.addSystem("")
    }
}

struct TerminalView_Previews: PreviewProvider {
    static var previews: some View {
        TerminalView()
            .preferredColorScheme(.dark)
    }
}
