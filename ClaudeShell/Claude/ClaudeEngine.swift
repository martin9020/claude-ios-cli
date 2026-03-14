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

        if withTools {
            prompt += """


            TOOL USE:
            You have access to tools: bash, read_file, write_file.
            Use them to accomplish the user's request autonomously.
            - Use bash to run shell commands (ls, cat, grep, mkdir, echo, etc.)
            - Use read_file to read file contents
            - Use write_file to create or modify files
            - Execute multiple steps as needed to complete the task
            - When done, provide a summary of what you did
            """
        } else {
            prompt += """


            AVAILABLE SHELL COMMANDS:
            Filesystem: ls, cat, cp, mv, rm, mkdir, touch, pwd, cd, find, chmod, du, ln
            Text: grep, head, tail, wc, sort, uniq, sed, tr, cut, diff
            System: echo, env, export, which, clear, exit, help, date, sleep, test, basename, dirname
            Network: curl, wget

            HOW TO RESPOND:
            - Be concise — this is a mobile screen
            - When the user wants to create or edit files, show the exact shell commands to run
            - Use echo with redirect or cat heredoc patterns to write files
            - When asked to review or explain code, give focused feedback
            - When asked to do a task, break it into shell commands the user can run
            - If you suggest commands, format them clearly so the user can copy them
            - Infer intent: "review X" = code review, "edit X" = suggest changes, "explain X" = explain
            - You can read file contents provided in the context to give informed answers
            """
        }

        return prompt
    }

    /// Resolve API key — OAuth (stored as API key after creation) or manual API key
    func resolveApiKey(apiKey: String) -> String? {
        // OAuth flow creates a real API key and stores it in keychainAccessToken
        if let oauthKey = OAuthManager.shared.getToken() {
            return oauthKey
        }
        if !apiKey.isEmpty {
            return apiKey
        }
        return nil
    }

    /// Send a message to Claude and get a response
    func sendMessage(prompt: String, apiKey: String, cwd: String,
                     directoryListing: String = "",
                     completion: @escaping (String) -> Void) {

        guard let resolvedKey = resolveApiKey(apiKey: apiKey) else {
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
        request.setValue(resolvedKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2024-10-22", forHTTPHeaderField: "anthropic-version")
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

        guard let resolvedKey = resolveApiKey(apiKey: apiKey) else {
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
        request.setValue(resolvedKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2024-10-22", forHTTPHeaderField: "anthropic-version")
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
