import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var userStore: UserStore
    @EnvironmentObject private var classroomsStore: ClassroomsStore
    @Environment(\.dismiss) private var dismiss

    @Binding var currentScreen: ContentView.Screen

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Appearance")) {
                    Picker("Mode", selection: $theme.selection) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(.segmented)

                    if theme.colorScheme == .dark || theme.selection == 2 {
                        Toggle("Pure black background", isOn: $theme.pureBlack)
                    }
                }

                Section(header: Text("Account")) {
                    HStack {
                        Text("Signed in as")
                        Spacer()
                        Text(userStore.user.googleEmail.isEmpty ? "—" : userStore.user.googleEmail)
                            .foregroundColor(.secondary).lineLimit(1)
                    }
                }

                Section(header: Text("Study Strategy")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Strategy: \(userStore.user.studyStrategy.displayName)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Picker("Study Strategy", selection: $userStore.user.studyStrategy) {
                            ForEach([StudyStrategy.activeRecall, .spacedRepetition, .pomodoro], id: \.self) { strategy in
                                HStack {
                                    Image(systemName: strategy.icon)
                                    Text(strategy.displayName)
                                }.tag(strategy)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section(header: Text("Preferences")) {
                    Button {
                        userStore.onboardingDone = true // Mark as done so they can update and go straight to schedule
                        userStore.user = userStore.user // Save updated user data
                        dismiss()
                    } label: { Label("Update Questionnaire", systemImage: "pencil.circle") }

                    NavigationLink(destination:
                        QuestionnaireView(
                            currentScreen: .constant(.schedule),
                            user: .constant(userStore.user)
                        )
                    ) {
                        Label("Edit Study Preferences", systemImage: "slider.horizontal.3")
                    }

                    Button {
                        classroomsStore.hasChosenOnce = false
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            currentScreen = .classroomSelection
                        }
                    } label: { Label("Reselect Classes", systemImage: "books.vertical") }
                }

                Section {
                    Button(role: .destructive) {
                        auth.signOut()
                        userStore.reset()
                        classroomsStore.reset()
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            currentScreen = .welcome
                        }
                    } label: { Label("Sign Out & Reset All Data", systemImage: "arrow.right.square") }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
