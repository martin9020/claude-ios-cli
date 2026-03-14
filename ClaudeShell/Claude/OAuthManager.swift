import Foundation
import AuthenticationServices
import CryptoKit
import Security

/// Manages OAuth PKCE authentication with Anthropic for Claude Pro/Max subscriptions
class OAuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthManager()

    @Published var isSignedIn: Bool = false
    @Published var isLoading: Bool = false
    @Published var statusMessage: String = ""

    private let tokenEndpoint = "https://platform.claude.com/v1/oauth/token"
    private let authorizeEndpoint = "https://platform.claude.com/oauth/authorize"
    private let callbackScheme = "claudeshell"

    /// Official Claude Code OAuth client_id (from @anthropic-ai/claude-code npm package)
    private let officialClientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    // Keychain keys
    private let keychainAccessToken = "com.claudeshell.oauth.accessToken"
    private let keychainRefreshToken = "com.claudeshell.oauth.refreshToken"
    private let keychainTokenExpiry = "com.claudeshell.oauth.tokenExpiry"
    private let keychainClientId = "com.claudeshell.oauth.clientId"

    private var codeVerifier: String?

    override init() {
        super.init()
        // Check if we have stored tokens
        isSignedIn = loadFromKeychain(key: keychainAccessToken) != nil
    }

    // MARK: - Client ID Extraction

    /// Get the OAuth client_id — uses the official hardcoded value from Claude Code,
    /// or falls back to keychain/env override
    func extractClientId() -> String? {
        // Check for env override first (CLAUDE_CODE_OAUTH_CLIENT_ID)
        if let cached = loadFromKeychain(key: keychainClientId) {
            return cached
        }
        // Use the official client_id from the Claude Code npm package
        saveToKeychain(key: keychainClientId, value: officialClientId)
        return officialClientId
    }

    // MARK: - OAuth PKCE Flow

    /// Start the OAuth PKCE authentication flow
    func startOAuthFlow(from window: UIWindow? = nil) {
        guard let clientId = extractClientId() else {
            statusMessage = "Could not get OAuth client_id"
            return
        }

        isLoading = true
        statusMessage = "Opening login..."

        // Generate PKCE code verifier (43-128 chars, URL-safe)
        let verifier = generateCodeVerifier()
        self.codeVerifier = verifier

        // Compute code_challenge = base64url(SHA256(verifier))
        let challenge = generateCodeChallenge(from: verifier)

        // Build authorize URL
        var components = URLComponents(string: authorizeEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: "\(callbackScheme)://oauth/callback"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "scope", value: "user:inference")
        ]

        guard let authURL = components.url else {
            statusMessage = "Failed to build auth URL"
            isLoading = false
            return
        }

        // Use ASWebAuthenticationSession for secure browser-based login
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: callbackScheme
        ) { [weak self] callbackURL, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if let error = error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        self.statusMessage = "Login cancelled"
                    } else {
                        self.statusMessage = "Login error: \(error.localizedDescription)"
                    }
                    self.isLoading = false
                    return
                }

                guard let callbackURL = callbackURL,
                      let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "code" })?.value else {
                    self.statusMessage = "No auth code received"
                    self.isLoading = false
                    return
                }

                // Exchange code for tokens
                self.exchangeCodeForTokens(code: code, clientId: clientId)
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    /// ASWebAuthenticationPresentationContextProviding
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }

    // MARK: - Token Exchange

    /// Exchange auth code for access + refresh tokens
    private func exchangeCodeForTokens(code: String, clientId: String) {
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
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": "\(callbackScheme)://oauth/callback",
            "client_id": clientId,
            "code_verifier": verifier
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

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
                    self.statusMessage = "Invalid token response"
                    return
                }

                if let errorMsg = json["error_description"] as? String ?? json["error"] as? String {
                    self.statusMessage = "Auth error: \(errorMsg)"
                    return
                }

                guard let accessToken = json["access_token"] as? String else {
                    self.statusMessage = "No access token in response"
                    return
                }

                // Store tokens
                self.saveToKeychain(key: self.keychainAccessToken, value: accessToken)

                if let refreshToken = json["refresh_token"] as? String {
                    self.saveToKeychain(key: self.keychainRefreshToken, value: refreshToken)
                }

                // Store expiry (default 8 hours)
                let expiresIn = json["expires_in"] as? Int ?? 28800
                let expiry = Date().addingTimeInterval(TimeInterval(expiresIn))
                    .timeIntervalSince1970
                self.saveToKeychain(key: self.keychainTokenExpiry,
                                   value: String(format: "%.0f", expiry))

                self.isSignedIn = true
                self.statusMessage = "Signed in successfully!"
            }
        }.resume()
    }

    // MARK: - Token Management

    /// Get current valid access token (refreshes if expired)
    func getToken() -> String? {
        guard let token = loadFromKeychain(key: keychainAccessToken) else {
            return nil
        }

        // Check if token is expired
        if isTokenExpired() {
            // Try to refresh
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

    /// Check if the access token is expired
    private func isTokenExpired() -> Bool {
        guard let expiryStr = loadFromKeychain(key: keychainTokenExpiry),
              let expiry = Double(expiryStr) else {
            return true
        }
        // Refresh 5 minutes before actual expiry
        return Date().timeIntervalSince1970 > (expiry - 300)
    }

    /// Refresh the access token using the refresh token
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
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

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

            DispatchQueue.main.async {
                self.isSignedIn = true
            }

            completion(newAccessToken)
        }.resume()
    }

    /// Sign out — remove all stored tokens
    func signOut() {
        deleteFromKeychain(key: keychainAccessToken)
        deleteFromKeychain(key: keychainRefreshToken)
        deleteFromKeychain(key: keychainTokenExpiry)
        isSignedIn = false
        statusMessage = "Signed out"
    }

    // MARK: - PKCE Helpers

    /// Generate a random code verifier (43-128 URL-safe chars)
    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    /// Generate code challenge from verifier: base64url(SHA256(verifier))
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

// MARK: - Data Extension for base64url encoding

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
