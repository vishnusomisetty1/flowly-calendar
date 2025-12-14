// Reminder: Ensure that ScheduleSettings is created and injected as an environmentObject in your main App struct, e.g.
//
// @main
// struct YourApp: App {
//     @StateObject private var auth = AuthManager()
//     @StateObject private var classroomsStore = ClassroomsStore()
//     @StateObject private var assignmentsStore = AssignmentsStore()
//     @StateObject private var scheduleSettings = ScheduleSettings()
//
//     var body: some Scene {
//         WindowGroup {
//             ContentView()
//                 .environmentObject(auth)
//                 .environmentObject(classroomsStore)
//                 .environmentObject(assignmentsStore)
//                 .environmentObject(scheduleSettings)
//         }
//     }
// }

import SwiftUI
import FoundationModels

// MARK: - FoundationModels support and AI availability check

@available(iOS 26.0, *)
extension SystemLanguageModel {
    static var isAppleIntelligenceAvailable: Bool {
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        } else {
            // Fallback for earlier iOS versions
            return false
        }
    }
}

// MARK: - AI estimate data model

@available(iOS 26.0, *)
@Generable(description: "Assignment AI estimate")
struct AssignmentEstimate {
    @Guide(description: "Estimated time to complete, in minutes")
    var estimatedMinutes: Int

    @Guide(description: "Estimated importance, 1 (lowest) to 5 (highest)")
    var importance: Int
}

// MARK: - Assignment AI Estimator ViewModel

class AssignmentAIEstimator: ObservableObject {
    @Published var modelAvailable: Bool
    private var session: Any?

    init() {
        if #available(iOS 26.0, *) {
            self.modelAvailable = SystemLanguageModel.isAppleIntelligenceAvailable
            if modelAvailable {
                session = LanguageModelSession(
                    instructions: "You are an assistant that helps schedule homework. Given an assignment title and description, estimate how many minutes it will take and its importance (1-5). Consider that students usually have school on weekdays and may not have as much free time during those days. Take typical weekday and weekend schedules into account when estimating."
                )
            } else {
                session = nil
            }
        } else {
            // Fallback for earlier iOS versions
            self.modelAvailable = false
            session = nil
        }
    }

    @MainActor
    func estimate(for assignment: Assignment, completion: @escaping (Int, Int) -> Void) async {
        if #available(iOS 26.0, *) {
            guard let session = session as? LanguageModelSession else {
                // Fallback: return default estimate
                completion(30, 3) // Default 30 minutes, importance 3
                return
            }
            let prompt = "Title: \(assignment.title). Description: \(assignment.description ?? "")"
            do {
                let estimate = try await session.respond(
                    to: prompt,
                    generating: AssignmentEstimate.self
                )
                completion(estimate.content.estimatedMinutes, estimate.content.importance)
            } catch {
                completion(30, 3)
            }
        } else {
            // Fallback for earlier iOS versions
            completion(30, 3)
        }
    }
}

// MARK: - AI Scheduler and StudySession model

struct StudySession: Identifiable, Codable {
    let id: UUID
    let assignmentTitle: String
    let date: Date
    let startTime: String // e.g. "17:00"
    let endTime: String // e.g. "17:40"
}

@available(iOS 26.0, *)
class AIScheduler: ObservableObject {
    private var session: LanguageModelSession?

    init() {
        if SystemLanguageModel.isAppleIntelligenceAvailable {
            session = LanguageModelSession(
                instructions: "You are a study scheduling assistant. Given a list of assignments and available study slots, and considering preferences, output a schedule (JSON) assigning each assignment to time slots. Default: Prefer scheduling later in the day for weekdays."
            )
        }
    }

    // preferenceSummary could be built from user settings in future
    func generateSchedule(assignments: [Assignment], preferenceSummary: String = "Prefer work later in the day for weekdays.", completion: @escaping (Result<[StudySession], Error>) -> Void) async {
        guard let session else {
            completion(.failure(NSError(domain: "AIScheduler", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not available"])))
            return
        }
        // Build input prompt
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filteredAssignments = assignments.filter { a in
            let now = Date()
            let fourteenDaysFromNow = Calendar.current.date(byAdding: .day, value: 14, to: now)!
            return a.dueDate <= fourteenDaysFromNow
        }
        .sorted { $0.dueDate < $1.dueDate }
        .prefix(10)

        let assignmentsList = filteredAssignments.map { a in
            "- \(a.title), due \(formatter.string(from: a.dueDate)), needs \(a.aiEstimatedTime) minutes"
        }.joined(separator: "\n")

        let availableSlots = "Assume the student is available 16:00-21:00 on weekdays and 10:00-21:00 on weekends."
        let prompt = """
        Assignments:\n\(assignmentsList)\n\n\(availableSlots)\nPreferences: \(preferenceSummary)\nOutput a study schedule as a JSON array: [{\"assignmentTitle\":...,\"date\":...,\"startTime\":...,\"endTime\":...}]
        """
        do {
            let response = try await session.respond(to: prompt)
            // Parse JSON in response with improved error handling
            if let range = response.content.range(of: "[", options: .literal),
               let last = response.content.range(of: "]", options: .backwards) {
                let jsonString = String(response.content[range.lowerBound...last.upperBound])
                // Validate JSON array presence and non-empty
                if jsonString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !jsonString.hasPrefix("[") || !jsonString.hasSuffix("]") {
                    let errorMessage = "Could not read schedule from AI: Invalid response format. Response: \(response.content)"
                    completion(.failure(NSError(domain: "AIScheduler", code: 2, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                    return
                }
                let data = jsonString.data(using: .utf8) ?? Data()
                do {
                    let sessions = try JSONDecoder().decode([StudySession].self, from: data)
                    completion(.success(sessions))
                } catch {
                    let errorMessage = "JSON decoding failed with error: \(error.localizedDescription). Response: \(response.content)"
                    completion(.failure(NSError(domain: "AIScheduler", code: 3, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                }
            } else {
                let errorMessage = "Could not read schedule from AI: Invalid response format. Response: \(response.content)"
                completion(.failure(NSError(domain: "AIScheduler", code: 2, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
            }
        } catch {
            completion(.failure(error))
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var classroomsStore: ClassroomsStore
    @EnvironmentObject private var assignmentsStore: AssignmentsStore

    @State private var user = User()
    @State private var currentScreen: Screen = .welcome

    enum Screen { case welcome, googleSignIn, classroomSelection, assignments }

    @EnvironmentObject private var scheduleSettings: ScheduleSettings

    var body: some View {
        Group {
            if !auth.didAttemptRestore {
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()
                    ProgressView("Checking your session…")
                }
            } else {
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()
                    switch currentScreen {
                    case .welcome:
                        WelcomeView(currentScreen: $currentScreen)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    routeIfPossible()
                                }
                            }

                    case .googleSignIn:
                        GoogleSignInView(currentScreen: $currentScreen, user: $user)

                    case .classroomSelection:
                        ClassroomSelectionView(currentScreen: $currentScreen, user: $user)

                    case .assignments:
                        MainTabView(currentScreen: $currentScreen)
                    }
                }
            }
        }
        .onAppear {
            auth.restorePreviousSignIn()
            if auth.isSignedIn {
                assignmentsStore.load(for: auth.email)
            } else {
                assignmentsStore.load(for: "local")
            }
        }
        .onChangeCompat(auth.isSignedIn) { _, _ in
            routeIfPossible()
            if auth.isSignedIn {
                assignmentsStore.load(for: auth.email)
            } else {
                assignmentsStore.load(for: "local")
            }
        }
        .onChangeCompat(classroomsStore.hasChosenOnce) { _, _ in routeIfPossible() }
    }

    private func routeIfPossible() {
        if !auth.isSignedIn {
            currentScreen = .googleSignIn
            return
        }
        if !classroomsStore.hasChosenOnce || classroomsStore.allClassrooms.isEmpty {
            currentScreen = .classroomSelection
        } else {
            assignmentsStore.migrateLocalIfNeeded(to: auth.email)
            currentScreen = .assignments
        }
    }
}

struct WelcomeView: View {
    @Binding var currentScreen: ContentView.Screen
    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 10) {
                Text("Flowly Calendar").font(.system(size: 40, weight: .bold)).foregroundColor(.blue)
                Text("Your Assignment Manager").font(.subheadline).foregroundColor(.gray)
            }
            Spacer()
            Button { currentScreen = .googleSignIn } label: {
                Text("Get Started").font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding().background(Color.blue).cornerRadius(10)
            }
        }
        .padding()
    }
}

struct MainTabView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var assignmentsStore: AssignmentsStore
    @EnvironmentObject private var scheduleSettings: ScheduleSettings
    @Binding var currentScreen: ContentView.Screen

    @State private var scheduleManager: ScheduleManager?

    var body: some View {
        TabView {
            AssignmentsView(currentScreen: $currentScreen)
                .tabItem {
                    Label("Assignments", systemImage: "list.bullet")
                }

            if #available(iOS 26.0, *) {
                if let scheduleManager = scheduleManager {
                    ScheduleView()
                        .environmentObject(scheduleManager)
                        .tabItem {
                            Label("Schedule", systemImage: "calendar")
                        }
                } else {
                    Text("Loading schedule...")
                        .tabItem {
                            Label("Schedule", systemImage: "calendar")
                        }
                }
            } else {
                // Fallback on earlier versions
            }
        }
        .onAppear {
            // Initialize ScheduleManager with actual settings if not already created
            if scheduleManager == nil {
                scheduleManager = ScheduleManager(assignments: [], settings: scheduleSettings)
            }
            // Update ScheduleManager with current assignments
            updateScheduleManager()
        }
        .onChangeCompat(assignmentsStore.assignments) { _, _ in
            updateScheduleManager()
        }
        .onChangeCompat(scheduleSettings.preferredStartInterval) { _, _ in
            updateScheduleManager()
        }
        .onChangeCompat(scheduleSettings.preferredEndInterval) { _, _ in
            updateScheduleManager()
        }
        .onChangeCompat(scheduleSettings.loadBias) { _, _ in
            updateScheduleManager()
        }
    }

    private func updateScheduleManager() {
        guard let scheduleManager = scheduleManager else { return }

        // Update settings reference if it changed
        if scheduleManager.settings !== scheduleSettings {
            scheduleManager.settings = scheduleSettings
        }

        // Convert assignments to AssignmentInput format
        let inputs = assignmentsStore.incompleteAssignments.compactMap { a -> AssignmentInput? in
            guard a.hasRealDueDate else { return nil }
            let remainingMinutes = max(0, a.aiEstimatedTime - a.minutesCompleted)
            guard remainingMinutes > 0 else { return nil }
            return AssignmentInput(
                id: a.id.uuidString,
                dueDate: a.dueDate,
                totalHours: Double(remainingMinutes) / 60.0,
                hoursCompleted: 0,
                importance: Double(a.aiEstimatedImportance)
            )
        }
        scheduleManager.updateAssignments(inputs)
    }
}

struct PlaceholderScheduleView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Schedule coming soon")
                .font(.headline)
            Text("AI scheduling is temporarily disabled. You can still edit each assignment's duration and points from the Assignments tab.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct AssignmentsView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var assignmentsStore: AssignmentsStore
    @EnvironmentObject private var classroomsStore: ClassroomsStore

    @Binding var currentScreen: ContentView.Screen

    @AppStorage("assignments.selectedTab") private var selectedTabRaw: String = Tab.incomplete.rawValue
    var selectedTab: Tab {
        Tab(rawValue: selectedTabRaw) ?? .incomplete
    }

    @State private var isRefreshing = false
    // Move showClassroomPicker state into settings view (removed from here)
    // @State private var showClassroomPicker = false
    @State private var localClassrooms: [GoogleClassroom] = []
    @State private var expandedSections: [String: Bool] = [:]

    // Add AI estimator instance
    @StateObject private var aiEstimator = AssignmentAIEstimator()

    // Add state to control add assignment sheet presentation
    @State private var showAddAssignment = false

    // Add state for deletion
    @State private var assignmentToDelete: Assignment?
    @State private var showDeleteAlert = false
    @State private var confirmSecondDelete = false

    @State private var assignmentToEdit: Assignment? = nil

    // New state for showing SettingsView sheet
    @State private var showSettings = false

    private let classroomScopes = [
        "https://www.googleapis.com/auth/classroom.courses.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.me.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.me"
    ]

    var incompleteCount: Int {
        let grouped = groupIncomplete(assignmentsStore.incompleteAssignments)
        return grouped.values.reduce(0) { $0 + $1.count }
    }
    var missingCount: Int { assignmentsStore.missingAssignments.count }
    var doneCount: Int { assignmentsStore.completedAssignments.count }

    enum Tab: String, CaseIterable {
        case incomplete, missing, done
    }

    private func deleteAssignment(_ assignment: Assignment) {
        assignmentsStore.assignments.removeAll(where: { $0.id == assignment.id })
    }

    private func assignmentRowView(assignment: Assignment) -> some View {
        AssignmentRow(
            assignment: assignment
        )
        .contentShape(Rectangle())
        .onTapGesture {
            assignmentToEdit = assignment
        }
        .contextMenu {
            Button {
                assignmentToEdit = assignment
            } label: {
                Label("Edit Duration & Points", systemImage: "slider.horizontal.3")
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                Picker("Section", selection: $selectedTabRaw) {
                    Text("Incomplete (\(incompleteCount))").tag(Tab.incomplete.rawValue)
                    Text("Missing (\(missingCount))").tag(Tab.missing.rawValue)
                    Text("Done (\(doneCount))").tag(Tab.done.rawValue)
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                List {
                    switch selectedTab {
                    case .missing:
                        buildMissingSection()
                    case .incomplete:
                        buildIncompleteSection()
                    case .done:
                        buildDoneSection()
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Assignments")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await refreshAssignments() }
                        } label: {
                            if isRefreshing {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(isRefreshing)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showAddAssignment = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Sign Out") {
                            auth.signOut()
                            currentScreen = .welcome
                        }
                    }
                }
                .refreshable {
                    await refreshAssignments()
                }
                .onAppear {
                    if assignmentsStore.assignments.isEmpty && !isRefreshing {
                        isRefreshing = true
                        Task { await refreshAssignments() }
                    }
                    var keys: [String] = []
                    switch selectedTab {
                    case .incomplete:
                        keys = ["This Week", "Next Week", "More", "No Due Date"]
                    case .missing:
                        keys = ["This Week", "Last Week", "Before"]
                    case .done:
                        keys = ["This Week", "Last Week", "Before", "No Due Date"]
                    }
                    for key in keys {
                        expandedSections[key] = false
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    localClassrooms: classroomsStore.allClassrooms,
                    onSaveClassrooms: { selectedClassrooms in
                        classroomsStore.allClassrooms = selectedClassrooms
                        classroomsStore.rememberSelection(from: selectedClassrooms)
                        Task { await refreshAssignments() }
                    }
                )
            }
            .sheet(isPresented: $showAddAssignment) {
                AddAssignmentView(
                    isPresented: $showAddAssignment,
                    assignmentsStore: assignmentsStore,
                    classrooms: classroomsStore.allClassrooms
                )
            }
            .sheet(item: $assignmentToEdit) { assignment in
                AssignmentEditSheet(assignment: assignment)
                    .environmentObject(assignmentsStore)
            }
            .alert("Delete Assignment?", isPresented: $showDeleteAlert, presenting: assignmentToDelete) { assignment in
                Button("Delete", role: .destructive) {
                    confirmSecondDelete = true
                    showDeleteAlert = false
                }
                Button("Cancel", role: .cancel) {
                    assignmentToDelete = nil
                    showDeleteAlert = false
                }
            } message: { assignment in
                Text("Are you sure you want to delete \"\(assignment.title)\"?")
            }
            .alert("Delete Forever?", isPresented: $confirmSecondDelete, presenting: assignmentToDelete) { assignment in
                Button("Delete Forever", role: .destructive) {
                    deleteAssignment(assignment)
                    assignmentToDelete = nil
                    confirmSecondDelete = false
                }
                Button("Cancel", role: .cancel) {
                    assignmentToDelete = nil
                    confirmSecondDelete = false
                }
            } message: { assignment in
                Text("This cannot be undone. Are you sure you want to permanently delete \"\(assignment.title)\"?")
            }
        }
    }

    @ViewBuilder
    private func buildMissingSection() -> some View {
        let missing: [Assignment] = assignmentsStore.missingAssignments
        let orderedKeys = ["This Week", "Last Week", "Before"]
        let grouped = groupMissing(missing)

        ForEach(orderedKeys, id: \.self) { key in
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedSections[key] ?? false },
                    set: { expandedSections[key] = $0 }
                ),
                content: {
                    if let assignments = grouped[key], !assignments.isEmpty {
                        ForEach(assignments) { assignment in
                            assignmentRowView(assignment: assignment)
                        }
                    } else {
                        Text("No assignments in this section.")
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                },
                label: {
                    HStack {
                        Text(key)
                        Spacer()
                        if let count = grouped[key]?.count {
                            Text("(\(count))")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
            )
        }
    }

    @ViewBuilder
    private func buildIncompleteSection() -> some View {
        let incomplete: [Assignment] = assignmentsStore.incompleteAssignments
        let grouped = groupIncomplete(incomplete)
        let orderedKeys = ["This Week", "Next Week", "More", "No Due Date"]

        ForEach(orderedKeys, id: \.self) { key in
            if key != "No Due Date" || (grouped[key]?.isEmpty == false) {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedSections[key] ?? false },
                        set: { expandedSections[key] = $0 }
                    ),
                    content: {
                        if let assignments = grouped[key], !assignments.isEmpty {
                            ForEach(assignments) { assignment in
                                assignmentRowView(assignment: assignment)
                            }
                        } else {
                            Text("No assignments in this section.")
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        }
                    },
                    label: {
                        HStack {
                            Text(key)
                            Spacer()
                            if let count = grouped[key]?.count {
                                Text("(\(count))")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func buildDoneSection() -> some View {
        let completed: [Assignment] = assignmentsStore.completedAssignments
        let orderedKeys = ["This Week", "Last Week", "Before", "No Due Date"]
        let grouped = groupDone(completed)

        ForEach(orderedKeys, id: \.self) { key in
            if key != "No Due Date" || (grouped[key]?.isEmpty == false) {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedSections[key] ?? false },
                        set: { expandedSections[key] = $0 }
                    ),
                    content: {
                        if let assignments = grouped[key], !assignments.isEmpty {
                            ForEach(assignments) { assignment in
                                assignmentRowView(assignment: assignment)
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    let assignment = assignments[index]
                                    assignmentToDelete = assignment
                                    showDeleteAlert = true
                                }
                            }
                        } else {
                            Text("No assignments in this section.")
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        }
                    },
                    label: {
                        HStack {
                            Text(key)
                            Spacer()
                            if let count = grouped[key]?.count {
                                Text("(\(count))")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                )
            }
        }
    }

    private func refreshAssignments() async {
        isRefreshing = true

        do {
            let token = try await auth.getFreshAccessToken(requiredScopes: classroomScopes).token
            let classrooms = classroomsStore.allClassrooms.filter { $0.isSelected }

            if !classrooms.isEmpty {
                let fetched = try await AssignmentSync.fetchForSelectedClasses(token: token, classes: classrooms)
                let customAssignments = assignmentsStore.assignments.filter { $0.courseId == nil }
                assignmentsStore.replace(with: customAssignments + fetched)
                // Removed assignmentsStore.load(for: auth.email) per instructions
            }
        } catch {
            // Silently handle errors for simplicity
        }

        isRefreshing = false
    }

    // Helper to get Monday (startOfWeek) for a given date
    private func startOfWeek(for date: Date) -> Date {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        let daysToSubtract = weekday == 1 ? 6 : weekday - 2
        guard let monday = cal.date(byAdding: .day, value: -daysToSubtract, to: date) else {
            return date
        }
        return cal.startOfDay(for: monday)
    }

    // Helper to get Sunday (endOfWeek) for a given date (Sunday inclusive)
    private func endOfWeek(for date: Date) -> Date {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        let daysToAdd = weekday == 1 ? 0 : 8 - weekday
        guard let sunday = cal.date(byAdding: .day, value: daysToAdd, to: date) else {
            return date
        }
        var components = DateComponents()
        components.day = 1
        components.second = -1
        if let endOfSunday = cal.date(byAdding: components, to: cal.startOfDay(for: sunday)) {
            return endOfSunday
        }
        return sunday
    }

    private func groupIncomplete(_ assignments: [Assignment]) -> [String: [Assignment]] {
        var groups: [String: [Assignment]] = [:]
        let cal = Calendar.current
        let today = Date()

        let thisWeekStart = startOfWeek(for: today)
        let thisWeekEnd = endOfWeek(for: today)
        groups["This Week"] = assignments.filter {
            let due = $0.dueDate
            return due >= thisWeekStart && due <= thisWeekEnd
        }

        if let nextWeekMonday = cal.date(byAdding: .weekOfYear, value: 1, to: thisWeekStart),
           let nextWeekSunday = cal.date(byAdding: .day, value: 6, to: nextWeekMonday) {
            let nextWeekStart = cal.startOfDay(for: nextWeekMonday)
            let nextWeekEnd = cal.date(bySettingHour: 23, minute: 59, second: 59, of: nextWeekSunday) ?? nextWeekSunday
            groups["Next Week"] = assignments.filter {
                let due = $0.dueDate
                return due >= nextWeekStart && due <= nextWeekEnd
            }
        } else {
            groups["Next Week"] = []
        }

        if let nextWeekMonday = cal.date(byAdding: .weekOfYear, value: 1, to: thisWeekStart),
           let nextWeekSunday = cal.date(byAdding: .day, value: 6, to: nextWeekMonday) {
            let nextWeekPlus = cal.date(bySettingHour: 23, minute: 59, second: 59, of: nextWeekSunday) ?? nextWeekSunday
            groups["More"] = assignments.filter {
                let due = $0.dueDate
                return due > nextWeekPlus
            }
        } else {
            groups["More"] = []
        }

        let noDueDateAssignments = assignmentsStore.otherAssignments.filter { !$0.hasRealDueDate }
        let incompleteNoDueDate = assignments.filter { !$0.hasRealDueDate }
        var combinedNoDueDate = noDueDateAssignments
        for assignment in incompleteNoDueDate {
            if !combinedNoDueDate.contains(where: { $0.id == assignment.id }) {
                combinedNoDueDate.append(assignment)
            }
        }
        groups["No Due Date"] = combinedNoDueDate

        groups = groups.filter { !$0.value.isEmpty }

        let orderedKeys = ["This Week", "Next Week", "More", "No Due Date"]
        return Dictionary(uniqueKeysWithValues: orderedKeys.compactMap { key in
            if let val = groups[key] {
                return (key, val)
            }
            return nil
        })
    }

    private func groupMissing(_ assignments: [Assignment]) -> [String: [Assignment]] {
        var groups: [String: [Assignment]] = [:]
        let cal = Calendar.current
        let today = Date()

        let thisWeekStart = startOfWeek(for: today)
        let thisWeekEnd = endOfWeek(for: today)
        groups["This Week"] = assignments.filter {
            let due = $0.dueDate
            return due >= thisWeekStart && due <= thisWeekEnd
        }

        if let lastWeekMonday = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) {
            let lastWeekStart = cal.startOfDay(for: lastWeekMonday)
            let lastWeekEnd = cal.date(bySettingHour: 23, minute: 59, second: 59, of: cal.date(byAdding: .day, value: 6, to: lastWeekMonday) ?? lastWeekStart) ?? lastWeekStart
            groups["Last Week"] = assignments.filter {
                let due = $0.dueDate
                return due >= lastWeekStart && due <= lastWeekEnd
            }
        } else {
            groups["Last Week"] = []
        }

        if let lastWeekMonday = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) {
            groups["Before"] = assignments.filter {
                let due = $0.dueDate
                return due < lastWeekMonday
            }
        } else {
            groups["Before"] = []
        }

        groups = groups.filter { !$0.value.isEmpty }

        let orderedKeys = ["This Week", "Last Week", "Before"]
        return Dictionary(uniqueKeysWithValues: orderedKeys.compactMap { key in
            if let val = groups[key] {
                return (key, val)
            }
            return nil
        })
    }

    private func groupDone(_ assignments: [Assignment]) -> [String: [Assignment]] {
        var groups: [String: [Assignment]] = [:]
        let cal = Calendar.current
        let today = Date()

        let thisWeekStart = startOfWeek(for: today)
        let thisWeekEnd = endOfWeek(for: today)
        groups["This Week"] = assignments.filter {
            let due = $0.dueDate
            return due >= thisWeekStart && due <= thisWeekEnd
        }

        if let lastWeekMonday = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) {
            let lastWeekStart = cal.startOfDay(for: lastWeekMonday)
            let lastWeekEnd = cal.date(bySettingHour: 23, minute: 59, second: 59, of: cal.date(byAdding: .day, value: 6, to: lastWeekMonday) ?? lastWeekStart) ?? lastWeekStart
            groups["Last Week"] = assignments.filter {
                let due = $0.dueDate
                return due >= lastWeekStart && due <= lastWeekEnd
            }
        } else {
            groups["Last Week"] = []
        }

        if let lastWeekMonday = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) {
            groups["Before"] = assignments.filter {
                let due = $0.dueDate
                return due < lastWeekMonday
            }
        } else {
            groups["Before"] = []
        }

        groups["No Due Date"] = assignments.filter { !$0.hasRealDueDate }

        groups = groups.filter { !$0.value.isEmpty }

        let orderedKeys = ["This Week", "Last Week", "Before", "No Due Date"]
        return Dictionary(uniqueKeysWithValues: orderedKeys.compactMap { key in
            if let val = groups[key] {
                return (key, val)
            }
            return nil
        })
    }

    private func sortedSectionKeys(for grouped: [String: [Assignment]], assignments: [Assignment]) -> [String] {
        func latestDueDate(in assignments: [Assignment]) -> Date? {
            assignments.compactMap { $0.hasRealDueDate ? $0.dueDate : nil }.max()
        }

        let keys = grouped.keys

        let noDueDateKeys = keys.filter { key in
            if key == "No Due Date" {
                return true
            }
            guard let sectionAssignments = grouped[key] else { return false }
            return sectionAssignments.allSatisfy { !$0.hasRealDueDate }
        }

        let dueDateKeys = keys.filter { !noDueDateKeys.contains($0) }

        let sortedDueDateKeys = dueDateKeys.sorted { a, b in
            let aDate = latestDueDate(in: grouped[a] ?? []) ?? Date.distantPast
            let bDate = latestDueDate(in: grouped[b] ?? []) ?? Date.distantPast
            return aDate > bDate
        }

        return sortedDueDateKeys + noDueDateKeys.sorted()
    }
}

// Removed duplicate AssignmentRow struct since likely defined elsewhere and to avoid redeclaration and complexity.

struct MissingFilterView: View {
    @Binding var filterDate: Date
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    DatePicker("Show assignments after", selection: $filterDate, displayedComponents: .date)

                    Button("Reset to 1 week ago") {
                        filterDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
                    }
                } header: {
                    Text("Filter Missing Assignments")
                } footer: {
                    Text("Only show missing assignments with due dates on or after this date.")
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct CompletedFilterView: View {
    @Binding var filterDate: Date
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    DatePicker("Show assignments after", selection: $filterDate, displayedComponents: .date)

                    Button("Reset to 1 week ago") {
                        filterDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
                    }

                    Button("Reset to 1 month ago") {
                        filterDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
                    }

                    Button("Reset to 3 months ago") {
                        filterDate = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
                    }
                } header: {
                    Text("Filter Completed Assignments")
                } footer: {
                    Text("Only show completed assignments with due dates on or after this date.")
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct ClassroomMultiSelectView: View {
    @Binding var classrooms: [GoogleClassroom]
    var onCancel: () -> Void
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Your Google Classroom courses")) {
                    ForEach($classrooms) { $c in
                        Toggle(isOn: $c.isSelected) {
                            Text(c.name.isEmpty ? "Untitled" : c.name)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Select Classrooms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSave(); dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Select All") { for i in classrooms.indices { classrooms[i].isSelected = true } }
                    Spacer()
                    Button("Deselect All") { for i in classrooms.indices { classrooms[i].isSelected = false } }
                }
            }
        }
    }
}

/// A view that allows the user to add a new assignment by entering title, description, due date, classroom, and category.
/// On save, it creates and adds a new Assignment to the assignmentsStore with the proper isCompleted state and due date based on the selected category.
/// The sheet dismisses automatically when the assignment is saved.
struct AddAssignmentView: View {
    @Binding var isPresented: Bool
    @ObservedObject var assignmentsStore: AssignmentsStore
    var classrooms: [GoogleClassroom]

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var dueDate: Date = Date()
    @State private var selectedClassroomIndex: Int = -1 // Default to -1 for "None"
    @State private var selectedCategory: Category = .incomplete

    enum Category: String, CaseIterable, Identifiable {
        case incomplete = "Incomplete"
        case missing = "Missing"
        case done = "Done"

        var id: String { rawValue }
    }

    @StateObject private var aiEstimator = AssignmentAIEstimator()
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Assignment Info")) {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description)
                    Picker("Classroom", selection: $selectedClassroomIndex) {
                        Text("None").tag(-1)
                        ForEach(classrooms.indices, id: \.self) { index in
                            Text(classrooms[index].name.isEmpty ? "Untitled" : classrooms[index].name).tag(index)
                        }
                    }
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(Category.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Add Assignment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            isSaving = true
                            Task {
                                await saveAssignment()
                            }
                        }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    @MainActor
    private func saveAssignment() async {
        let classroomName: String
        let courseId: String?

        if selectedClassroomIndex == -1 {
            classroomName = "None"
            courseId = nil
        } else if classrooms.indices.contains(selectedClassroomIndex) {
            classroomName = classrooms[selectedClassroomIndex].name
            courseId = classrooms[selectedClassroomIndex].id
        } else {
            classroomName = "None"
            courseId = nil
        }

        let now = Date()
        var assignmentDueDate = dueDate
        var isCompleted = false

        switch selectedCategory {
        case .incomplete:
            isCompleted = false
            if assignmentDueDate < now {
                assignmentDueDate = now
            }
        case .missing:
            isCompleted = false
            if assignmentDueDate >= now {
                assignmentDueDate = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
            }
        case .done:
            isCompleted = true
        }

        var aiEstimatedTime = 30
        var aiEstimatedImportance = 3

        if #available(iOS 26.0, *), aiEstimator.modelAvailable {
            let tempAssignment = Assignment(
                id: UUID(),
                title: title.trimmingCharacters(in: .whitespaces),
                dueDate: assignmentDueDate,
                classroom: classroomName,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                courseId: courseId,
                isCompleted: isCompleted,
                hasRealDueDate: true,
                aiEstimatedImportance: 3,
                aiEstimatedTime: 30
            )
            await aiEstimator.estimate(for: tempAssignment) { time, importance in
                aiEstimatedTime = time
                aiEstimatedImportance = importance
            }
        }

        let newAssignment = Assignment(
            id: UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            dueDate: assignmentDueDate,
            classroom: classroomName,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            courseId: courseId,
            isCompleted: isCompleted,
            hasRealDueDate: true,
            aiEstimatedImportance: aiEstimatedImportance,
            aiEstimatedTime: aiEstimatedTime
        )

        assignmentsStore.assignments.append(newAssignment)

        isSaving = false
        isPresented = false
    }
}

struct AssignmentEditSheet: View {
    @EnvironmentObject var assignmentsStore: AssignmentsStore
    @Environment(\.dismiss) var dismiss
    let assignment: Assignment

    @State private var newTitle: String
    @State private var newDescription: String
    @State private var newTime: Int
    @State private var newImportance: Int
    @State private var newDueDate: Date

    init(assignment: Assignment) {
        self.assignment = assignment
        _newTitle = State(initialValue: assignment.title)
        _newDescription = State(initialValue: assignment.description ?? "")
        _newTime = State(initialValue: assignment.aiEstimatedTime)
        _newImportance = State(initialValue: assignment.aiEstimatedImportance)
        _newDueDate = State(initialValue: assignment.hasRealDueDate ? assignment.dueDate : Date())
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // Title Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Title").font(.headline)
                        TextField("Title", text: $newTitle)
                            .textFieldStyle(.roundedBorder)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                    }

                    // Description Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description").font(.headline)
                        TextEditor(text: $newDescription)
                            .frame(minHeight: 120)
                            .padding(6)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.18), lineWidth: 1)
                            )
                    }

                    // Due Date Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Due Date").font(.headline)
                        if assignment.hasRealDueDate {
                            DatePicker("Due Date", selection: $newDueDate, displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .padding(8)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                        } else {
                            Label("No Due Date", systemImage: "calendar.badge.exclamationmark")
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                        }
                    }

                    // Estimated Time Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Estimated Time (minutes)").font(.headline)
                        TextField("Time (1-1440)", value: $newTime, format: .number)
                            .keyboardType(.numberPad)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                            .onChange(of: newTime) { _ in
                                if newTime < 1 { newTime = 1 }
                                if newTime > 1440 { newTime = 1440 }
                            }
                    }

                    // Importance Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Importance (1-5)").font(.headline)
                        TextField("Importance (1-5)", value: $newImportance, format: .number)
                            .keyboardType(.numberPad)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                            .onChange(of: newImportance) { _ in
                                if newImportance < 1 { newImportance = 1 }
                                if newImportance > 5 { newImportance = 5 }
                            }
                    }
                }
                .padding(.top, 32)
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .navigationTitle("Edit Assignment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let idx = assignmentsStore.assignments.firstIndex(where: { $0.id == assignment.id }) {
                            assignmentsStore.assignments[idx].title = newTitle
                            assignmentsStore.assignments[idx].description = newDescription
                            assignmentsStore.assignments[idx].aiEstimatedTime = min(max(newTime, 1), 1440)
                            assignmentsStore.assignments[idx].aiEstimatedImportance = min(max(newImportance, 1), 5)
                            if assignment.hasRealDueDate {
                                assignmentsStore.assignments[idx].dueDate = newDueDate
                            }
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - SettingsView new for dark mode toggle and classroom picker

struct SettingsView: View {
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

    @State private var localClassrooms: [GoogleClassroom]
    @State private var showClassroomPicker = false

    var onSaveClassrooms: ([GoogleClassroom]) -> Void

    @Environment(\.dismiss) private var dismiss

    init(localClassrooms: [GoogleClassroom], onSaveClassrooms: @escaping ([GoogleClassroom]) -> Void) {
        _localClassrooms = State(initialValue: localClassrooms)
        self.onSaveClassrooms = onSaveClassrooms
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("Dark Mode", isOn: $isDarkMode)
                } header: {
                    Text("Appearance")
                }
                Section {
                    Button("Select Classrooms") {
                        showClassroomPicker = true
                    }
                } header: {
                    Text("Classrooms")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showClassroomPicker) {
                ClassroomMultiSelectView(
                    classrooms: $localClassrooms,
                    onCancel: {
                        showClassroomPicker = false
                    },
                    onSave: {
                        onSaveClassrooms(localClassrooms)
                        showClassroomPicker = false
                    }
                )
            }
        }
    }
}

// MARK: - DateFormatter extension for schedule display

extension DateFormatter {
    static var shortDate: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }
}
