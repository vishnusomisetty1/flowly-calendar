import Foundation
import GoogleSignIn
import UIKit

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var isSignedIn: Bool = false
    @Published var email: String = ""
    @Published var didAttemptRestore: Bool = false   // 👈 tells the UI when restore finished

    private init() {}

    func restorePreviousSignIn() {
        if GIDSignIn.sharedInstance.configuration == nil {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: GoogleConfig.clientID)
        }
        GIDSignIn.sharedInstance.restorePreviousSignIn { user, _ in
            self.isSignedIn = (user != nil)
            self.email = user?.profile?.email ?? ""
            self.didAttemptRestore = true                // 👈 important
        }
    }

    func getFreshAccessToken(requiredScopes: [String]) async throws -> (token: String, email: String) {
        if GIDSignIn.sharedInstance.configuration == nil {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: GoogleConfig.clientID)
        }

        if let user = GIDSignIn.sharedInstance.currentUser {
            let ensured = try await ensureScopesAndRefresh(user: user, requiredScopes: requiredScopes)
            self.isSignedIn = true
            self.email = ensured.profile?.email ?? ""
            return (ensured.accessToken.tokenString, ensured.profile?.email ?? "")
        }

        let restoredUser: GIDGoogleUser? = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<GIDGoogleUser?, Error>) in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: user)
            }
        }

        guard let user = restoredUser else {
            throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let ensured = try await ensureScopesAndRefresh(user: user, requiredScopes: requiredScopes)
        self.isSignedIn = true
        self.email = ensured.profile?.email ?? ""
        return (ensured.accessToken.tokenString, ensured.profile?.email ?? "")
    }

    private func ensureScopesAndRefresh(user: GIDGoogleUser, requiredScopes: [String]) async throws -> GIDGoogleUser {
        var activeUser = user
        let granted = Set(activeUser.grantedScopes ?? [])
        let missing = requiredScopes.filter { !granted.contains($0) }

        if !missing.isEmpty {
            if GIDSignIn.sharedInstance.configuration == nil {
                GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: GoogleConfig.clientID)
            }
            guard let presenter = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })?
                .rootViewController else {
                throw NSError(domain: "Auth", code: -2, userInfo: [NSLocalizedDescriptionKey: "No presenter"])
            }

            let signInResult: GIDSignInResult = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<GIDSignInResult, Error>) in
                activeUser.addScopes(missing, presenting: presenter) { result, error in
                    if let error { cont.resume(throwing: error); return }
                    if let result { cont.resume(returning: result) }
                    else { cont.resume(throwing: NSError(domain: "Auth", code: -3, userInfo: [NSLocalizedDescriptionKey: "No result"])) }
                }
            }
            activeUser = signInResult.user
        }

        let refreshed: GIDGoogleUser = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<GIDGoogleUser, Error>) in
            activeUser.refreshTokensIfNeeded { u, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: u ?? activeUser)
            }
        }
        return refreshed
    }

    func signIn(scopes: [String]) async throws -> (token: String, email: String) {
        guard let presenter = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController else {
            throw NSError(domain: "Auth", code: -10, userInfo: [NSLocalizedDescriptionKey: "No presenter"])
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: GoogleConfig.clientID)

        _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil, additionalScopes: scopes) { _, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: ()) }
            }
        }

        return try await getFreshAccessToken(requiredScopes: scopes)
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        email = ""
    }
}
