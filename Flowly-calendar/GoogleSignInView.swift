import SwiftUI

struct GoogleSignInView: View {
    @EnvironmentObject private var auth: AuthManager

    @Binding var currentScreen: ContentView.Screen
    @Binding var user: User

    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Flowly Calendar")
                .font(.largeTitle)
                .bold()
                .foregroundColor(.blue)
            
              Text("Welcome! This app helps manages your classroom assigments and create a schedule for you!")
                  .font(.body)
                  .foregroundColor(.primary)
                  .multilineTextAlignment(.center)
                  .padding(.horizontal, 24)
           
         
          
            

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundColor(.red).multilineTextAlignment(.center).padding(.horizontal)
            }

            Spacer()

            Button(action: handleGoogleSignIn) {
                HStack { Image(systemName: "person.badge.key"); Text(isSigningIn ? "Connecting ..." : "Connect with Google").font(.headline) }
                    .foregroundColor(.white).frame(maxWidth: .infinity).padding().background(isSigningIn ? Color.gray : Color.blue).cornerRadius(10)
            }
            .disabled(isSigningIn)

            Text("Approve access to your classes and coursework.")
                .font(.caption).foregroundColor(.gray).multilineTextAlignment(.center)
        }
        .padding()
    }

    private func handleGoogleSignIn() {
        isSigningIn = true
        errorMessage = nil

        Task { @MainActor in
            do {
                let result = try await auth.signIn()
                handlePostSignIn(newEmail: result.email, token: result.token)
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
