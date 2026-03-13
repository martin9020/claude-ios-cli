import Foundation

/// Handles communication with the Claude API (Anthropic Messages API)
class ClaudeEngine {
    static let shared = ClaudeEngine()

    private let apiURL = "https://api.anthropic.com/v1/messages"
    private let model = "claude-sonnet-4-20250514"
    private var conversationHistory: [[String: Any]] = []

    /// System prompt for Claude when used inside ClaudeShell
    private let systemPrompt = """
    You are Claude, running inside ClaudeShell on an iOS device.
    You are a coding assistant with access to a sandboxed Linux-like environment.

    The user can execute shell commands in this environment. Available commands include:
    ls, cat, cp, mv, rm, mkdir, touch, pwd, cd, find, grep, head, tail, wc, sort,
    sed, cut, diff, echo, env, curl, wget, and more.

    When the user asks you to perform tasks:
    - Provide shell commands they can run
    - Write code and save it to files
    - Help debug issues
    - Explain code and concepts

    Keep responses concise since this runs on a mobile device.
    Use the available shell commands when suggesting solutions.
    """

    /// Send a message to Claude and get a response
    func sendMessage(prompt: String, apiKey: String, cwd: String,
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

        // Build request
        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt + "\n\nCurrent directory: \(cwd)",
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
