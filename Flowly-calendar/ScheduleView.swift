import SwiftUI

enum ScheduleViewMode: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week", month = "Month"
    var id: String { rawValue }
}

struct ScheduleScreen: View {
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var classroomsStore: ClassroomsStore
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var userStore: UserStore

    @Binding var user: User
    @Binding var scheduleItems: [ScheduleItem]
    @Binding var assignments: [Assignment]
    @Binding var reminders: [Reminder]
    @Binding var selectedDate: Date
    var classrooms: [GoogleClassroom]
    @Binding var currentScreen: ContentView.Screen

    @State private var viewMode: ScheduleViewMode = .day
    @State private var showAddTask = false
    @State private var showSettings = false
    @State private var newTaskTitle = ""
    @State private var newTaskDuration = 30
    @State private var isSyncing = false
    @State private var syncError: String?

    private let classroomScopes = [
        "https://www.googleapis.com/auth/classroom.courses.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.me.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.me"
    ]

    var body: some View {
        ZStack {
            theme.bgColor.ignoresSafeArea()
            VStack(spacing: 12) {
                header

                if let syncError {
                    Text(syncError).font(.footnote).foregroundColor(.red).padding(.horizontal)
                }

                Picker("", selection: $viewMode) {
                    ForEach(ScheduleViewMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch viewMode {
                case .day:
                    DayView(scheduleItems: $scheduleItems, selectedDate: $selectedDate, reminders: $reminders)
                case .week:
                    WeekView(scheduleItems: $scheduleItems, selectedDate: $selectedDate, reminders: $reminders)
                        .frame(maxHeight: .infinity)
                case .month:
                    MonthView(scheduleItems: $scheduleItems, selectedDate: $selectedDate)
                        .frame(maxHeight: .infinity)
                }

                Button { showAddTask = true } label: {
                    HStack { Image(systemName: "plus.circle.fill"); Text("Add Custom Task").font(.headline) }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.blue).cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(currentScreen: $currentScreen)
                .environmentObject(theme)
                .environmentObject(userStore)
                .environmentObject(auth)
                .environmentObject(classroomsStore)
        }
        .sheet(isPresented: $showAddTask) {
            AddTaskSheet(isPresented: $showAddTask,
                         scheduleItems: $scheduleItems,
                         newTaskTitle: $newTaskTitle,
                         newTaskDuration: $newTaskDuration)
        }
        .task { await autoSyncIfNeeded() }              // pulls Classroom once
        .onChangeCompat(assignments) { _, newValue in
            if !newValue.isEmpty { generateAISchedule() }
        }
        .onChangeCompat(reminders) { _, newValue in
            if !newValue.isEmpty { generateAISchedule() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Flowly Calendar").font(.title2).fontWeight(.bold)
                Text(selectedDate.formatted(date: .abbreviated, time: .omitted)).foregroundColor(.gray)
            }
            Spacer()
            if isSyncing { ProgressView().scaleEffect(0.9) }
            Button(action: { Task { await manualRefresh() } }) { Image(systemName: "arrow.clockwise") }
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
        }
        .padding(.horizontal)
    }

    // MARK: Logic

    private func generateAISchedule() {
        assignments = assignments.map { AIEstimator.annotate($0, user: user) }
        scheduleItems = ScheduleGenerator.generateWeek(user: user, assignments: assignments, from: Date())
    }

    private func autoSyncIfNeeded() async {
        guard assignments.isEmpty && reminders.isEmpty else { return }
        guard classroomsStore.hasChosenOnce, !classroomsStore.allClassrooms.isEmpty else { return }

        isSyncing = true; syncError = nil
        do {
            let (token, email) = try await auth.getFreshAccessToken(requiredScopes: classroomScopes)
            user.googleToken = token
            if user.googleEmail.isEmpty { user.googleEmail = email }

            let fetchedAssignments = try await AssignmentSync.fetchForSelectedClasses(token: token, classes: classroomsStore.allClassrooms)
            let fetchedReminders = try await AssignmentSync.fetchRemindersForSelectedClasses(token: token, classes: classroomsStore.allClassrooms)
            assignments = fetchedAssignments
            reminders = fetchedReminders
            isSyncing = false
        } catch {
            syncError = "Sync failed: \(error.localizedDescription)"
            isSyncing = false
        }
    }

    private func manualRefresh() async {
        assignments.removeAll()
        reminders.removeAll()
        await autoSyncIfNeeded()
    }
}

// MARK: - Day / Week / Month

private struct DayView: View {
    @Binding var scheduleItems: [ScheduleItem]
    @Binding var selectedDate: Date
    @Binding var reminders: [Reminder]

    private var dayItems: [ScheduleItem] {
        scheduleItems.filter { Calendar.current.isDate($0.startTime, inSameDayAs: selectedDate) }
            .sorted { $0.startTime < $1.startTime }
    }
    
    // Assignment subcategories
    private var activeAssignments: [ScheduleItem] {
        dayItems.filter { item in
            let isActuallyCompleted = item.isCompleted || (item.associatedAssignment?.isCompleted ?? false)
            return !isActuallyCompleted && !isOverdue(item: item)
        }
    }
    
    private var completedAssignments: [ScheduleItem] {
        dayItems.filter { item in
            let isActuallyCompleted = item.isCompleted || (item.associatedAssignment?.isCompleted ?? false)
            return isActuallyCompleted
        }
    }
    
    private var missingAssignments: [ScheduleItem] {
        dayItems.filter { item in
            let isActuallyCompleted = item.isCompleted || (item.associatedAssignment?.isCompleted ?? false)
            return !isActuallyCompleted && isOverdue(item: item)
        }
    }
    
    // Reminder subcategories
    private var activeReminders: [Reminder] {
        reminders.filter { !$0.isCompleted && !isMissing(reminder: $0) }
    }
    
    private var completedReminders: [Reminder] {
        reminders.filter { $0.isCompleted }
    }
    
    private var missingReminders: [Reminder] {
        reminders.filter { !$0.isCompleted && isMissing(reminder: $0) }
    }
    
    private func isOverdue(item: ScheduleItem) -> Bool {
        guard let assignment = item.associatedAssignment else { return false }
        return assignment.dueDate < Date()
    }
    
    private func isMissing(reminder: Reminder) -> Bool {
        return reminder.eventDate < Date()
    }

    var body: some View {
        VStack(spacing: 8) {
            DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .padding(.horizontal)

            ScrollView {
                VStack(spacing: 16) {
                    // ASSIGNMENTS SECTION
                    VStack(alignment: .leading, spacing: 12) {
                        if !dayItems.isEmpty {
                            Text("Assignments")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)
                            
                            // Active Assignments (not completed, not overdue)
                            ForEach($scheduleItems) { $item in
                                if Calendar.current.isDate(item.startTime, inSameDayAs: selectedDate) && 
                                   !item.isCompleted && !isOverdue(item: item) {
                                    ScheduleItemRow(item: $item)
                                }
                            }
                            .padding(.horizontal)
                            
                            // Missing Assignments (overdue)
                            ForEach($scheduleItems) { $item in
                                if Calendar.current.isDate(item.startTime, inSameDayAs: selectedDate) && 
                                   isOverdue(item: item) {
                                    ScheduleItemRow(item: $item)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // COMPLETED ASSIGNMENTS SECTION
                    VStack(alignment: .leading, spacing: 10) {
                        if !completedAssignments.isEmpty {
                            Divider()
                                .padding(.vertical, 8)
                            
                            Text("Completed Assignments")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)
                            
                            ForEach($scheduleItems) { $item in
                                if Calendar.current.isDate(item.startTime, inSameDayAs: selectedDate) {
                                    let isActuallyCompleted = item.isCompleted || (item.associatedAssignment?.isCompleted ?? false)
                                    if isActuallyCompleted {
                                        ScheduleItemRow(item: $item)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // COMPLETED ASSIGNMENTS SECTION
                    VStack(alignment: .leading, spacing: 10) {
                        if !completedAssignments.isEmpty {
                            Divider()
                                .padding(.vertical, 8)
                            
                            Text("Completed Assignments")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)
                            
                            ForEach($scheduleItems) { $item in
                                if Calendar.current.isDate(item.startTime, inSameDayAs: selectedDate) {
                                    let isActuallyCompleted = item.isCompleted || (item.associatedAssignment?.isCompleted ?? false)
                                    if isActuallyCompleted {
                                        ScheduleItemRow(item: $item)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // REMINDERS SECTION
                    if !reminders.isEmpty {
                        Divider()
                            .padding(.vertical, 8)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Reminders")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Image(systemName: "star.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text("(\(reminders.count))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                            
                            // Active Reminders (not completed, not past event date)
                            ForEach(reminders.indices, id: \.self) { index in
                                if !reminders[index].isCompleted && !isMissing(reminder: reminders[index]) {
                                    ReminderRow(reminder: $reminders[index])
                                        .padding(.horizontal)
                                }
                            }
                            
                            // Missing Reminders (not completed, past event date)
                            ForEach(reminders.indices, id: \.self) { index in
                                if !reminders[index].isCompleted && isMissing(reminder: reminders[index]) {
                                    ReminderRow(reminder: $reminders[index])
                                        .padding(.horizontal)
                                }
                            }
                            
                            // Completed Reminders
                            ForEach(reminders.indices, id: \.self) { index in
                                if reminders[index].isCompleted {
                                    ReminderRow(reminder: $reminders[index])
                                        .padding(.horizontal)
                                }
                            }
                        }
                    }
                    
                    if dayItems.isEmpty && reminders.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            Text("No schedule for this day")
                                .font(.headline)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                        .padding()
                    }
                }
                .padding(.vertical)
            }
        }
    }
}

private struct WeekView: View {
    @Binding var scheduleItems: [ScheduleItem]
    @Binding var selectedDate: Date
    @Binding var reminders: [Reminder]

    private let cal = Calendar.current
    private var startOfDisplayedWeek: Date {
        let base = selectedDate
        return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: base)) ?? base
    }
    private var days: [Date] { (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: startOfDisplayedWeek) } }
    
    private var dayItems: [ScheduleItem] {
        scheduleItems.filter { cal.isDate($0.startTime, inSameDayAs: selectedDate) }
            .sorted { $0.startTime < $1.startTime }
    }
    
    // Assignment subcategories
    private var activeAssignments: [ScheduleItem] {
        scheduleItems.filter { item in
            // Check if the assignment is within the current week
            let isInWeek = days.contains { day in
                cal.isDate(item.startTime, inSameDayAs: day)
            }
            let isActuallyCompleted = item.isCompleted || (item.associatedAssignment?.isCompleted ?? false)
            return isInWeek && !isActuallyCompleted && !isOverdue(item: item)
        }
    }
    
    private var completedAssignments: [ScheduleItem] {
        scheduleItems.filter { item in
            // Check if the assignment is within the current week
            let isInWeek = days.contains { day in
                cal.isDate(item.startTime, inSameDayAs: day)
            }
            let isActuallyCompleted = item.isCompleted || (item.associatedAssignment?.isCompleted ?? false)
            return isInWeek && isActuallyCompleted
        }
    }
    
    private var missingAssignments: [ScheduleItem] {
        scheduleItems.filter { item in
            // Check if the assignment is within the current week
            let isInWeek = days.contains { day in
                cal.isDate(item.startTime, inSameDayAs: day)
            }
            let isActuallyCompleted = item.isCompleted || (item.associatedAssignment?.isCompleted ?? false)
            return isInWeek && !isActuallyCompleted && isOverdue(item: item)
        }
    }
    
    // Reminder subcategories
    private var activeReminders: [Reminder] {
        reminders.filter { !$0.isCompleted && !isMissing(reminder: $0) }
    }
    
    private var completedReminders: [Reminder] {
        reminders.filter { $0.isCompleted }
    }
    
    private var missingReminders: [Reminder] {
        reminders.filter { !$0.isCompleted && isMissing(reminder: $0) }
    }
    
    private func isOverdue(item: ScheduleItem) -> Bool {
        guard let assignment = item.associatedAssignment else { return false }
        return assignment.dueDate < Date()
    }
    
    private func isMissing(reminder: Reminder) -> Bool {
        return reminder.eventDate < Date()
    }

    var body: some View {
        VStack(spacing: 16) {
            // Week navigation header
            HStack {
                Button {
                    let previousWeek = cal.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
                    selectedDate = previousWeek
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.blue)
                }

                Spacer()

                Text(startOfDisplayedWeek.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()

                Button {
                    let nextWeek = cal.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
                    selectedDate = nextWeek
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(days, id: \.self) { d in
                        let isSel = cal.isDate(d, inSameDayAs: selectedDate)
                        Button { selectedDate = d } label: {
                            VStack(spacing: 6) {
                                Text(d.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                Text("\(cal.component(.day, from: d))")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .frame(width: 50, height: 60)
                            .background(isSel ? Color.blue : Color(.systemGray6))
                            .foregroundColor(isSel ? .white : .primary)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal)
            }

            let dayItems = scheduleItems
                .filter { cal.isDate($0.startTime, inSameDayAs: selectedDate) }
                .sorted { $0.startTime < $1.startTime }

            ScrollView {
                VStack(spacing: 16) {
                    // ASSIGNMENTS SECTION
                    VStack(alignment: .leading, spacing: 12) {
                        if !dayItems.isEmpty {
                            Text("Assignments")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)
                            
                            // Active Assignments (not completed, not overdue)
                            ForEach($scheduleItems) { $item in
                                // Check if the assignment is within the current week
                                let isInWeek = days.contains { day in
                                    cal.isDate(item.startTime, inSameDayAs: day)
                                }
                                if isInWeek && !item.isCompleted && !isOverdue(item: item) {
                                    ScheduleItemRow(item: $item)
                                }
                            }
                            .padding(.horizontal)
                            
                            // Missing Assignments (overdue)
                            ForEach($scheduleItems) { $item in
                                // Check if the assignment is within the current week
                                let isInWeek = days.contains { day in
                                    cal.isDate(item.startTime, inSameDayAs: day)
                                }
                                if isInWeek && isOverdue(item: item) {
                                    ScheduleItemRow(item: $item)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // COMPLETED ASSIGNMENTS SECTION
                    VStack(alignment: .leading, spacing: 10) {
                        if !completedAssignments.isEmpty {
                            Divider()
                                .padding(.vertical, 8)
                            
                            Text("Completed Assignments")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)
                            
                            ForEach($scheduleItems) { $item in
                                // Check if the assignment is within the current week
                                let isInWeek = days.contains { day in
                                    cal.isDate(item.startTime, inSameDayAs: day)
                                }
                                let isActuallyCompleted = item.isCompleted || (item.associatedAssignment?.isCompleted ?? false)
                                if isInWeek && isActuallyCompleted {
                                    ScheduleItemRow(item: $item)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // REMINDERS SECTION
                    if !reminders.isEmpty {
                        Divider()
                            .padding(.vertical, 8)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Reminders")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Image(systemName: "star.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text("(\(reminders.count))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                            
                            // Active Reminders (not completed, not past event date)
                            ForEach(reminders.indices, id: \.self) { index in
                                if !reminders[index].isCompleted && !isMissing(reminder: reminders[index]) {
                                    ReminderRow(reminder: $reminders[index])
                                        .padding(.horizontal)
                                }
                            }
                            
                            // Missing Reminders (not completed, past event date)
                            ForEach(reminders.indices, id: \.self) { index in
                                if !reminders[index].isCompleted && isMissing(reminder: reminders[index]) {
                                    ReminderRow(reminder: $reminders[index])
                                        .padding(.horizontal)
                                }
                            }
                            
                            // Completed Reminders
                            ForEach(reminders.indices, id: \.self) { index in
                                if reminders[index].isCompleted {
                                    ReminderRow(reminder: $reminders[index])
                                        .padding(.horizontal)
                                }
                            }
                        }
                    }
                    
                    if dayItems.isEmpty && reminders.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            Text("No schedule for this day")
                                .font(.headline)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                        .padding()
                    }
                }
                .padding(.vertical)
            }
        }
    }
}

private struct MonthView: View {
    @Binding var scheduleItems: [ScheduleItem]
    @Binding var selectedDate: Date

    @State private var showDayPopup = false
    @State private var popupDate: Date = Date()

    private let cal = Calendar.current

    private var monthStart: Date {
        let comps = cal.dateComponents([.year, .month], from: selectedDate)
        return cal.date(from: comps) ?? selectedDate
    }

    private var gridDays: [Date] {
        let firstWeekday = cal.component(.weekday, from: monthStart) - cal.firstWeekday
        let leading = (firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -leading, to: monthStart)!
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private func hasItem(on day: Date) -> Bool {
        scheduleItems.contains { cal.isDate($0.startTime, inSameDayAs: day) }
    }

    private var popupScheduleItems: [ScheduleItem] {
        scheduleItems.filter { cal.isDate($0.startTime, inSameDayAs: popupDate) }
            .sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Month navigation header
            HStack {
                Button {
                    let previousMonth = cal.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
                    selectedDate = previousMonth
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.blue)
                }

                Spacer()

                Text(monthStart.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()

                Button {
                    let nextMonth = cal.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
                    selectedDate = nextMonth
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)

            let syms = cal.shortWeekdaySymbols
            HStack {
                ForEach(syms, id: \.self) { s in
                    Text(s)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(gridDays, id: \.self) { day in
                    let isCurrentMonth = cal.isDate(day, equalTo: monthStart, toGranularity: .month)
                    let isSelected = cal.isDate(day, inSameDayAs: selectedDate)
                    Button {
                        selectedDate = day
                        if hasItem(on: day) {
                            popupDate = day
                            showDayPopup = true
                        }
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? Color.blue : Color(.systemGray6))
                                .frame(height: 60)
                            Text("\(cal.component(.day, from: day))")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(isSelected ? .white : (isCurrentMonth ? .primary : .secondary))
                                .padding(8)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            if hasItem(on: day) {
                                Circle().fill(isSelected ? Color.white : Color.blue)
                                    .frame(width: 8, height: 8)
                                    .padding(8)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $showDayPopup) {
            DaySchedulePopup(
                date: popupDate,
                scheduleItems: popupScheduleItems,
                isPresented: $showDayPopup
            )
        }
    }
}

// MARK: - Day Schedule Popup

private struct DaySchedulePopup: View {
    let date: Date
    let scheduleItems: [ScheduleItem]
    @Binding var isPresented: Bool

    private let cal = Calendar.current

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                if scheduleItems.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("No schedule for this day")
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(scheduleItems, id: \.id) { item in
                                ScheduleItemRow(item: .constant(item))
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(dateString)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - Row + Add task

private struct ScheduleItemRow: View {
    @Binding var item: ScheduleItem

    private var timeString: String {
        let f = DateFormatter(); f.timeStyle = .short
        return f.string(from: item.startTime)
    }

    private var courseName: String? {
        if let course = item.associatedAssignment?.classroom
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !course.isEmpty {
            return course
        }
        return nil
    }

    private var dueDateString: String? {
        guard let assignment = item.associatedAssignment else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone.current // Ensure local timezone
        return "Due: \(formatter.string(from: assignment.dueDate))"
    }

    private var isOverdue: Bool {
        guard let assignment = item.associatedAssignment else { return false }
        return assignment.dueDate < Date()
    }
    
    private var isActuallyCompleted: Bool {
        // For assignments, check both schedule item completion AND assignment completion
        if let assignment = item.associatedAssignment {
            return item.isCompleted || assignment.isCompleted
        }
        // For reminders, just check schedule item completion
        return item.isCompleted
    }
    
    private var isReminder: Bool {
        return item.type == "reminder"
    }
    
    private var reminderEventDate: String? {
        guard isReminder else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone.current
        return "Event: \(formatter.string(from: item.startTime))"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(timeString).font(.caption).bold()
                Image(systemName: (isActuallyCompleted || (isOverdue && !isReminder)) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(
                        isReminder ? 
                            (item.isCompleted ? .orange : .gray) :
                            ((isActuallyCompleted || isOverdue) ? .green : .gray)
                    )
            }
            .frame(width: 56)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)
                    .foregroundColor(
                        isReminder ? 
                            (isOverdue ? .red : .primary) :
                            (isActuallyCompleted ? .primary : (isOverdue ? .red : .primary))
                    )
                    .strikethrough(isActuallyCompleted || (isOverdue && !isReminder))

                HStack(spacing: 6) {
                    Text(item.type.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let course = courseName {
                        Text(course)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                            .lineLimit(1)
                    }
                }

                // Show due date for assignments or event date for reminders
                if let dueDate = dueDateString {
                    Text(dueDate)
                        .font(.caption2)
                        .foregroundColor(isOverdue ? .red : .secondary)
                        .fontWeight(isOverdue ? .semibold : .regular)
                } else if let eventDate = reminderEventDate {
                    Text(eventDate)
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .fontWeight(.medium)
                }
            }
            Spacer()
        }
        .padding()
        .background(
            isReminder ? 
                (item.isCompleted ? Color.orange.opacity(0.1) : Color.orange.opacity(0.05)) :
                (isActuallyCompleted || isOverdue ? Color.green.opacity(0.1) : Color(.systemGray6))
        )
        .cornerRadius(10)
        .onTapGesture {
            if isReminder {
                // For reminders, always allow completion toggle
                item.isCompleted.toggle()
            } else if !isOverdue {
                // For assignments, only allow completion if not overdue
                item.isCompleted.toggle()
            }
        }
    }
}

private struct AddTaskSheet: View {
    @Binding var isPresented: Bool
    @Binding var scheduleItems: [ScheduleItem]
    @Binding var newTaskTitle: String
    @Binding var newTaskDuration: Int
    @State private var selectedTime = Date()

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Add Custom Task").font(.headline)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Task Title").font(.headline)
                TextField("Enter task name", text: $newTaskTitle).textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Start Time").font(.headline)
                DatePicker("", selection: $selectedTime, displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.compact)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Duration (minutes)").font(.headline)
                Stepper(value: $newTaskDuration, in: 15...180, step: 15) {
                    Text("\(newTaskDuration) minutes")
                }
            }

            Button {
                guard !newTaskTitle.isEmpty else { return }
                let endTime = Calendar.current.date(byAdding: .minute, value: newTaskDuration, to: selectedTime) ?? selectedTime
                scheduleItems.append(ScheduleItem(title: newTaskTitle, startTime: selectedTime, endTime: endTime, type: "task"))
                newTaskTitle = ""; newTaskDuration = 30; isPresented = false
            } label: {
                Text("Add Task").frame(maxWidth: .infinity).padding()
                    .background(Color.blue).foregroundColor(.white).cornerRadius(10)
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

// MARK: - Reminder Row

private struct ReminderRow: View {
    @Binding var reminder: Reminder
    
    private var timeString: String {
        let f = DateFormatter(); f.timeStyle = .short
        return f.string(from: reminder.eventDate)
    }
    
    private var eventDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone.current
        return "Event: \(formatter.string(from: reminder.eventDate))"
    }
    
    private var isOverdue: Bool {
        return reminder.eventDate < Date()
    }
    
    private var reminderIcon: String {
        switch reminder.reminderType {
        case .meeting: return "👥"
        case .deadline: return "⏰"
        case .event: return "📅"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(timeString).font(.caption).bold()
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(reminder.isCompleted ? .orange : .gray)
            }
            .frame(width: 56)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("\(reminderIcon) \(reminder.title)")
                    .font(.headline)
                    .foregroundColor(isOverdue ? .red : .primary)
                    .strikethrough(reminder.isCompleted)
                
                HStack(spacing: 6) {
                    Text(reminder.reminderType.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(reminder.classroom)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .cornerRadius(6)
                        .lineLimit(1)
                }
                
                Text(eventDateString)
                    .font(.caption2)
                    .foregroundColor(isOverdue ? .red : .orange)
                    .fontWeight(.medium)
            }
            Spacer()
        }
        .padding()
        .background(
            reminder.isCompleted ? Color.orange.opacity(0.1) : Color.orange.opacity(0.05)
        )
        .cornerRadius(10)
        .onTapGesture {
            // For reminders, always allow completion toggle
            reminder.isCompleted.toggle()
        }
    }
}
