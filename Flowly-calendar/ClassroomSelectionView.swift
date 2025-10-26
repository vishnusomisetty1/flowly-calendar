import SwiftUI

@MainActor
struct ClassroomSelectionView: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var classroomsStore: ClassroomsStore
    @EnvironmentObject private var auth: AuthManager

    @Binding var currentScreen: ContentView.Screen
    @Binding var user: User
    @Binding var classrooms: [GoogleClassroom]
    @Binding var assignments: [Assignment]

    @State private var isWorking = false
    @State private var errorMessage: String?

    private let classroomScopes = [
        "https://www.googleapis.com/auth/classroom.courses.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.me.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.me"
    ]

    var body: some View {
        VStack(spacing: 12) {
            HStack { Text("Choose your classes").font(.title2).bold(); Spacer() }.padding(.horizontal)

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundColor(.red).padding(.horizontal)
            }

            if classrooms.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray").font(.system(size: 36)).foregroundColor(.gray)
                    Text("No classes found yet").foregroundColor(.gray)
                    Text("Tap Refresh to load your classes").font(.caption).foregroundColor(.gray)
                }
                .padding(.top, 24)
            } else {
                List {
                    Section {
                        ForEach($classrooms) { $c in
                            Toggle(isOn: $c.isSelected) {
                                Text(c.name.isEmpty ? "Untitled" : c.name)
                            }
                        }
                    } header: { Text("Your Google Classroom courses") }
                }
                .listStyle(.insetGrouped)
            }

            HStack(spacing: 10) {
                Button { for i in classrooms.indices { classrooms[i].isSelected = true } } label: { Text("Select All") }
                Button { for i in classrooms.indices { classrooms[i].isSelected = false } } label: { Text("Deselect All") }
                Spacer()
                Button {
                    Task { await saveAndContinue() }
                } label: {
                    HStack { if isWorking { ProgressView().scaleEffect(0.8) }; Text("Continue").font(.headline) }
                        .foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 10).background(Color.blue).cornerRadius(10)
                }
                .disabled(isWorking)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(theme.bgColor.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await loadClasses() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(isWorking)
            }
        }
        .task {
            if classrooms.isEmpty && classroomsStore.allClassrooms.isEmpty {
                await loadClasses()
            } else if classrooms.isEmpty {
                classrooms = classroomsStore.applySelection(to: classroomsStore.allClassrooms)
            }
        }
        .onAppear {
            // Skip classroom selection if user already has classrooms and is just redoing questionnaire
            if classroomsStore.hasChosenOnce && !classroomsStore.allClassrooms.isEmpty && classrooms.isEmpty {
                classrooms = classroomsStore.applySelection(to: classroomsStore.allClassrooms)
            }
        }
    }

    private func loadClasses() async {
        isWorking = true; errorMessage = nil
        do {
            let (token, email) = try await auth.getFreshAccessToken(requiredScopes: classroomScopes)
            user.googleToken = token
            if user.googleEmail.isEmpty { user.googleEmail = email }

            let coursesRaw = try await ClassroomAPI.listAllMyCourses(accessToken: token)
            let mapped: [GoogleClassroom] = coursesRaw.map {
                GoogleClassroom(
                    id: $0.id,
                    name: [$0.name, $0.section].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " • "),
                    isSelected: true
                )
            }
            let applied = classroomsStore.applySelection(to: mapped)
            classroomsStore.allClassrooms = applied
            classrooms = applied
        } catch {
            errorMessage = "Could not load classes: \(error.localizedDescription)"
        }
        isWorking = false
    }

    private func saveAndContinue() async {
        isWorking = true; errorMessage = nil
        classroomsStore.allClassrooms = classrooms
        classroomsStore.rememberSelection(from: classrooms)
        isWorking = false
        currentScreen = .schedule
    }
}
