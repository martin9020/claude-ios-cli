import Foundation
import AuthenticationServices
import CryptoKit
import Security

/// OAuth PKCE auth for Claude Pro/Max subscriptions.
/// Flow: claude.ai authorize → get code → exchange for token → use as Bearer.
class OAuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthManager()

    @Published var isSignedIn: Bool = false
    @Published var isLoading: Bool = false
    @Published var statusMessage: String = ""
    @Published var awaitingCode: Bool = false

    // Claude Code source endpoints
    private let authorizeEndpoint = "https://claude.ai/oauth/authorize"
    private let tokenEndpoint = "https://platform.claude.com/v1/oauth/token"
    private let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let redirectUri = "https://platform.claude.com/oauth/code/callback"

    // Pro/Max scopes — user:inference for API access
    private let scopes = "user:inference user:profile user:sessions:claude_code"

    // Keychain
    private let kAccessToken = "com.claudeshell.oauth.accessToken"
    private let kRefreshToken = "com.claudeshell.oauth.refreshToken"
    private let kTokenExpiry = "com.claudeshell.oauth.tokenExpiry"

    private var codeVerifier: String?
    private var oauthState: String?

    override init() {
        super.init()
        isSignedIn = loadKeychain(kAccessToken) != nil
    }

    // MARK: - Public API

    /// Get the current OAuth token (refreshes if expired)
    func getToken() -> String? {
        guard let token = loadKeychain(kAccessToken) else { return nil }
        if isExpired() {
            var refreshed: String?
            let sem = DispatchSemaphore(value: 0)
            doRefresh { refreshed = $0; sem.signal() }
            sem.wait()
            return refreshed
        }
        return token
    }

    /// Whether we have an OAuth token (vs API key)
    var hasOAuthToken: Bool {
        loadKeychain(kAccessToken) != nil && isSignedIn
    }

    // MARK: - OAuth Flow

    func startOAuthFlow(from window: UIWindow? = nil) {
        isLoading = true
        statusMessage = "Opening login..."

        let verifier = randomBase64URL()
        codeVerifier = verifier
        let challenge = sha256Base64URL(verifier)
        let state = randomBase64URL()
        oauthState = state

        var c = URLComponents(string: authorizeEndpoint)!
        c.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let url = c.url else {
            statusMessage = "Failed to build URL"
            isLoading = false
            return
        }

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "claudeshell-none") { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.isLoading = false
                self?.awaitingCode = true
                self?.statusMessage = "Paste the code from the browser"
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    func submitAuthCode(_ input: String) {
        // Extract code — strip URL fragment (#...) and query params
        var code = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.contains("code=") {
            if let r = code.range(of: "code=") {
                code = String(code[r.upperBound...])
                if let a = code.firstIndex(of: "&") { code = String(code[..<a]) }
            }
        }
        if let h = code.firstIndex(of: "#") { code = String(code[..<h]) }
        code = code.removingPercentEncoding ?? code
        code = code.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !code.isEmpty else { statusMessage = "Empty code"; return }
        guard codeVerifier != nil else { statusMessage = "Session expired — sign in again"; return }

        isLoading = true
        awaitingCode = false
        statusMessage = "Exchanging code (\(code.count) chars)..."
        exchangeCode(code)
    }

    func signOut() {
        deleteKeychain(kAccessToken)
        deleteKeychain(kRefreshToken)
        deleteKeychain(kTokenExpiry)
        codeVerifier = nil
        oauthState = nil
        isSignedIn = false
        awaitingCode = false
        UserDefaults.standard.set("", forKey: "anthropic_api_key")
        statusMessage = "Signed out"
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    // MARK: - Token Exchange

    private func exchangeCode(_ code: String) {
        guard let verifier = codeVerifier, let state = oauthState,
              let url = URL(string: tokenEndpoint) else {
            statusMessage = "Missing auth state"
            isLoading = false
            return
        }

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectUri,
            "client_id": clientId,
            "code_verifier": verifier,
            "state": state
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            DispatchQueue.main.async { self?.handleTokenResponse(data, resp, err) }
        }.resume()
    }

    private func handleTokenResponse(_ data: Data?, _ resp: URLResponse?, _ err: Error?) {
        isLoading = false

        if let err = err { statusMessage = "Network: \(err.localizedDescription)"; return }

        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            statusMessage = "Bad response"
            return
        }

        if let e = json["error"] as? [String: Any], let m = e["message"] as? String {
            statusMessage = "Error: \(m)"; awaitingCode = true; return
        }
        if let e = json["error"] as? String {
            statusMessage = "Error: \(json["error_description"] as? String ?? e)"; awaitingCode = true; return
        }

        guard let token = json["access_token"] as? String else {
            statusMessage = "No access_token"; return
        }

        // Store OAuth token directly — used as Bearer token for API calls
        codeVerifier = nil
        oauthState = nil
        saveKeychain(kAccessToken, token)

        if let refresh = json["refresh_token"] as? String {
            saveKeychain(kRefreshToken, refresh)
        }
        let exp = json["expires_in"] as? Int ?? 28800
        saveKeychain(kTokenExpiry, String(format: "%.0f", Date().addingTimeInterval(TimeInterval(exp)).timeIntervalSince1970))

        isSignedIn = true
        statusMessage = "Signed in successfully!"
    }

    // MARK: - Token Refresh

    private func isExpired() -> Bool {
        guard let s = loadKeychain(kTokenExpiry), let e = Double(s) else { return true }
        return Date().timeIntervalSince1970 > (e - 300)
    }

    private func doRefresh(completion: @escaping (String?) -> Void) {
        guard let refresh = loadKeychain(kRefreshToken),
              let url = URL(string: tokenEndpoint) else {
            DispatchQueue.main.async { self.isSignedIn = false; self.statusMessage = "Session expired" }
            completion(nil); return
        }

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientId,
            "scope": scopes
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String else {
                DispatchQueue.main.async { self?.isSignedIn = false; self?.statusMessage = "Refresh failed" }
                completion(nil); return
            }
            self.saveKeychain(self.kAccessToken, token)
            if let r = json["refresh_token"] as? String { self.saveKeychain(self.kRefreshToken, r) }
            let exp = json["expires_in"] as? Int ?? 28800
            self.saveKeychain(self.kTokenExpiry, String(format: "%.0f", Date().addingTimeInterval(TimeInterval(exp)).timeIntervalSince1970))
            DispatchQueue.main.async { self.isSignedIn = true }
            completion(token)
        }.resume()
    }

    // MARK: - Crypto

    private func randomBase64URL() -> String {
        var b = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &b)
        return Data(b).base64URLEncoded()
    }

    private func sha256Base64URL(_ input: String) -> String {
        Data(SHA256.hash(data: Data(input.utf8))).base64URLEncoded()
    }

    // MARK: - Keychain

    private func saveKeychain(_ key: String, _ value: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                 kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        SecItemDelete(q as CFDictionary)
        SecItemAdd(q as CFDictionary, nil)
    }

    private func loadKeychain(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                 kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var r: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private func deleteKeychain(_ key: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key] as CFDictionary)
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
