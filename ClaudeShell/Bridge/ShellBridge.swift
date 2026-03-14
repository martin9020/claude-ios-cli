import Foundation

/// Bridges the C shell engine to Swift, handling callbacks for output,
/// network requests, and Claude AI integration.
class ShellBridge: ObservableObject {
    private var shell: UnsafeMutablePointer<Shell>?
    let sandboxRoot: String

    @Published var outputBuffer: String = ""
    @Published var isRunning: Bool = true
    @Published var claudeMode: Bool = false

    /// Thread-safe capture buffer — written directly by C callbacks (no dispatch)
    /// Used by TerminalView to read command output synchronously after execute()
    private var captureBuffer: String = ""

    /// Callback for live tool execution progress (set by TerminalView)
    var toolProgressCallback: ((String) -> Void)?

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

        // Register node/npm handlers
        shell_set_node_handler(nodeCommandCallback)
        shell_set_npm_handler(npmCommandCallback)

        // Initialize JS engine and npm manager
        JsEngine.shared.setup(sandboxRoot: sandboxRoot)
        NpmManager.shared.setup(sandboxRoot: sandboxRoot)
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

    /// Append text to output buffer (called from C callback on same thread as execute)
    func appendOutput(_ text: String) {
        // Write to capture buffer directly (same thread as shell_exec)
        captureBuffer += text
    }

    /// Clear capture buffer and return its contents
    func flushOutput() -> String {
        let output = captureBuffer
        captureBuffer = ""
        return output
    }

    /// Clear output buffer (legacy)
    func clearOutput() {
        captureBuffer = ""
    }

    // MARK: - Tool Execution (Phase 2: Autonomous)

    /// Execute a shell command and capture the output synchronously
    func executeAndCapture(_ command: String) -> String {
        guard let shell = shell else { return "Error: shell not initialized\n" }

        // Save and clear the capture buffer
        let savedBuffer = captureBuffer
        captureBuffer = ""

        // Execute — C callbacks write to captureBuffer synchronously
        let _ = shell_exec(shell, command)

        if shell_is_running(shell) == 0 {
            shell_reset_running(shell)
        }

        // Get captured output and restore
        let captured = captureBuffer
        captureBuffer = savedBuffer

        return captured
    }

    /// Resolve and validate a path stays within the sandbox
    private func resolveSandboxPath(_ path: String) -> String? {
        let fullPath: String
        if path.hasPrefix("/") {
            fullPath = sandboxRoot + path
        } else {
            fullPath = sandboxRoot + currentDirectory + "/" + path
        }
        // Canonicalize to resolve ../ and symlinks, then verify it's within sandbox
        let canonical = (fullPath as NSString).standardizingPath
        guard canonical.hasPrefix(sandboxRoot) else {
            return nil // Path escapes sandbox
        }
        return canonical
    }

    /// Execute a tool by name with given input parameters
    func executeTool(_ toolName: String, _ input: [String: Any]) -> String {
        switch toolName {
        case "bash":
            guard let command = input["command"] as? String else {
                return "Error: 'command' parameter required for bash tool"
            }
            toolProgressCallback?("> Running: \(command)")
            return executeAndCapture(command)

        case "read_file":
            guard let path = input["path"] as? String else {
                return "Error: 'path' parameter required for read_file tool"
            }
            toolProgressCallback?("> Reading: \(path)")
            guard let fullPath = resolveSandboxPath(path) else {
                return "Error: Path outside sandbox: \(path)"
            }
            if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                // Limit to 10KB to stay within API limits
                if content.count > 10240 {
                    return String(content.prefix(10240)) + "\n...(truncated at 10KB)"
                }
                return content
            } else {
                return "Error: File not found or unreadable: \(path)"
            }

        case "write_file":
            guard let path = input["path"] as? String,
                  let content = input["content"] as? String else {
                return "Error: 'path' and 'content' parameters required for write_file tool"
            }
            toolProgressCallback?("> Writing: \(path)")
            guard let fullPath = resolveSandboxPath(path) else {
                return "Error: Path outside sandbox: \(path)"
            }
            // Create parent directories if needed
            let dir = (fullPath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            do {
                try content.write(toFile: fullPath, atomically: true, encoding: .utf8)
                return "File written: \(path) (\(content.count) bytes)"
            } catch {
                return "Error writing file: \(error.localizedDescription)"
            }

        default:
            return "Error: Unknown tool '\(toolName)'"
        }
    }

    // MARK: - Agentic Claude Mode

    /// Handle input with agentic tool loop — Claude autonomously uses tools
    func handleClaudeInputAgentic(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespaces)

        // Slash commands handled normally
        if trimmed.hasPrefix("/") {
            return handleSlashCommand(trimmed)
        }

        if trimmed.isEmpty { return "" }

        guard let shell = shell else { return "Error: shell not available\n" }

        let apiKey: String
        if let apiKeyPtr = shell_get_env(shell, "ANTHROPIC_API_KEY") {
            apiKey = String(cString: apiKeyPtr)
        } else {
            apiKey = "" // Will try OAuth
        }

        // Check if we have any auth
        if apiKey.isEmpty && OAuthManager.shared.getToken() == nil {
            claudeMode = false
            return "Error: No API key or OAuth token. Configure in Settings.\n"
        }

        let cwd = currentDirectory
        let fullCwd = sandboxRoot + cwd

        // Build context
        var dirContext = ""
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: fullCwd) {
            dirContext = entries.joined(separator: "\n")
        }

        // Read referenced files for context
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

        // Agentic loop
        var iteration = 0
        let maxIterations = 75
        var outputParts: [String] = []

        // Initial call with tools
        var response = ClaudeEngine.shared.sendMessageWithTools(
            prompt: fullPrompt,
            apiKey: apiKey,
            cwd: cwd,
            directoryListing: dirContext
        )

        while iteration < maxIterations {
            iteration += 1

            switch response {
            case .text(let text):
                outputParts.append(text)
                return outputParts.joined(separator: "\n")

            case .toolUse(let id, let name, let input):
                let toolResult = executeTool(name, input)
                outputParts.append("⚙ \(name): \(toolResultSummary(name, input))")
                ClaudeEngine.shared.appendToolResult(toolUseId: id, result: toolResult)

                // Continue the loop
                response = ClaudeEngine.shared.sendMessageWithTools(
                    prompt: "", apiKey: apiKey, cwd: cwd,
                    directoryListing: dirContext,
                    messages: ClaudeEngine.shared.conversationHistory
                )

            case .mixed(let text, let toolUses):
                if !text.isEmpty {
                    outputParts.append(text)
                }
                // Execute all tool uses
                for tu in toolUses {
                    let toolResult = executeTool(tu.name, tu.input)
                    outputParts.append("⚙ \(tu.name): \(toolResultSummary(tu.name, tu.input))")
                    ClaudeEngine.shared.appendToolResult(toolUseId: tu.id, result: toolResult)
                }
                // Continue
                response = ClaudeEngine.shared.sendMessageWithTools(
                    prompt: "", apiKey: apiKey, cwd: cwd,
                    directoryListing: dirContext,
                    messages: ClaudeEngine.shared.conversationHistory
                )

            case .error(let error):
                outputParts.append("Error: \(error)")
                return outputParts.joined(separator: "\n")
            }
        }

        // Add tool_result for any pending tool_use in the last response
        // so conversation history stays valid for the next message
        switch response {
        case .toolUse(let id, _, _):
            ClaudeEngine.shared.appendToolResult(toolUseId: id, result: "Stopped: maximum iterations reached")
        case .mixed(_, let toolUses):
            for tu in toolUses {
                ClaudeEngine.shared.appendToolResult(toolUseId: tu.id, result: "Stopped: maximum iterations reached")
            }
        default:
            break
        }
        outputParts.append("\n⚠ Reached maximum iterations (\(maxIterations))")
        return outputParts.joined(separator: "\n")
    }

    /// Summarize a tool execution for display
    private func toolResultSummary(_ name: String, _ input: [String: Any]) -> String {
        switch name {
        case "bash":
            return input["command"] as? String ?? ""
        case "read_file":
            return input["path"] as? String ?? ""
        case "write_file":
            return input["path"] as? String ?? ""
        default:
            return name
        }
    }

    /// Enter interactive Claude mode
    func enterClaudeMode() -> String {
        guard let shell = shell else {
            claudeMode = false
            return "Error: shell not initialized\n"
        }

        // Check for auth: OAuth or API key
        let hasApiKey = shell_get_env(shell, "ANTHROPIC_API_KEY") != nil
        let hasOAuth = OAuthManager.shared.isSignedIn

        if !hasApiKey && !hasOAuth {
            claudeMode = false
            return """
            \u{001B}[1;31mNo authentication configured.\u{001B}[0m

            Option A: Sign in with Claude Pro/Max in Settings.
            Option B: export ANTHROPIC_API_KEY=sk-ant-...

            Or configure in Settings (gear icon).
            """
        }

        claudeMode = true

        // Get directory listing for context
        let cwd = currentDirectory
        let fullCwd = sandboxRoot + cwd
        var fileList = ""
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: fullCwd) {
            fileList = entries.prefix(20).joined(separator: ", ")
            if entries.count > 20 { fileList += " ... (\(entries.count) total)" }
        }

        let authLabel = hasOAuth ? "Pro/Max" : "API Key"
        var banner = """
        \u{001B}[1;35m╭──────────────────────────────────────╮\u{001B}[0m
        \u{001B}[1;35m│\u{001B}[0m  \u{001B}[1;37mClaude Code\u{001B}[0m · \u{001B}[36mClaudeShell v1.0\u{001B}[0m      \u{001B}[1;35m│\u{001B}[0m
        \u{001B}[1;35m│\u{001B}[0m  \u{001B}[90mModel: claude-sonnet-4\u{001B}[0m              \u{001B}[1;35m│\u{001B}[0m
        \u{001B}[1;35m│\u{001B}[0m  \u{001B}[90mAuth: \(authLabel)\u{001B}[0m                        \u{001B}[1;35m│\u{001B}[0m
        \u{001B}[1;35m│\u{001B}[0m  \u{001B}[90mTools: bash, read_file, write_file\u{001B}[0m  \u{001B}[1;35m│\u{001B}[0m
        \u{001B}[1;35m│\u{001B}[0m  \u{001B}[90mJust type naturally. /help for cmds\u{001B}[0m  \u{001B}[1;35m│\u{001B}[0m
        \u{001B}[1;35m╰──────────────────────────────────────╯\u{001B}[0m
        """

        if !fileList.isEmpty {
            banner += "\n\u{001B}[90mFiles here: \(fileList)\u{001B}[0m"
        }

        return banner
    }

    /// Handle input while in Claude mode — uses agentic tool loop
    func handleClaudeInput(_ input: String) -> String {
        return handleClaudeInputAgentic(input)
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
            let hasOAuth = OAuthManager.shared.isSignedIn
            return """
            \u{001B}[1mClaude Status\u{001B}[0m
              API: \(hasKey ? "\u{001B}[32mAPI key set\u{001B}[0m" : "\u{001B}[90mno API key\u{001B}[0m")
              OAuth: \(hasOAuth ? "\u{001B}[32mPro/Max signed in\u{001B}[0m" : "\u{001B}[90mnot signed in\u{001B}[0m")
              Model: claude-sonnet-4
              History: \(ClaudeEngine.shared.historyCount) messages
              Tools: bash, read_file, write_file
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
              "create a project with index.html and style.css"

            \u{001B}[1mAutonomous tools:\u{001B}[0m
              Claude can run commands, read and write files automatically.
              Watch the ⚙ indicators to see what Claude is doing.
            """

        default:
            return "\u{001B}[31mUnknown command: \(command)\u{001B}[0m\nType /help for available commands."
        }
    }

    /// One-shot Claude message (for `claude <message>` without entering interactive mode)
    func claudeOneShot(_ message: String) -> String {
        guard let shell = shell else { return "Error: shell not available\n" }

        let apiKey: String
        if let apiKeyPtr = shell_get_env(shell, "ANTHROPIC_API_KEY") {
            apiKey = String(cString: apiKeyPtr)
        } else {
            apiKey = ""
        }

        // Check for any auth
        if apiKey.isEmpty && OAuthManager.shared.getToken() == nil {
            return """
            \u{001B}[31mNo authentication configured.\u{001B}[0m
            Sign in with Pro/Max in Settings, or: export ANTHROPIC_API_KEY=sk-ant-...
            """
        }

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

    guard let arg1 = argv[1] else {
        shell_output(sh, "claude: missing subcommand\n")
        return
    }
    let subcommand = String(cString: arg1)

    switch subcommand {
    case "config":
        let hasKey = shell_get_env(sh, "ANTHROPIC_API_KEY") != nil
        let hasOAuth = OAuthManager.shared.isSignedIn
        shell_output(sh, "API key: \(hasKey ? "****configured****" : "(not set)")\n")
        shell_output(sh, "OAuth: \(hasOAuth ? "Pro/Max signed in" : "not signed in")\n")
        shell_output(sh, "Set with: export ANTHROPIC_API_KEY=sk-ant-...\n")
        shell_output(sh, "Or sign in with Pro/Max in Settings.\n")

    case "status":
        let hasKey = shell_get_env(sh, "ANTHROPIC_API_KEY") != nil
        let hasOAuth = OAuthManager.shared.isSignedIn
        shell_output(sh, "Claude API: \(hasKey || hasOAuth ? "ready" : "no auth configured")\n")
        if hasOAuth { shell_output(sh, "Auth: Pro/Max subscription\n") }
        if hasKey { shell_output(sh, "Auth: API Key\n") }
        shell_output(sh, "Model: claude-sonnet-4-20250514\n")
        shell_output(sh, "History: \(ClaudeEngine.shared.historyCount) messages\n")
        shell_output(sh, "Tools: bash, read_file, write_file\n")
        shell_output(sh, "Shell: ClaudeShell v1.0\n")

    default:
        // Any other "claude <message>" is handled by TerminalView as one-shot
        shell_output(sh, "Handled by interactive mode.\n")
    }
}

/// Node command callback — runs JavaScript via JavaScriptCore
private func nodeCommandCallback(
    _ sh: UnsafeMutablePointer<Shell>?,
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) {
    guard let sh = sh else { return }

    var args: [String] = []
    if let argv = argv {
        for i in 0..<Int(argc) {
            if let arg = argv[i] {
                args.append(String(cString: arg))
            }
        }
    }

    let cwd = String(cString: shell_get_cwd(sh))
    let root = String(cString: shell_get_root(sh))

    // node -e "code" — eval mode
    if args.count >= 3 && args[1] == "-e" {
        let code = args.dropFirst(2).joined(separator: " ")
        let exitCode = JsEngine.shared.runEval(source: code, cwd: root + cwd) { output in
            shell_output(sh, output)
        }
        shell_set_exit_code(sh, exitCode)
        return
    }

    // node <file> — run file
    if args.count >= 2 {
        let filename = args[1]
        let filePath: String
        if filename.hasPrefix("/") {
            filePath = root + filename
        } else {
            filePath = root + cwd + "/" + filename
        }
        let fileArgs = Array(args.dropFirst(2))
        let exitCode = JsEngine.shared.runFile(path: filePath, cwd: root + cwd, args: fileArgs) { output in
            shell_output(sh, output)
        }
        shell_set_exit_code(sh, exitCode)
        return
    }

    // node (no args) — show version info
    shell_output(sh, "ClaudeShell JavaScript Engine (JavaScriptCore)\n")
    shell_output(sh, "Usage: node <file.js>      Run a JavaScript file\n")
    shell_output(sh, "       node -e \"code\"      Evaluate JavaScript\n")
}

/// npm command callback — handles package management
private func npmCommandCallback(
    _ sh: UnsafeMutablePointer<Shell>?,
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) {
    guard let sh = sh else { return }

    var args: [String] = []
    if let argv = argv {
        for i in 1..<Int(argc) { // Skip "npm" itself
            if let arg = argv[i] {
                args.append(String(cString: arg))
            }
        }
    }

    let cwd = String(cString: shell_get_cwd(sh))

    let exitCode = NpmManager.shared.handleCommand(args: args, cwd: cwd) { output in
        shell_output(sh, output)
    }
    shell_set_exit_code(sh, exitCode)
}
