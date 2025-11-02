import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var classroomsStore: ClassroomsStore
    @EnvironmentObject private var assignmentsStore: AssignmentsStore

    @State private var user = User()
    @State private var currentScreen: Screen = .welcome

    enum Screen { case welcome, googleSignIn, classroomSelection, assignments }

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
        .onAppear { auth.restorePreviousSignIn() }
        .onChangeCompat(auth.isSignedIn) { _, _ in routeIfPossible() }
        .onChangeCompat(classroomsStore.hasChosenOnce) { _, _ in routeIfPossible() }
    }

    private func routeIfPossible() {
        if !auth.isSignedIn { currentScreen = .googleSignIn; return }
        if !classroomsStore.hasChosenOnce || classroomsStore.allClassrooms.isEmpty {
            currentScreen = .classroomSelection
        } else {
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
    @Binding var currentScreen: ContentView.Screen
    
    var body: some View {
        TabView {
            AssignmentsView(currentScreen: $currentScreen)
                .tabItem {
                    Label("Assignments", systemImage: "list.bullet")
                }
            
            ScheduleView()
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }
            
            MonthView()
                .tabItem {
                    Label("Month", systemImage: "calendar.badge.clock")
                }
        }
    }
}

struct AssignmentsView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var assignmentsStore: AssignmentsStore
    @EnvironmentObject private var classroomsStore: ClassroomsStore
    
    @Binding var currentScreen: ContentView.Screen
    
    @State private var isRefreshing = false
    @State private var missingFilterDate: Date = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
    @State private var showMissingFilter = false
    @State private var completedFilterDate: Date = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
    @State private var showCompletedFilter = false
    
    private let classroomScopes = [
        "https://www.googleapis.com/auth/classroom.courses.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.me.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.me"
    ]
    
    var body: some View {
        NavigationView {
            List {
                let missing = assignmentsStore.missingAssignments(filteredAfter: missingFilterDate)
                let incomplete = assignmentsStore.incompleteAssignments
                let others = assignmentsStore.otherAssignments
                let completed = assignmentsStore.completedAssignments(filteredAfter: completedFilterDate)
                
                if missing.isEmpty && incomplete.isEmpty && others.isEmpty && completed.isEmpty {
                    Text("No assignments found. Pull to refresh.")
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    // Missing: Past due, not completed (has real due date)
                    if !missing.isEmpty {
                        Section {
                            ForEach(missing) { assignment in
                                AssignmentRow(
                                    assignment: assignment,
                                    onToggleComplete: {
                                        assignmentsStore.toggleCompletion(for: assignment.id)
                                    },
                                    onUpdateDuration: { minutes in
                                        assignmentsStore.updateDuration(for: assignment.id, minutes: minutes)
                                    },
                                    onUpdatePoints: { points in
                                        assignmentsStore.updatePoints(for: assignment.id, points: points)
                                    }
                                )
                            }
                        } header: {
                            HStack {
                                Text("Missing (\(missing.count))")
                                    .foregroundColor(.red)
                                Spacer()
                                Button(action: { showMissingFilter.toggle() }) {
                                    Image(systemName: "calendar")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    
                    // Incomplete: Not yet due, not completed (has real due date)
                    if !incomplete.isEmpty {
                        Section {
                            ForEach(incomplete) { assignment in
                                AssignmentRow(
                                    assignment: assignment,
                                    onToggleComplete: {
                                        assignmentsStore.toggleCompletion(for: assignment.id)
                                    },
                                    onUpdateDuration: { minutes in
                                        assignmentsStore.updateDuration(for: assignment.id, minutes: minutes)
                                    },
                                    onUpdatePoints: { points in
                                        assignmentsStore.updatePoints(for: assignment.id, points: points)
                                    }
                                )
                            }
                        } header: {
                            Text("Incomplete (\(incomplete.count))")
                        }
                    }
                    
                    // Others: No due date, not completed
                    if !others.isEmpty {
                        Section {
                            ForEach(others) { assignment in
                                AssignmentRow(
                                    assignment: assignment,
                                    onToggleComplete: {
                                        assignmentsStore.toggleCompletion(for: assignment.id)
                                    },
                                    onUpdateDuration: { minutes in
                                        assignmentsStore.updateDuration(for: assignment.id, minutes: minutes)
                                    },
                                    onUpdatePoints: { points in
                                        assignmentsStore.updatePoints(for: assignment.id, points: points)
                                    }
                                )
                            }
                        } header: {
                            Text("Others (\(others.count))")
                        }
                    }
                    
                    // Completed: Turned in or marked as done
                    if !completed.isEmpty {
                        Section {
                            ForEach(completed) { assignment in
                                AssignmentRow(
                                    assignment: assignment,
                                    onToggleComplete: {
                                        assignmentsStore.toggleCompletion(for: assignment.id)
                                    },
                                    onUpdateDuration: { minutes in
                                        assignmentsStore.updateDuration(for: assignment.id, minutes: minutes)
                                    },
                                    onUpdatePoints: { points in
                                        assignmentsStore.updatePoints(for: assignment.id, points: points)
                                    }
                                )
                            }
                        } header: {
                            HStack {
                                Text("Completed (\(completed.count))")
                                    .foregroundColor(.green)
                                Spacer()
                                Button(action: { showCompletedFilter.toggle() }) {
                                    Image(systemName: "calendar")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
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
                if assignmentsStore.assignments.isEmpty {
                    Task { await refreshAssignments() }
                }
            }
            .sheet(isPresented: $showMissingFilter) {
                MissingFilterView(filterDate: $missingFilterDate)
            }
            .sheet(isPresented: $showCompletedFilter) {
                CompletedFilterView(filterDate: $completedFilterDate)
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
                assignmentsStore.replace(with: fetched)
                assignmentsStore.load(for: auth.email)
            }
        } catch {
            // Silently handle errors for simplicity
        }
        
        isRefreshing = false
    }
}

struct AssignmentRow: View {
    let assignment: Assignment
    let onToggleComplete: () -> Void
    let onUpdateDuration: (Int?) -> Void
    let onUpdatePoints: (Int?) -> Void
    
    @State private var isEditingDuration = false
    @State private var durationText = ""
    @State private var isEditingPoints = false
    @State private var pointsText = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(action: onToggleComplete) {
                    Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(assignment.isCompleted ? .green : .gray)
                        .font(.title3)
                }
                .buttonStyle(PlainButtonStyle())
                
                Text(assignment.title)
                    .font(.headline)
                
                Spacer()
            }
            
            Text(assignment.classroom)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if assignment.hasRealDueDate {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text(formatDate(assignment.dueDate))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack {
                    Image(systemName: "calendar.badge.questionmark")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("No due date")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Duration and Points input - only show if not completed
            if !assignment.isCompleted {
                HStack(spacing: 16) {
                    // Duration
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.purple)
                            .font(.caption)
                        
                        if isEditingDuration {
                            HStack {
                                TextField("Min", text: $durationText)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                
                                Button("Save") {
                                    let minutes = Int(durationText)
                                    onUpdateDuration(minutes)
                                    isEditingDuration = false
                                    updateDurationText()
                                }
                                .font(.caption2)
                                
                                Button("X") {
                                    isEditingDuration = false
                                    updateDurationText()
                                }
                                .font(.caption2)
                                .foregroundColor(.red)
                            }
                        } else {
                            Button(action: { isEditingDuration = true }) {
                                if let duration = assignment.durationMinutes {
                                    Text("\(duration) min")
                                        .font(.caption)
                                        .foregroundColor(.purple)
                                } else {
                                    Text("Time")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                    
                    // Points
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        
                        if isEditingPoints {
                            HStack {
                                TextField("Pts", text: $pointsText)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                
                                Button("Save") {
                                    let points = Int(pointsText)
                                    onUpdatePoints(points)
                                    isEditingPoints = false
                                    updatePointsText()
                                }
                                .font(.caption2)
                                
                                Button("X") {
                                    isEditingPoints = false
                                    updatePointsText()
                                }
                                .font(.caption2)
                                .foregroundColor(.red)
                            }
                        } else {
                            Button(action: { isEditingPoints = true }) {
                                if let points = assignment.points {
                                    Text("\(points) pts")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                } else {
                                    Text("Points")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            updateDurationText()
            updatePointsText()
        }
    }
    
    private func updateDurationText() {
        durationText = assignment.durationMinutes.map { String($0) } ?? ""
    }
    
    private func updatePointsText() {
        pointsText = assignment.points.map { String($0) } ?? ""
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

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
