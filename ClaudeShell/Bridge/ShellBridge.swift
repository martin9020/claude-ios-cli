import Foundation

/// Type alias — Shell* comes in as OpaquePointer from C because
/// the struct contains arrays of pointers which Swift can't directly represent.
/// We wrap all C calls through helper functions.
typealias ShellPointer = OpaquePointer

/// Bridges the C shell engine to Swift, handling callbacks for output,
/// network requests, and Claude AI integration.
class ShellBridge: ObservableObject {
    private var shell: ShellPointer?
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
        isRunning = shell_is_running(shell)
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
}

// MARK: - C Helper Functions

/// These small C-callable helpers avoid accessing .pointee on OpaquePointer.
/// They are defined in shell_helpers.c and exposed via the bridging header.

// MARK: - C Callbacks

/// Output callback — receives text from the C shell
private func shellOutputCallback(_ text: UnsafePointer<CChar>?, _ ctx: UnsafeMutableRawPointer?) {
    guard let text = text else { return }
    let str = String(cString: text)
    ShellBridge.shared?.appendOutput(str)
}

/// Network request callback — handles curl/wget via URLSession
private func networkRequestCallback(
    _ sh: ShellPointer?,
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

/// Claude command callback — handles `claude` commands via ClaudeEngine
private func claudeCommandCallback(
    _ sh: ShellPointer?,
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) {
    guard let sh = sh, let argv = argv, argc >= 2 else {
        if let sh = sh {
            shell_output(sh, "Usage: claude <ask|run|edit|review|config|status> [args]\n")
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
        let hasKey = shell_get_env(sh, "ANTHROPIC_API_KEY") != nil
        shell_output(sh, "Current API key: \(hasKey ? "****configured****" : "(not set)")\n")
        shell_output(sh, "Set with: export ANTHROPIC_API_KEY=sk-ant-...\n")

    case "status":
        let hasKey = shell_get_env(sh, "ANTHROPIC_API_KEY") != nil
        shell_output(sh, "Claude API: \(hasKey ? "ready" : "no API key set")\n")
        shell_output(sh, "Model: claude-sonnet-4-20250514\n")
        shell_output(sh, "Shell: ClaudeShell v1.0\n")

    case "ask", "run", "edit", "review":
        if prompt.isEmpty {
            shell_output(sh, "claude \(subcommand): please provide a prompt\n")
            shell_set_exit_code(sh, 1)
            return
        }

        guard let apiKeyPtr = shell_get_env(sh, "ANTHROPIC_API_KEY") else {
            shell_output(sh, "Error: ANTHROPIC_API_KEY not set\n")
            shell_output(sh, "Run: export ANTHROPIC_API_KEY=sk-ant-...\n")
            shell_set_exit_code(sh, 1)
            return
        }

        let apiKey = String(cString: apiKeyPtr)
        shell_output(sh, "Thinking...\n")

        let cwd = String(cString: shell_get_cwd(sh))

        // Build context for edit/review
        var fullPrompt = prompt
        if subcommand == "edit" || subcommand == "review" {
            let filepath: String
            let root = String(cString: shell_get_root(sh))
            if prompt.hasPrefix("/") {
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
            cwd: cwd
        ) { response in
            shell_output(sh, "\n\(response)\n")
        }

    default:
        shell_output(sh, "claude: unknown subcommand '\(subcommand)'\n")
        shell_output(sh, "Usage: claude <ask|run|edit|review|config|status>\n")
        shell_set_exit_code(sh, 1)
    }
}
