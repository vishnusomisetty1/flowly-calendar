import SwiftUI
import GoogleSignIn

@main
struct FlowlyCalendarApp: App {
    @StateObject private var theme = ThemeManager()
    @StateObject private var userStore = UserStore()
    @StateObject private var auth = AuthManager.shared
    @StateObject private var classroomsStore = ClassroomsStore()

    // NEW
    @StateObject private var assignmentsStore = AssignmentsStore()
    @StateObject private var scheduleStore = ScheduleStore()

    init() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: GoogleConfig.clientID)
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
                    .environmentObject(theme)
                    .environmentObject(userStore)
                    .environmentObject(auth)
                    .environmentObject(classroomsStore)
                    .environmentObject(assignmentsStore)   // NEW
                    .environmentObject(scheduleStore)      // NEW
                    .preferredColorScheme(theme.colorScheme)
                    .onOpenURL { url in GIDSignIn.sharedInstance.handle(url) }
                    .task { auth.restorePreviousSignIn() }
            }
        }
    }
}
