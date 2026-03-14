import Foundation
import AuthenticationServices
import CryptoKit
import Security

/// Manages OAuth PKCE authentication with Anthropic for Claude Pro/Max subscriptions.
/// Uses a local HTTP server for the redirect URI (same approach as Claude Code CLI).
class OAuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthManager()

    @Published var isSignedIn: Bool = false
    @Published var isLoading: Bool = false
    @Published var statusMessage: String = ""

    private let tokenEndpoint = "https://platform.claude.com/v1/oauth/token"
    private let authorizeEndpoint = "https://claude.ai/oauth/authorize"
    /// Manual redirect — shows auth code on screen for user to copy
    private let manualRedirectUri = "https://platform.claude.com/oauth/code/callback"

    /// Official Claude Code OAuth client_id (from @anthropic-ai/claude-code npm package)
    private let officialClientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    // Keychain keys
    private let keychainAccessToken = "com.claudeshell.oauth.accessToken"
    private let keychainRefreshToken = "com.claudeshell.oauth.refreshToken"
    private let keychainTokenExpiry = "com.claudeshell.oauth.tokenExpiry"
    private let keychainClientId = "com.claudeshell.oauth.clientId"

    private var codeVerifier: String?
    /// Pending client ID for code exchange after user pastes auth code
    private var pendingClientId: String?

    override init() {
        super.init()
        isSignedIn = loadFromKeychain(key: keychainAccessToken) != nil
    }

    // MARK: - Client ID

    func extractClientId() -> String? {
        if let cached = loadFromKeychain(key: keychainClientId) {
            return cached
        }
        saveToKeychain(key: keychainClientId, value: officialClientId)
        return officialClientId
    }

    // MARK: - OAuth PKCE Flow (Manual Code Entry)

    /// Whether we're waiting for the user to paste an auth code
    @Published var awaitingCode: Bool = false

    func startOAuthFlow(from window: UIWindow? = nil) {
        guard let clientId = extractClientId() else {
            statusMessage = "Could not get OAuth client_id"
            return
        }

        isLoading = true
        statusMessage = "Opening login..."
        pendingClientId = clientId

        // Generate PKCE
        let verifier = generateCodeVerifier()
        self.codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)
        let state = generateCodeVerifier()

        // Build authorize URL with manual redirect (shows code on screen)
        let encodedRedirect = manualRedirectUri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let scope = "user:inference%20user:sessions:claude_code"
        let queryString = [
            "client_id=\(clientId)",
            "response_type=code",
            "redirect_uri=\(encodedRedirect)",
            "code_challenge=\(challenge)",
            "code_challenge_method=S256",
            "scope=\(scope)",
            "state=\(state)"
        ].joined(separator: "&")

        var components = URLComponents(string: authorizeEndpoint)!
        components.percentEncodedQuery = queryString

        guard let authURL = components.url else {
            statusMessage = "Failed to build auth URL"
            isLoading = false
            return
        }

        // Open in browser
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "claudeshell-none" // won't match — user will see code on screen
        ) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Browser was dismissed — user should now paste the code
                self.isLoading = false
                self.awaitingCode = true
                self.statusMessage = "Paste the authorization code from the browser"
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    /// Called when user pastes the authorization code from the browser
    func submitAuthCode(_ code: String) {
        guard let clientId = pendingClientId else {
            statusMessage = "No pending auth flow"
            return
        }

        isLoading = true
        awaitingCode = false
        statusMessage = "Exchanging code..."
        exchangeCodeForTokens(code: code, clientId: clientId, redirectUri: manualRedirectUri)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }

    // MARK: - Token Exchange

    private func exchangeCodeForTokens(code: String, clientId: String, redirectUri: String) {
        guard let verifier = codeVerifier else {
            statusMessage = "Missing code verifier"
            isLoading = false
            return
        }

        guard let url = URL(string: tokenEndpoint) else {
            statusMessage = "Invalid token endpoint"
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Build form body using URLComponents for correct percent encoding
        var formComponents = URLComponents()
        formComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]
        // URLComponents.query percent-encodes values correctly for form bodies
        // But it encodes space as + which is fine for form-urlencoded
        request.httpBody = formComponents.percentEncodedQuery?.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                self.codeVerifier = nil

                if let error = error {
                    self.statusMessage = "Token error: \(error.localizedDescription)"
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    // Show raw response for debugging
                    let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? "no data"
                    self.statusMessage = "Invalid response: \(String(raw.prefix(200)))"
                    return
                }

                // Handle errors — Anthropic returns {type, error: {type, message}, request_id}
                if let errorDict = json["error"] as? [String: Any],
                   let message = errorDict["message"] as? String {
                    self.statusMessage = "Auth error: \(message)"
                    return
                }
                if let errorMsg = json["error_description"] as? String ?? json["error"] as? String {
                    self.statusMessage = "Auth error: \(errorMsg)"
                    return
                }

                guard let accessToken = json["access_token"] as? String else {
                    let raw = String(data: data, encoding: .utf8) ?? "unknown"
                    self.statusMessage = "Failed: \(String(raw.prefix(300)))"
                    return
                }

                self.saveToKeychain(key: self.keychainAccessToken, value: accessToken)

                if let refreshToken = json["refresh_token"] as? String {
                    self.saveToKeychain(key: self.keychainRefreshToken, value: refreshToken)
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

    // MARK: - Token Management

    func getToken() -> String? {
        guard let token = loadFromKeychain(key: keychainAccessToken) else {
            return nil
        }
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
              let expiry = Double(expiryStr) else {
            return true
        }
        return Date().timeIntervalSince1970 > (expiry - 300)
    }

    func refreshToken(completion: @escaping (String?) -> Void) {
        guard let refreshToken = loadFromKeychain(key: keychainRefreshToken),
              let clientId = loadFromKeychain(key: keychainClientId),
              let url = URL(string: tokenEndpoint) else {
            DispatchQueue.main.async {
                self.isSignedIn = false
                self.statusMessage = "Session expired — please sign in again"
            }
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var formComponents = URLComponents()
        formComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: clientId)
        ]
        request.httpBody = formComponents.percentEncodedQuery?.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { completion(nil); return }

            guard error == nil, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccessToken = json["access_token"] as? String else {
                DispatchQueue.main.async {
                    self.isSignedIn = false
                    self.statusMessage = "Token refresh failed — please sign in again"
                }
                completion(nil)
                return
            }

            self.saveToKeychain(key: self.keychainAccessToken, value: newAccessToken)
            if let newRefresh = json["refresh_token"] as? String {
                self.saveToKeychain(key: self.keychainRefreshToken, value: newRefresh)
            }
            let expiresIn = json["expires_in"] as? Int ?? 28800
            let expiry = Date().addingTimeInterval(TimeInterval(expiresIn)).timeIntervalSince1970
            self.saveToKeychain(key: self.keychainTokenExpiry,
                               value: String(format: "%.0f", expiry))
            DispatchQueue.main.async { self.isSignedIn = true }
            completion(newAccessToken)
        }.resume()
    }

    func signOut() {
        deleteFromKeychain(key: keychainAccessToken)
        deleteFromKeychain(key: keychainRefreshToken)
        deleteFromKeychain(key: keychainTokenExpiry)
        isSignedIn = false
        statusMessage = "Signed out"
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncoded()
    }

    // MARK: - Keychain Helpers

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
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
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
