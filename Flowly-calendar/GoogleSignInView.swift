import SwiftUI

struct GoogleSignInView: View {
    @EnvironmentObject private var auth: AuthManager

    @Binding var currentScreen: ContentView.Screen
    @Binding var user: User

    @State private var isSigningIn = false
    @State private var errorMessage: String?

    private let classroomScopes = [
        "https://www.googleapis.com/auth/classroom.courses.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.me.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.me"
    ]

    var body: some View {
        VStack(spacing: 20) {
            Text("Connect Google Classroom").font(.title2).bold()

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundColor(.red).multilineTextAlignment(.center).padding(.horizontal)
            }

            Spacer()

            Button(action: handleGoogleSignIn) {
                HStack { Image(systemName: "person.badge.key"); Text(isSigningIn ? "Signing In..." : "Sign in with Google").font(.headline) }
                    .foregroundColor(.white).frame(maxWidth: .infinity).padding().background(isSigningIn ? Color.gray : Color.blue).cornerRadius(10)
            }
            .disabled(isSigningIn)

            if auth.isSignedIn {
                Button { proceedWithKnownSession() } label: {
                    Label("Continue (use saved session)", systemImage: "checkmark.circle")
                }
                .padding(.top, 4)
            }

            Text("Approve access to your classes and coursework.")
                .font(.caption).foregroundColor(.gray).multilineTextAlignment(.center)
        }
        .padding()
        .task { auth.restorePreviousSignIn() }
    }

    private func proceedWithKnownSession() {
        Task { @MainActor in
            do {
                let fresh = try await auth.getFreshAccessToken(requiredScopes: classroomScopes)
                handlePostSignIn(newEmail: fresh.email, token: fresh.token)
            } catch {
                errorMessage = "Could not restore session. Please sign in."
            }
        }
    }

    private func handleGoogleSignIn() {
        isSigningIn = true; errorMessage = nil
        Task { @MainActor in
            do {
                let fresh = try await auth.signIn(scopes: classroomScopes)
                handlePostSignIn(newEmail: fresh.email, token: fresh.token)
            } catch {
                errorMessage = "Sign-in failed: \(error.localizedDescription)"
            }
            isSigningIn = false
        }
    }

    private func handlePostSignIn(newEmail: String, token: String) {
        user.googleEmail = newEmail
        user.googleToken = token
        currentScreen = .classroomSelection
    }
}
