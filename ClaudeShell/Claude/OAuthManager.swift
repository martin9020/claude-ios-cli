import Foundation
import AuthenticationServices
import CryptoKit
import Security
import Network

/// Manages OAuth PKCE authentication with Anthropic for Claude Pro/Max subscriptions.
/// Uses a local HTTP server for the redirect URI (same approach as Claude Code CLI).
class OAuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthManager()

    @Published var isSignedIn: Bool = false
    @Published var isLoading: Bool = false
    @Published var statusMessage: String = ""

    private let tokenEndpoint = "https://platform.claude.com/v1/oauth/token"
    private let authorizeEndpoint = "https://claude.ai/oauth/authorize"

    /// Official Claude Code OAuth client_id (from @anthropic-ai/claude-code npm package)
    private let officialClientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    // Keychain keys
    private let keychainAccessToken = "com.claudeshell.oauth.accessToken"
    private let keychainRefreshToken = "com.claudeshell.oauth.refreshToken"
    private let keychainTokenExpiry = "com.claudeshell.oauth.tokenExpiry"
    private let keychainClientId = "com.claudeshell.oauth.clientId"

    private var codeVerifier: String?
    private var localServer: NWListener?
    private var serverPort: UInt16 = 0

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

    // MARK: - OAuth PKCE Flow with Local HTTP Server

    func startOAuthFlow(from window: UIWindow? = nil) {
        guard let clientId = extractClientId() else {
            statusMessage = "Could not get OAuth client_id"
            return
        }

        isLoading = true
        statusMessage = "Starting login server..."

        // Start local HTTP server to receive the OAuth callback
        startLocalServer { [weak self] port in
            guard let self = self, let port = port else {
                DispatchQueue.main.async {
                    self?.statusMessage = "Failed to start local server"
                    self?.isLoading = false
                }
                return
            }

            self.serverPort = port
            let redirectUri = "http://localhost:\(port)/oauth/callback"

            // Generate PKCE
            let verifier = self.generateCodeVerifier()
            self.codeVerifier = verifier
            let challenge = self.generateCodeChallenge(from: verifier)
            let state = self.generateCodeVerifier()

            // Build authorize URL
            let scope = "user:inference%20user:sessions:claude_code"
            let encodedRedirect = redirectUri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            let queryString = [
                "client_id=\(clientId)",
                "response_type=code",
                "redirect_uri=\(encodedRedirect)",
                "code_challenge=\(challenge)",
                "code_challenge_method=S256",
                "scope=\(scope)",
                "state=\(state)"
            ].joined(separator: "&")

            var components = URLComponents(string: self.authorizeEndpoint)!
            components.percentEncodedQuery = queryString

            guard let authURL = components.url else {
                DispatchQueue.main.async {
                    self.statusMessage = "Failed to build auth URL"
                    self.isLoading = false
                }
                return
            }

            DispatchQueue.main.async {
                self.statusMessage = "Opening login..."
                self.openAuthInBrowser(url: authURL, clientId: clientId, redirectUri: redirectUri)
            }
        }
    }

    /// Open the auth URL using ASWebAuthenticationSession with http scheme
    private func openAuthInBrowser(url: URL, clientId: String, redirectUri: String) {
        // Use ASWebAuthenticationSession — it will show the in-app browser
        // We use "http" as callback scheme so it intercepts the localhost redirect
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "http"
        ) { [weak self] callbackURL, error in
            guard let self = self else { return }
            self.stopLocalServer()

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

                self.exchangeCodeForTokens(code: code, clientId: clientId, redirectUri: redirectUri)
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
    }

    // MARK: - Local HTTP Server

    private func startLocalServer(completion: @escaping (UInt16?) -> Void) {
        // Use NWListener to create a TCP server on a random available port
        let params = NWParameters.tcp
        guard let listener = try? NWListener(using: params, on: .any) else {
            completion(nil)
            return
        }

        self.localServer = listener

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let port = listener.port?.rawValue {
                    completion(port)
                } else {
                    completion(nil)
                }
            case .failed:
                completion(nil)
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.start(queue: DispatchQueue.global(qos: .userInitiated))
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let data = data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            // Send a simple success response
            let html = """
            <html><head><title>ClaudeShell</title></head>
            <body style="font-family:system-ui;text-align:center;padding:60px">
            <h1>Authorization successful!</h1>
            <p>You can close this window and return to ClaudeShell.</p>
            </body></html>
            """
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
                connection.cancel()
            }))

            // We don't need to extract the code here — ASWebAuthenticationSession
            // intercepts the redirect URL before it reaches our server
            _ = request // suppress unused warning
        }
    }

    private func stopLocalServer() {
        localServer?.cancel()
        localServer = nil
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
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectUri,
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
