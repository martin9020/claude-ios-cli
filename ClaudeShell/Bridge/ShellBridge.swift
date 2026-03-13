import Foundation

/// Bridges the C shell engine to Swift, handling callbacks for output,
/// network requests, and Claude AI integration.
class ShellBridge: ObservableObject {
    private var shell: UnsafeMutablePointer<Shell>?
    let sandboxRoot: String

    @Published var outputBuffer: String = ""
    @Published var isRunning: Bool = true
    @Published var claudeMode: Bool = false

    // Singleton for C callback access
    static var shared: ShellBridge?

    init() {
        // Use app's Documents directory as sandbox root
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.sandboxRoot = docs.path

        // Create initial directory structure
        let dirs = ["bin", "home", "tmp", "var", "etc", "projects"]
        for dir in dirs {
            let path = docs.appendingPathComponent(dir)
            try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        }

        // Write welcome file
        let welcomePath = docs.appendingPathComponent("README.txt")
        if !FileManager.default.fileExists(atPath: welcomePath.path) {
            let welcome = """
            Welcome to ClaudeShell!
            =======================

            This is your sandboxed filesystem on iOS.
            Everything runs locally in the app's sandbox.

            Quick start:
              help          - Show all available commands
              claude        - Start AI chat (interactive mode)
              claude <msg>  - Quick one-shot AI question
              ls            - List files
              cat README.txt - Read this file

            Your files are stored in the app's Documents directory.
            """
            try? welcome.write(to: welcomePath, atomically: true, encoding: .utf8)
        }

        // Create shell instance
        ShellBridge.shared = self
        shell = shell_create(sandboxRoot, shellOutputCallback, nil)

        // Register network handler
        shell_set_network_handler(networkRequestCallback)

        // Register claude handler
        shell_set_claude_handler(claudeCommandCallback)
    }

    deinit {
        if let shell = shell {
            shell_destroy(shell)
        }
    }

    /// Execute a command line
    func execute(_ command: String) {
        guard let shell = shell else { return }
        let _ = shell_exec(shell, command)

        // If "exit" was called, the shell sets running=0.
        // On iOS we keep the shell alive — reset it.
        if shell_is_running(shell) == 0 {
            shell_reset_running(shell)
        }
    }

    /// Get the current working directory (display path)
    var currentDirectory: String {
        guard let shell = shell else { return "/" }
        return String(cString: shell_get_cwd(shell))
    }

    /// Append text to output buffer (called from C callback)
    func appendOutput(_ text: String) {
        DispatchQueue.main.async {
            self.outputBuffer += text
        }
    }

    /// Clear output buffer
    func clearOutput() {
        DispatchQueue.main.async {
            self.outputBuffer = ""
        }
    }

    /// Enter interactive Claude mode
    func enterClaudeMode() -> String {
        guard let shell = shell else {
            claudeMode = false
            return "Error: shell not initialized\n"
        }

        // Check API key
        guard let apiKeyPtr = shell_get_env(shell, "ANTHROPIC_API_KEY") else {
            claudeMode = false
            return """
            \u{001B}[1;31mNo API key configured.\u{001B}[0m

            Set your key first:
              export ANTHROPIC_API_KEY=sk-ant-...

            Or configure in Settings (gear icon).
            """
        }

        let _ = String(cString: apiKeyPtr) // validate it's readable
        claudeMode = true

        // Get directory listing for context
        let cwd = currentDirectory
        let fullCwd = sandboxRoot + cwd
        var fileList = ""
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: fullCwd) {
            fileList = entries.prefix(20).joined(separator: ", ")
            if entries.count > 20 { fileList += " ... (\(entries.count) total)" }
        }

        var banner = """
        \u{001B}[1;35m╭──────────────────────────────────────╮\u{001B}[0m
        \u{001B}[1;35m│\u{001B}[0m  \u{001B}[1;37mClaude Code\u{001B}[0m · \u{001B}[36mClaudeShell v1.0\u{001B}[0m      \u{001B}[1;35m│\u{001B}[0m
        \u{001B}[1;35m│\u{001B}[0m  \u{001B}[90mModel: claude-sonnet-4\u{001B}[0m              \u{001B}[1;35m│\u{001B}[0m
        \u{001B}[1;35m│\u{001B}[0m  \u{001B}[90mJust type naturally. /help for cmds\u{001B}[0m  \u{001B}[1;35m│\u{001B}[0m
        \u{001B}[1;35m╰──────────────────────────────────────╯\u{001B}[0m
        """

        if !fileList.isEmpty {
            banner += "\n\u{001B}[90mFiles here: \(fileList)\u{001B}[0m"
        }

        return banner
    }

    /// Handle input while in Claude mode
    func handleClaudeInput(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        // Slash commands
        if trimmed.hasPrefix("/") {
            return handleSlashCommand(trimmed)
        }

        // Empty input
        if trimmed.isEmpty { return "" }

        guard let shell = shell else { return "Error: shell not available\n" }

        guard let apiKeyPtr = shell_get_env(shell, "ANTHROPIC_API_KEY") else {
            claudeMode = false
            return "Error: API key lost. Run 'export ANTHROPIC_API_KEY=...' and try again.\n"
        }

        let apiKey = String(cString: apiKeyPtr)
        let cwd = currentDirectory

        // Build context: list files in current directory
        let fullCwd = sandboxRoot + cwd
        var dirContext = ""
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: fullCwd) {
            dirContext = entries.joined(separator: "\n")
        }

        // If user references a file that exists, read it for context
        var fileContext = ""
        let words = trimmed.components(separatedBy: .whitespaces)
        for word in words {
            let cleanWord = word.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`,;:"))
            if cleanWord.contains(".") && !cleanWord.hasPrefix("http") {
                let filePath: String
                if cleanWord.hasPrefix("/") {
                    filePath = sandboxRoot + cleanWord
                } else {
                    filePath = fullCwd + "/" + cleanWord
                }
                if FileManager.default.fileExists(atPath: filePath),
                   let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
                    let preview = content.count > 2000 ? String(content.prefix(2000)) + "\n...(truncated)" : content
                    fileContext += "\n\n--- Content of \(cleanWord) ---\n\(preview)\n--- End of \(cleanWord) ---"
                }
            }
        }

        var fullPrompt = trimmed
        if !fileContext.isEmpty {
            fullPrompt += fileContext
        }

        // Call Claude
        var result = ""
        let semaphore = DispatchSemaphore(value: 0)

        ClaudeEngine.shared.sendMessage(
            prompt: fullPrompt,
            apiKey: apiKey,
            cwd: cwd,
            directoryListing: dirContext
        ) { response in
            result = response
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    /// Handle slash commands in Claude mode
    private func handleSlashCommand(_ cmd: String) -> String {
        let parts = cmd.components(separatedBy: .whitespaces)
        let command = parts[0].lowercased()

        switch command {
        case "/exit", "/quit", "/q":
            claudeMode = false
            ClaudeEngine.shared.clearHistory()
            return "\u{001B}[90mExited Claude mode.\u{001B}[0m"

        case "/clear":
            ClaudeEngine.shared.clearHistory()
            return "\u{001B}[90mConversation cleared.\u{001B}[0m"

        case "/status":
            guard let shell = shell else { return "Shell not available\n" }
            let hasKey = shell_get_env(shell, "ANTHROPIC_API_KEY") != nil
            return """
            \u{001B}[1mClaude Status\u{001B}[0m
              API: \(hasKey ? "\u{001B}[32mconnected\u{001B}[0m" : "\u{001B}[31mno key\u{001B}[0m")
              Model: claude-sonnet-4
              History: \(ClaudeEngine.shared.historyCount) messages
            """

        case "/model":
            return "\u{001B}[90mCurrent model: claude-sonnet-4\u{001B}[0m"

        case "/help":
            return """
            \u{001B}[1mClaude Mode Commands\u{001B}[0m
              \u{001B}[33m/exit\u{001B}[0m     Return to shell
              \u{001B}[33m/clear\u{001B}[0m    Clear conversation history
              \u{001B}[33m/status\u{001B}[0m   Show connection status
              \u{001B}[33m/help\u{001B}[0m     Show this help

            \u{001B}[1mJust type naturally:\u{001B}[0m
              "make a python script that sorts files"
              "review todo.py"
              "what's in this directory?"
              "explain how grep works"
              "edit config.json and add a new field"
            """

        default:
            return "\u{001B}[31mUnknown command: \(command)\u{001B}[0m\nType /help for available commands."
        }
    }

    /// One-shot Claude message (for `claude <message>` without entering interactive mode)
    func claudeOneShot(_ message: String) -> String {
        guard let shell = shell else { return "Error: shell not available\n" }

        guard let apiKeyPtr = shell_get_env(shell, "ANTHROPIC_API_KEY") else {
            return """
            \u{001B}[31mNo API key set.\u{001B}[0m Run: export ANTHROPIC_API_KEY=sk-ant-...
            """
        }

        let apiKey = String(cString: apiKeyPtr)
        let cwd = currentDirectory
        let fullCwd = sandboxRoot + cwd

        var dirContext = ""
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: fullCwd) {
            dirContext = entries.joined(separator: "\n")
        }

        var result = ""
        let semaphore = DispatchSemaphore(value: 0)

        ClaudeEngine.shared.sendMessage(
            prompt: message,
            apiKey: apiKey,
            cwd: cwd,
            directoryListing: dirContext
        ) { response in
            result = response
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }
}

// MARK: - C Callbacks

/// Output callback — receives text from the C shell
private func shellOutputCallback(_ text: UnsafePointer<CChar>?, _ ctx: UnsafeMutableRawPointer?) {
    guard let text = text else { return }
    let str = String(cString: text)
    ShellBridge.shared?.appendOutput(str)
}

/// Network request callback — handles curl/wget via URLSession
private func networkRequestCallback(
    _ sh: UnsafeMutablePointer<Shell>?,
    _ url: UnsafePointer<CChar>?,
    _ method: UnsafePointer<CChar>?,
    _ data: UnsafePointer<CChar>?,
    _ outputFile: UnsafePointer<CChar>?
) {
    guard let sh = sh, let url = url, let method = method else { return }

    let urlStr = String(cString: url)
    let methodStr = String(cString: method)
    let dataStr = data != nil ? String(cString: data!) : nil

    guard let requestURL = URL(string: urlStr) else {
        shell_output(sh, "curl: invalid URL\n")
        return
    }

    var request = URLRequest(url: requestURL)
    request.httpMethod = methodStr
    request.timeoutInterval = 30

    if let dataStr = dataStr {
        request.httpBody = dataStr.data(using: .utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    // Synchronous request
    let semaphore = DispatchSemaphore(value: 0)
    var responseBody = ""
    var statusCode = 0

    let task = URLSession.shared.dataTask(with: request) { respData, response, error in
        if let error = error {
            responseBody = "curl: \(error.localizedDescription)\n"
            statusCode = 1
        } else if let httpResponse = response as? HTTPURLResponse {
            statusCode = httpResponse.statusCode
            if let respData = respData, let body = String(data: respData, encoding: .utf8) {
                responseBody = body
            }
        }
        semaphore.signal()
    }
    task.resume()
    semaphore.wait()

    if let outputFile = outputFile {
        let filename = String(cString: outputFile)
        let cwd = String(cString: shell_get_cwd(sh))
        let filePath = "\(cwd)/\(filename)"
        try? responseBody.write(toFile: filePath, atomically: true, encoding: .utf8)
        shell_output(sh, "Saved to \(filename) (\(responseBody.count) bytes)\n")
    } else {
        shell_output(sh, responseBody)
        if !responseBody.hasSuffix("\n") {
            shell_output(sh, "\n")
        }
    }

    shell_set_exit_code(sh, (statusCode >= 200 && statusCode < 400) ? 0 : 1)
}

/// Claude command callback — handles `claude config` and `claude status` from C dispatch
private func claudeCommandCallback(
    _ sh: UnsafeMutablePointer<Shell>?,
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) {
    guard let sh = sh else { return }

    // If no subcommand, this is handled by TerminalView (interactive mode)
    guard let argv = argv, argc >= 2 else {
        // Shouldn't reach here — TerminalView intercepts bare "claude"
        shell_output(sh, "Type 'claude' to enter interactive AI mode.\n")
        return
    }

    let subcommand = String(cString: argv[1]!)

    switch subcommand {
    case "config":
        let hasKey = shell_get_env(sh, "ANTHROPIC_API_KEY") != nil
        shell_output(sh, "Current API key: \(hasKey ? "****configured****" : "(not set)")\n")
        shell_output(sh, "Set with: export ANTHROPIC_API_KEY=sk-ant-...\n")
        shell_output(sh, "Or configure in Settings (gear icon).\n")

    case "status":
        let hasKey = shell_get_env(sh, "ANTHROPIC_API_KEY") != nil
        shell_output(sh, "Claude API: \(hasKey ? "ready" : "no API key set")\n")
        shell_output(sh, "Model: claude-sonnet-4-20250514\n")
        shell_output(sh, "History: \(ClaudeEngine.shared.historyCount) messages\n")
        shell_output(sh, "Shell: ClaudeShell v1.0\n")

    default:
        // Any other "claude <message>" is handled by TerminalView as one-shot
        shell_output(sh, "Handled by interactive mode.\n")
    }
}
