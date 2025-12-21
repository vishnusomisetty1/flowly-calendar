import Foundation
import GoogleSignIn
import UIKit

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    /// 🔒 Fixed, immutable scope list (must never change dynamically)
    static let classroomScopes: [String] = [
        "https://www.googleapis.com/auth/classroom.courses.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.me",
        "https://www.googleapis.com/auth/classroom.coursework.me.readonly"
    ]

    @Published var isSignedIn = false
    @Published var email: String = ""
    @Published var didAttemptRestore = false

    private var isRestoring = false

    private init() {}

    // MARK: - Configuration

    private func configureIfNeeded() {
        if GIDSignIn.sharedInstance.configuration == nil {
            GIDSignIn.sharedInstance.configuration =
                GIDConfiguration(clientID: GoogleConfig.clientID)
        }
    }

    // MARK: - Restore (NO UI, NO CONSENT)

    /// Silent restore only. If scopes are missing → signed out.
    func restorePreviousSignIn() {
        guard !isRestoring else {
            print("[AuthManager] restore skipped (already restoring)")
            return
        }

        isRestoring = true
        print("[AuthManager] restore start")

        configureIfNeeded()

        GIDSignIn.sharedInstance.restorePreviousSignIn { user, _ in
            Task { @MainActor in
                defer {
                    self.didAttemptRestore = true
                    self.isRestoring = false
                    print("[AuthManager] restore end - isSignedIn=\(self.isSignedIn)")
                }

                guard let user else {
                    self.resetState()
                    return
                }

                let granted = Set(user.grantedScopes ?? [])
                let required = Set(Self.classroomScopes)

                guard required.isSubset(of: granted) else {
                    print("[AuthManager] restore failed - missing scopes")
                    self.resetState()
                    return
                }

                do {
                    let refreshed = try await self.refresh(user)
                    self.isSignedIn = true
                    self.email = refreshed.profile?.email ?? ""
                } catch {
                    self.resetState()
                }
            }
        }
    }

    // MARK: - Interactive Sign-In (ONE TIME ONLY)

    /// The ONLY place OAuth UI is allowed to appear.
    func signIn() async throws -> (token: String, email: String) {
        print("[AuthManager] signIn start")

        configureIfNeeded()

        guard let presenter = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController else {
            throw NSError(domain: "Auth", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No presenter"])
        }

        let result: GIDSignInResult = try await withCheckedThrowingContinuation { cont in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: Self.classroomScopes
            ) { result, error in
                if let error { cont.resume(throwing: error) }
                else if let result { cont.resume(returning: result) }
                else {
                    cont.resume(throwing: NSError(
                        domain: "Auth",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "No sign-in result"]
                    ))
                }
            }
        }

        let user = try await refresh(result.user)

        self.isSignedIn = true
        self.email = user.profile?.email ?? ""

        print("[AuthManager] signIn end - email=\(self.email)")
        return (user.accessToken.tokenString, self.email)
    }

    /// Returns a valid access token for Google Classroom APIs, refreshing interactively if needed.
    func getFreshAccessToken(requiredScopes: [String]) async throws -> (token: String, email: String) {
        if isSignedIn && !email.isEmpty {
            // Try restoring (should be current)
            if let currentUser = GIDSignIn.sharedInstance.currentUser {
                let refreshed = try await self.refresh(currentUser)
                self.email = refreshed.profile?.email ?? self.email
                return (refreshed.accessToken.tokenString, self.email)
            }
        }
        // If not signed in, fall back to sign-in flow
        return try await self.signIn()
    }

    // MARK: - Helpers

    private func refresh(_ user: GIDGoogleUser) async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { cont in
            user.refreshTokensIfNeeded { refreshed, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: refreshed ?? user) }
            }
        }
    }

    private func resetState() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        email = ""
    }

    func signOut() {
        print("[AuthManager] signOut")
        resetState()
    }
}
