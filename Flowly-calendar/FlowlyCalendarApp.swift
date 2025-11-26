import SwiftUI
import GoogleSignIn

@main
struct FlowlyCalendarApp: App {
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @StateObject private var auth = AuthManager.shared
    @StateObject private var classroomsStore = ClassroomsStore()
    @StateObject private var assignmentsStore = AssignmentsStore()

    init() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: GoogleConfig.clientID)
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
                    .environmentObject(auth)
                    .environmentObject(classroomsStore)
                    .environmentObject(assignmentsStore)
                    .onOpenURL { url in GIDSignIn.sharedInstance.handle(url) }
                    .task { auth.restorePreviousSignIn() }
            }
            .colorScheme(isDarkMode ? .dark : .light)
        }
    }
}
