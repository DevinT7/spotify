import AuthenticationServices
import CryptoKit
import Observation
import UIKit

/// Spotify Authorization Code flow with PKCE. No client secret ever ships in the app.
@Observable @MainActor
final class AuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let redirectURI = "tempo://callback"
    static let scopes = [
        "user-read-playback-state", "user-modify-playback-state", "user-read-currently-playing",
        "user-read-recently-played", "user-top-read", "user-library-read", "user-library-modify",
        "playlist-read-private", "playlist-read-collaborative", "playlist-modify-public",
        "playlist-modify-private", "user-read-private", "user-follow-read",
    ]

    var clientID: String { didSet { UserDefaults.standard.set(clientID, forKey: "clientID") } }
    private(set) var isSignedIn: Bool
    private var session: ASWebAuthenticationSession?
    private var refreshTask: Task<String, Error>?

    override init() {
        clientID = UserDefaults.standard.string(forKey: "clientID") ?? ""
        isSignedIn = Keychain.get("refresh") != nil
        super.init()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    func signIn() async throws {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw AuthError.missingClientID }
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: id), .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "code_challenge", value: challenge),
        ]
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: "tempo") { url, err in
                if let url { cont.resume(returning: url) } else { cont.resume(throwing: err ?? AuthError.cancelled) }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            session = s
            s.start()
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else { throw AuthError.denied }
        try await tokenRequest(["grant_type": "authorization_code", "code": code,
                                "redirect_uri": Self.redirectURI, "client_id": id, "code_verifier": verifier])
    }

    func signOut() {
        Keychain.remove("access"); Keychain.remove("refresh"); Keychain.remove("expiry")
        isSignedIn = false
    }

    func validAccessToken() async throws -> String {
        if let t = Keychain.get("access"), let e = Keychain.get("expiry"), let exp = Double(e),
           Date().timeIntervalSince1970 < exp - 60 { return t }
        if let refreshTask { return try await refreshTask.value }
        let task = Task { () -> String in
            defer { refreshTask = nil }
            guard let r = Keychain.get("refresh") else { throw AuthError.notSignedIn }
            try await tokenRequest(["grant_type": "refresh_token", "refresh_token": r, "client_id": clientID])
            guard let t = Keychain.get("access") else { throw AuthError.notSignedIn }
            return t
        }
        refreshTask = task
        return try await task.value
    }

    func forceRefresh() async { Keychain.set("0", for: "expiry") }

    private func tokenRequest(_ form: [String: String]) async throws {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var comps = URLComponents(); comps.queryItems = form.map { .init(name: $0.key, value: $0.value) }
        req.httpBody = comps.percentEncodedQuery?.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else {
            if form["grant_type"] == "refresh_token" { signOut() }
            throw AuthError.tokenFailed(String(data: data, encoding: .utf8) ?? "")
        }
        Keychain.set(access, for: "access")
        if let r = json["refresh_token"] as? String { Keychain.set(r, for: "refresh") }
        Keychain.set(String(Date().timeIntervalSince1970 + ((json["expires_in"] as? Double) ?? 3600)), for: "expiry")
        isSignedIn = true
    }

    private static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in chars.randomElement()! })
    }
}

enum AuthError: LocalizedError {
    case missingClientID, cancelled, denied, notSignedIn, tokenFailed(String)
    var errorDescription: String? {
        switch self {
        case .missingClientID: "Paste your Spotify Client ID first."
        case .cancelled: "Sign-in cancelled."
        case .denied: "Spotify did not return an authorization code."
        case .notSignedIn: "You are signed out."
        case .tokenFailed(let m): "Token exchange failed: \(m)"
        }
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
