import Foundation

/// Handles communication with the Claude API (Anthropic Messages API)
class ClaudeEngine {
    static let shared = ClaudeEngine()

    private let apiURL = "https://api.anthropic.com/v1/messages"
    private let model = "claude-sonnet-4-20250514"
    private(set) var conversationHistory: [[String: Any]] = []

    /// Number of messages in history
    var historyCount: Int { conversationHistory.count }

    /// System prompt for Claude when used inside ClaudeShell
    private func buildSystemPrompt(cwd: String, directoryListing: String) -> String {
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

        return prompt
    }

    /// Send a message to Claude and get a response
    func sendMessage(prompt: String, apiKey: String, cwd: String,
                     directoryListing: String = "",
                     completion: @escaping (String) -> Void) {

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
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
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

    /// Clear conversation history
    func clearHistory() {
        conversationHistory.removeAll()
    }
}
