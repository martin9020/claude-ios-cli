import Foundation

/// Represents the result of a Claude API call — either text or tool_use
enum ClaudeResponse {
    case text(String)
    case toolUse(id: String, name: String, input: [String: Any])
    case mixed(text: String, toolUses: [(id: String, name: String, input: [String: Any])])
    case error(String)
}

/// Handles communication with the Claude API (Anthropic Messages API)
class ClaudeEngine {
    static let shared = ClaudeEngine()

    private let apiURL = "https://api.anthropic.com/v1/messages"
    /// Model ID — reads from UserDefaults (set by SettingsView picker), defaults to Sonnet 4
    private var model: String {
        UserDefaults.standard.string(forKey: "model_id") ?? "claude-sonnet-4-6"
    }
    private(set) var conversationHistory: [[String: Any]] = []

    /// Number of messages in history
    var historyCount: Int { conversationHistory.count }

    /// System prompt for Claude when used inside ClaudeShell
    private func buildSystemPrompt(cwd: String, directoryListing: String, withTools: Bool = false) -> String {
        var prompt = """
        You are Claude, running inside ClaudeShell — a terminal app on iOS.
        You are a hands-on coding assistant. The user is at a shell prompt and can run commands.

        CURRENT DIRECTORY: \(cwd)
        """

        if !directoryListing.isEmpty {
            prompt += """

            FILES IN CURRENT DIRECTORY:
            \(directoryListing)
            """
        }

        // Common capabilities — always included
        prompt += """


        ENVIRONMENT: ClaudeShell on iOS (sandboxed)
        All files live in the app's Documents directory. / = Documents root.
        Files are accessible via iOS Files app under "On My iPhone > ClaudeShell".

        SHELL COMMANDS AVAILABLE:
        Filesystem: ls [-la], cat, cp, mv, rm, mkdir, touch, pwd, cd, find [-name] [-type], chmod, du [-h], ln
        Text: grep [-i][-n][-c][-v][-r], head [-n], tail [-n], wc [-l][-w][-c], sort [-r], uniq [-c][-d], sed 's/find/replace/[g]', tr [-d][-s] 'set1' 'set2', cut -d<delim> -f<fields> [-c<range>], diff
        System: echo [-n], env, export, which, clear, exit, help, date, sleep, test [-f][-d][-z][-n], basename, dirname, true, false
        Network: curl [-X method] [-d data] <url>, wget [-O file] <url>
        Node.js: node <file.js>, node -e "code", npm install/list/run/init
        Shell: VAR=val, $VAR, ${VAR}, &&, ||, |, >, >>, "quotes", 'quotes', #comments

        LIMITATIONS:
        - No fork/exec, git, ssh, tar — everything is built-in
        - Use write_file tool for reliable file writes (shell > redirect is session-scoped)
        - Pipes work with: grep, head, tail, wc, sort, uniq, sed, cut, tr, cat
        - Use && not ; for chaining commands
        - 75 tool calls max per turn
        """

        if withTools {
            prompt += "\nTOOLS: You have bash, read_file, write_file. Use them autonomously. Prefer write_file over echo > for creating files. Be concise — mobile screen."
        } else {
            prompt += "\nBe concise — mobile screen. Show exact commands. Infer intent from context."
        }

        return prompt
    }

    /// Auth: OAuth Bearer token or manual API key
    enum AuthMethod {
        case bearer(String)  // OAuth Pro/Max token
        case apiKey(String)  // Manual API key
    }

    func resolveAuth(apiKey: String) -> AuthMethod? {
        // OAuth token (Pro/Max subscription) takes priority
        if OAuthManager.shared.hasOAuthToken, let token = OAuthManager.shared.getToken() {
            return .bearer(token)
        }
        // Manual API key fallback
        if !apiKey.isEmpty {
            return .apiKey(apiKey)
        }
        return nil
    }

    private func applyAuth(_ auth: AuthMethod, to request: inout URLRequest) {
        switch auth {
        case .bearer(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .apiKey(let key):
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }
    }

    /// Send a message to Claude and get a response
    func sendMessage(prompt: String, apiKey: String, cwd: String,
                     directoryListing: String = "",
                     completion: @escaping (String) -> Void) {

        guard let auth = resolveAuth(apiKey: apiKey) else {
            completion("Error: No API key or OAuth token available. Configure in Settings.")
            return
        }

        // Add user message to history
        conversationHistory.append([
            "role": "user",
            "content": prompt
        ])

        // Keep history manageable (last 20 messages)
        if conversationHistory.count > 20 {
            conversationHistory = Array(conversationHistory.suffix(20))
        }

        let systemPrompt = buildSystemPrompt(cwd: cwd, directoryListing: directoryListing)

        // Build request
        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": conversationHistory
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody),
              let url = URL(string: apiURL) else {
            completion("Error: Failed to build API request")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(auth, to: &request)
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 120

        let semaphore = DispatchSemaphore(value: 0)
        var result = ""

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error = error {
                result = "Error: \(error.localizedDescription)"
                return
            }

            guard let data = data else {
                result = "Error: No response data"
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Check for API error
                    if let errorInfo = json["error"] as? [String: Any],
                       let message = errorInfo["message"] as? String {
                        result = "API Error: \(message)"
                        return
                    }

                    // Extract response text
                    if let content = json["content"] as? [[String: Any]],
                       let firstBlock = content.first,
                       let text = firstBlock["text"] as? String {
                        result = text

                        // Add assistant response to history
                        self.conversationHistory.append([
                            "role": "assistant",
                            "content": text
                        ])
                    } else {
                        result = "Error: Unexpected response format"
                    }
                }
            } catch {
                result = "Error: Failed to parse response — \(error.localizedDescription)"
            }
        }

        task.resume()
        semaphore.wait()
        completion(result)
    }

    /// Send a message with tools enabled; returns structured ClaudeResponse
    func sendMessageWithTools(prompt: String, apiKey: String, cwd: String,
                              directoryListing: String = "",
                              messages: [[String: Any]]? = nil) -> ClaudeResponse {

        guard let auth = resolveAuth(apiKey: apiKey) else {
            return .error("No API key or OAuth token available. Configure in Settings.")
        }

        // Use provided messages or build from prompt
        var messageList: [[String: Any]]
        if let messages = messages {
            messageList = messages
        } else {
            messageList = conversationHistory
            messageList.append([
                "role": "user",
                "content": prompt
            ])
        }

        let systemPrompt = buildSystemPrompt(cwd: cwd, directoryListing: directoryListing, withTools: true)

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": messageList,
            "tools": ToolDefinitions.allTools
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody),
              let url = URL(string: apiURL) else {
            return .error("Failed to build API request")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(auth, to: &request)
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 120

        let semaphore = DispatchSemaphore(value: 0)
        var result: ClaudeResponse = .error("No response")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            if let error = error {
                result = .error(error.localizedDescription)
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                result = .error("No response data")
                return
            }

            if let errorInfo = json["error"] as? [String: Any],
               let message = errorInfo["message"] as? String {
                result = .error("API Error: \(message)")
                return
            }

            guard let content = json["content"] as? [[String: Any]] else {
                result = .error("Unexpected response format")
                return
            }

            var textParts: [String] = []
            var toolUses: [(id: String, name: String, input: [String: Any])] = []

            for block in content {
                if let type = block["type"] as? String {
                    if type == "text", let text = block["text"] as? String {
                        textParts.append(text)
                    } else if type == "tool_use",
                              let id = block["id"] as? String,
                              let name = block["name"] as? String,
                              let input = block["input"] as? [String: Any] {
                        toolUses.append((id: id, name: name, input: input))
                    }
                }
            }

            // Store the raw assistant content for conversation history
            self.conversationHistory = messageList
            self.conversationHistory.append([
                "role": "assistant",
                "content": content
            ])

            if !toolUses.isEmpty && !textParts.isEmpty {
                result = .mixed(text: textParts.joined(separator: "\n"), toolUses: toolUses)
            } else if toolUses.count > 1 {
                // Multiple tool uses, no text — use mixed with empty text
                result = .mixed(text: "", toolUses: toolUses)
            } else if toolUses.count == 1 {
                result = .toolUse(id: toolUses[0].id, name: toolUses[0].name, input: toolUses[0].input)
            } else {
                result = .text(textParts.joined(separator: "\n"))
            }
        }

        task.resume()
        semaphore.wait()
        return result
    }

    /// Append a tool result to conversation history
    func appendToolResult(toolUseId: String, result: String) {
        conversationHistory.append([
            "role": "user",
            "content": [
                [
                    "type": "tool_result",
                    "tool_use_id": toolUseId,
                    "content": result
                ] as [String: Any]
            ]
        ])
    }

    /// Clear conversation history
    func clearHistory() {
        conversationHistory.removeAll()
    }
}
