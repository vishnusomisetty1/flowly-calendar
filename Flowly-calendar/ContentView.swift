import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var userStore: UserStore
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var classroomsStore: ClassroomsStore

    @State private var scheduleItems: [ScheduleItem] = []
    @State private var assignments: [Assignment] = []
    @State private var classrooms: [GoogleClassroom] = []
    @State private var selectedDate = Date()

    enum Screen { case welcome, questionnaire, googleSignIn, classroomSelection, schedule }
    @State private var currentScreen: Screen = .welcome

    var body: some View {
        Group {
            if !auth.didAttemptRestore {
                // 🔒 Hold routing until restore completes (prevents repeated consent screens)
                ZStack {
                    theme.bgColor.ignoresSafeArea()
                    ProgressView("Checking your session…")
                }
            } else {
                ZStack {
                    theme.bgColor.ignoresSafeArea()
                    switch currentScreen {
                    case .welcome:
                        WelcomeView(currentScreen: $currentScreen)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    routeIfPossible()
                                }
                            }

                    case .questionnaire:
                        QuestionnaireView(currentScreen: $currentScreen, user: $userStore.user)

                    case .googleSignIn:
                        GoogleSignInView(currentScreen: $currentScreen, user: $userStore.user)

                    case .classroomSelection:
                        ClassroomSelectionView(
                            currentScreen: $currentScreen,
                            user: $userStore.user,
                            classrooms: $classrooms,
                            assignments: $assignments
                        )

                    case .schedule:
                        ScheduleScreen(
                            user: $userStore.user,
                            scheduleItems: $scheduleItems,
                            assignments: $assignments,
                            selectedDate: $selectedDate,
                            classrooms: classrooms,
                            currentScreen: $currentScreen
                        )
                    }
                }
            }
        }
        .onAppear { auth.restorePreviousSignIn() }
        .onChangeCompat(auth.isSignedIn) { _, _ in routeIfPossible() }
        .onChangeCompat(userStore.onboardingDone) { _, _ in routeIfPossible() }
        .onChangeCompat(classroomsStore.allClassrooms) { _, _ in
            classrooms = classroomsStore.allClassrooms
            routeIfPossible()
        }
        .onChangeCompat(classroomsStore.hasChosenOnce) { _, _ in routeIfPossible() }
    }

    private func routeIfPossible() {
        if !userStore.onboardingDone { currentScreen = .questionnaire; return }
        if !auth.isSignedIn { currentScreen = .googleSignIn; return }
        if classroomsStore.hasChosenOnce && !classroomsStore.allClassrooms.isEmpty {
            currentScreen = .schedule
        } else {
            currentScreen = .classroomSelection
        }
    }
}

// Keep ONE WelcomeView/FeatureRow definition in the project.
// If you already have WelcomeView in a separate file, delete these.
struct WelcomeView: View {
    @Binding var currentScreen: ContentView.Screen
    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 10) {
                Text("Flowly Calendar").font(.system(size: 40, weight: .bold)).foregroundColor(.blue)
                Text("Your Smart Study Companion").font(.subheadline).foregroundColor(.gray)
            }
            VStack(spacing: 20) {
                FeatureRow(icon: "calendar", title: "Smart Scheduling", subtitle: "AI-generated plans from your habits")
                FeatureRow(icon: "books.vertical", title: "Google Classroom", subtitle: "Sync assignments automatically")
                FeatureRow(icon: "checkmark.circle", title: "Task Tracking", subtitle: "Track progress and adjust")
            }
            .padding().background(Color(.systemGray6)).cornerRadius(12)
            Spacer()
            Button { currentScreen = .questionnaire } label: {
                Text("Get Started").font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding().background(Color.blue).cornerRadius(10)
            }
        }
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String; let title: String; let subtitle: String
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: icon)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundColor(.gray)
            }
        }
    }
}


