import Foundation

/// Bridges the C shell engine to Swift, handling callbacks for output,
/// network requests, and Claude AI integration.
class ShellBridge: ObservableObject {
    private var shell: OpaquePointer?
    private let sandboxRoot: String

    @Published var outputBuffer: String = ""
    @Published var isRunning: Bool = true

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
              claude ask    - Ask Claude AI a question
              claude run    - Run an AI-powered task
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
        isRunning = shell.pointee.running != 0
    }

    /// Get the current working directory (display path)
    var currentDirectory: String {
        guard let shell = shell else { return "/" }
        let cwd = String(cString: &shell.pointee.cwd.0)
        let root = String(cString: &shell.pointee.root.0)
        let display = String(cwd.dropFirst(root.count))
        return display.isEmpty ? "/" : display
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
    _ sh: OpaquePointer?,
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
        shell_printf(sh, "curl: invalid URL: %s\n", url)
        return
    }

    var request = URLRequest(url: requestURL)
    request.httpMethod = methodStr
    request.timeoutInterval = 30

    if let dataStr = dataStr {
        request.httpBody = dataStr.data(using: .utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    // Synchronous request (we're already on a background context)
    let semaphore = DispatchSemaphore(value: 0)
    var responseBody = ""
    var statusCode = 0

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            responseBody = "curl: \(error.localizedDescription)\n"
            statusCode = 1
        } else if let httpResponse = response as? HTTPURLResponse {
            statusCode = httpResponse.statusCode
            if let data = data, let body = String(data: data, encoding: .utf8) {
                responseBody = body
            }
        }
        semaphore.signal()
    }
    task.resume()
    semaphore.wait()

    if let outputFile = outputFile {
        let filename = String(cString: outputFile)
        let bridge = ShellBridge.shared
        // Save to file in sandbox
        let cwd = String(cString: &sh.pointee.cwd.0)
        let filePath = "\(cwd)/\(filename)"
        try? responseBody.write(toFile: filePath, atomically: true, encoding: .utf8)
        shell_printf(sh, "Saved to %s (%d bytes)\n",
                     outputFile, Int32(responseBody.count))
    } else {
        shell_printf(sh, "%s", responseBody)
        if !responseBody.hasSuffix("\n") {
            shell_printf(sh, "\n")
        }
    }

    sh.pointee.last_exit_code = statusCode >= 200 && statusCode < 400 ? 0 : 1
}

/// Claude command callback — handles `claude` commands via ClaudeEngine
private func claudeCommandCallback(
    _ sh: OpaquePointer?,
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) {
    guard let sh = sh, let argv = argv, argc >= 2 else {
        // Show help
        if let sh = sh {
            shell_printf(sh, "Usage: claude <ask|run|edit|review|config|status> [args]\n")
        }
        return
    }

    let subcommand = String(cString: argv[1]!)
    var args: [String] = []
    for i in 2..<Int(argc) {
        if let arg = argv[i] {
            args.append(String(cString: arg))
        }
    }

    let prompt = args.joined(separator: " ")

    switch subcommand {
    case "config":
        shell_printf(sh, "Current API key: %s\n",
                     shell_getenv(sh, "ANTHROPIC_API_KEY") != nil ? "****configured****" : "(not set)")
        shell_printf(sh, "Set with: export ANTHROPIC_API_KEY=sk-ant-...\n")

    case "status":
        let hasKey = shell_getenv(sh, "ANTHROPIC_API_KEY") != nil
        shell_printf(sh, "Claude API: %s\n", hasKey ? "ready" : "no API key set")
        shell_printf(sh, "Model: claude-sonnet-4-20250514\n")
        shell_printf(sh, "Shell: ClaudeShell v1.0\n")

    case "ask", "run", "edit", "review":
        if prompt.isEmpty {
            shell_printf(sh, "claude %s: please provide a prompt\n", argv[1]!)
            sh.pointee.last_exit_code = 1
            return
        }

        guard let apiKeyPtr = shell_getenv(sh, "ANTHROPIC_API_KEY") else {
            shell_printf(sh, "Error: ANTHROPIC_API_KEY not set\n")
            shell_printf(sh, "Run: export ANTHROPIC_API_KEY=sk-ant-...\n")
            sh.pointee.last_exit_code = 1
            return
        }

        let apiKey = String(cString: apiKeyPtr)
        shell_printf(sh, "Thinking...\n")

        // Build context for edit/review
        var fullPrompt = prompt
        if subcommand == "edit" || subcommand == "review" {
            let filepath: String
            let cwd = String(cString: &sh.pointee.cwd.0)
            if prompt.hasPrefix("/") {
                let root = String(cString: &sh.pointee.root.0)
                filepath = root + prompt
            } else {
                filepath = cwd + "/" + prompt
            }
            if let content = try? String(contentsOfFile: filepath, encoding: .utf8) {
                fullPrompt = subcommand == "edit"
                    ? "Edit this file and return the complete updated content:\n\n```\n\(content)\n```"
                    : "Review this code and provide feedback:\n\n```\n\(content)\n```"
            }
        }

        // Call Claude API
        ClaudeEngine.shared.sendMessage(
            prompt: fullPrompt,
            apiKey: apiKey,
            cwd: String(cString: &sh.pointee.cwd.0)
        ) { response in
            shell_printf(sh, "\n%s\n", (response as NSString).utf8String!)
        }

    default:
        shell_printf(sh, "claude: unknown subcommand '%s'\n", argv[1]!)
        shell_printf(sh, "Usage: claude <ask|run|edit|review|config|status>\n")
        sh.pointee.last_exit_code = 1
    }
}
