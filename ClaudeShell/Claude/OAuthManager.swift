import Foundation
import AuthenticationServices
import CryptoKit
import Security

/// Manages OAuth PKCE authentication with Anthropic for Claude Pro/Max subscriptions.
/// Implements the exact same OAuth flow as Claude Code CLI (from source).
class OAuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthManager()

    @Published var isSignedIn: Bool = false
    @Published var isLoading: Bool = false
    @Published var statusMessage: String = ""
    @Published var awaitingCode: Bool = false

    // Endpoints — exact values from Claude Code source (d2A config object)
    private let authorizeEndpoint = "https://platform.claude.com/oauth/authorize"
    private let tokenEndpoint = "https://platform.claude.com/v1/oauth/token"
    private let manualRedirectUri = "https://platform.claude.com/oauth/code/callback"
    private let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    // Full scopes from Claude Code source (ed1 array)
    private let scopes = "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"

    // Keychain keys
    private let keychainAccessToken = "com.claudeshell.oauth.accessToken"
    private let keychainRefreshToken = "com.claudeshell.oauth.refreshToken"
    private let keychainTokenExpiry = "com.claudeshell.oauth.tokenExpiry"

    // PKCE state
    private var codeVerifier: String?
    private var oauthState: String?

    override init() {
        super.init()
        isSignedIn = loadFromKeychain(key: keychainAccessToken) != nil
    }

    // MARK: - OAuth Flow (matches Claude Code CLI buildAuthUrl + by8 functions)

    func startOAuthFlow(from window: UIWindow? = nil) {
        isLoading = true
        statusMessage = "Opening login..."

        // Generate PKCE values
        let verifier = generateCodeVerifier()
        self.codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)
        let state = generateCodeVerifier()
        self.oauthState = state

        // Build authorize URL matching JavaScript URLSearchParams encoding exactly.
        // JS encodes : as %3A and spaces as + which differs from Swift's URLQueryItem.
        // The server may do exact-match on redirect_uri including encoding.
        let params = [
            ("code", "true"),
            ("client_id", clientId),
            ("response_type", "code"),
            ("redirect_uri", manualRedirectUri),
            ("scope", scopes),
            ("code_challenge", challenge),
            ("code_challenge_method", "S256"),
            ("state", state)
        ].map { key, value in
            "\(formEncode(key))=\(formEncode(value))"
        }.joined(separator: "&")

        guard let authURL = URL(string: "\(authorizeEndpoint)?\(params)") else {
            statusMessage = "Failed to build auth URL"
            isLoading = false
            return
        }

        // Open in browser — use a callback scheme that won't match anything
        // so the user stays on the page and sees the auth code to copy
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "claudeshell-none"
        ) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                self.awaitingCode = true
                self.statusMessage = "Paste the authorization code from the browser"
            }
        }

        session.presentationContextProvider = self
        // Share cookies with Safari — allows auto-login if already signed in
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    /// Called when user pastes the authorization code
    func submitAuthCode(_ code: String) {
        let cleanCode = extractCode(from: code)
        guard !cleanCode.isEmpty else {
            statusMessage = "Please enter a valid code"
            return
        }
        guard codeVerifier != nil else {
            statusMessage = "Auth session expired — tap Sign In again"
            return
        }

        isLoading = true
        awaitingCode = false
        statusMessage = "Exchanging code..."
        exchangeCodeForTokens(code: cleanCode)
    }

    /// Extract the authorization code from whatever the user pasted.
    /// Handles: plain code, full callback URL, URL-encoded code, extra whitespace.
    private func extractCode(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // If it looks like a URL with a code parameter, extract it
        if trimmed.contains("code=") {
            if let components = URLComponents(string: trimmed),
               let codeParam = components.queryItems?.first(where: { $0.name == "code" })?.value {
                return codeParam.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Fallback: regex extract after "code="
            if let range = trimmed.range(of: "code=") {
                let afterCode = String(trimmed[range.upperBound...])
                let code = afterCode.components(separatedBy: "&").first ?? afterCode
                return code.removingPercentEncoding?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? code.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // URL-decode if needed
        return trimmed.removingPercentEncoding ?? trimmed
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }

    // MARK: - Token Exchange (exact copy of Claude Code's by8 function)
    // Source: X8.post(P7().TOKEN_URL, w, {headers:{"Content-Type":"application/json"}, timeout:15000})

    private func exchangeCodeForTokens(code: String) {
        guard let verifier = codeVerifier, let state = oauthState else {
            statusMessage = "Missing PKCE state"
            isLoading = false
            return
        }

        guard let url = URL(string: tokenEndpoint) else {
            statusMessage = "Invalid token endpoint"
            isLoading = false
            return
        }

        // Exact body from by8(): {grant_type, code, redirect_uri, client_id, code_verifier, state}
        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": manualRedirectUri,
            "client_id": clientId,
            "code_verifier": verifier,
            "state": state
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false

                if let error = error {
                    self.statusMessage = "Network error: \(error.localizedDescription)"
                    return
                }

                let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0

                guard let data = data else {
                    self.statusMessage = "No response (HTTP \(httpStatus))"
                    return
                }

                // Try to parse response
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    let raw = String(data: data, encoding: .utf8) ?? "binary"
                    self.statusMessage = "Bad response (HTTP \(httpStatus)): \(String(raw.prefix(200)))"
                    return
                }

                // Check for errors — Anthropic format: {error: {type, message}}
                if let errorDict = json["error"] as? [String: Any],
                   let message = errorDict["message"] as? String {
                    self.statusMessage = "Auth error: \(message)"
                    // Don't clear verifier — user can try again with new code
                    self.awaitingCode = true
                    return
                }
                if let errorStr = json["error"] as? String {
                    let desc = json["error_description"] as? String ?? errorStr
                    self.statusMessage = "Auth error: \(desc)"
                    self.awaitingCode = true
                    return
                }

                // Check for HTTP error
                if httpStatus != 200 {
                    self.statusMessage = "HTTP \(httpStatus): \(json)"
                    self.awaitingCode = true
                    return
                }

                // Success — extract tokens
                guard let accessToken = json["access_token"] as? String else {
                    let keys = json.keys.joined(separator: ", ")
                    self.statusMessage = "No access_token in response (keys: \(keys))"
                    return
                }

                // Clear PKCE state
                self.codeVerifier = nil
                self.oauthState = nil

                // Store tokens
                self.saveToKeychain(key: self.keychainAccessToken, value: accessToken)
                if let refresh = json["refresh_token"] as? String {
                    self.saveToKeychain(key: self.keychainRefreshToken, value: refresh)
                }
                let expiresIn = json["expires_in"] as? Int ?? 28800
                let expiry = Date().addingTimeInterval(TimeInterval(expiresIn)).timeIntervalSince1970
                self.saveToKeychain(key: self.keychainTokenExpiry,
                                   value: String(format: "%.0f", expiry))

                self.isSignedIn = true
                self.statusMessage = "Signed in successfully!"
            }
        }.resume()
    }

    // MARK: - Token Refresh (exact copy of Claude Code's QQ6 function)
    // Source: X8.post(P7().TOKEN_URL, K, {headers:{"Content-Type":"application/json"}, timeout:15000})

    func getToken() -> String? {
        guard let token = loadFromKeychain(key: keychainAccessToken) else { return nil }
        if isTokenExpired() {
            let semaphore = DispatchSemaphore(value: 0)
            var refreshedToken: String?
            refreshToken { newToken in
                refreshedToken = newToken
                semaphore.signal()
            }
            semaphore.wait()
            return refreshedToken
        }
        return token
    }

    private func isTokenExpired() -> Bool {
        guard let expiryStr = loadFromKeychain(key: keychainTokenExpiry),
              let expiry = Double(expiryStr) else { return true }
        return Date().timeIntervalSince1970 > (expiry - 300)
    }

    func refreshToken(completion: @escaping (String?) -> Void) {
        guard let refresh = loadFromKeychain(key: keychainRefreshToken),
              let url = URL(string: tokenEndpoint) else {
            DispatchQueue.main.async {
                self.isSignedIn = false
                self.statusMessage = "Session expired — please sign in again"
            }
            completion(nil)
            return
        }

        // Exact body from QQ6(): {grant_type, refresh_token, client_id, scope}
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientId,
            "scope": scopes
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { completion(nil); return }

            guard error == nil, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newToken = json["access_token"] as? String else {
                DispatchQueue.main.async {
                    self.isSignedIn = false
                    self.statusMessage = "Token refresh failed — please sign in again"
                }
                completion(nil)
                return
            }

            self.saveToKeychain(key: self.keychainAccessToken, value: newToken)
            if let newRefresh = json["refresh_token"] as? String {
                self.saveToKeychain(key: self.keychainRefreshToken, value: newRefresh)
            }
            let expiresIn = json["expires_in"] as? Int ?? 28800
            let expiry = Date().addingTimeInterval(TimeInterval(expiresIn)).timeIntervalSince1970
            self.saveToKeychain(key: self.keychainTokenExpiry,
                               value: String(format: "%.0f", expiry))
            DispatchQueue.main.async { self.isSignedIn = true }
            completion(newToken)
        }.resume()
    }

    func signOut() {
        deleteFromKeychain(key: keychainAccessToken)
        deleteFromKeychain(key: keychainRefreshToken)
        deleteFromKeychain(key: keychainTokenExpiry)
        codeVerifier = nil
        oauthState = nil
        isSignedIn = false
        awaitingCode = false
        statusMessage = "Signed out"
    }

    // MARK: - URL Encoding (matches JavaScript URLSearchParams)

    /// Encodes a string the same way JavaScript's URLSearchParams does:
    /// spaces → +, and encodes : / @ etc. (more aggressive than RFC 3986 query encoding)
    private func formEncode(_ string: String) -> String {
        // Only unreserved chars are left unencoded: A-Z a-z 0-9 - _ . * and space→+
        var allowed = CharacterSet()
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.*")
        return string.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? string
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded()
    }

    // MARK: - Keychain

    private func saveToKeychain(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
