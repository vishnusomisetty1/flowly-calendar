import SwiftUI
import Foundation

enum ScheduleViewMode: String, CaseIterable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
}

struct ScheduleView: View {
    @EnvironmentObject var assignmentsStore: AssignmentsStore
    @EnvironmentObject var settings: ScheduleSettings
    @EnvironmentObject var scheduleManager: ScheduleManager
    @EnvironmentObject var classroomsStore: ClassroomsStore
    @EnvironmentObject var auth: AuthManager

    @State private var selectedViewMode: ScheduleViewMode = .day
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Settings/info panel
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Preferred Start Time:")
                        Spacer()
                        DatePicker("", selection: $settings.preferredStartTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    HStack {
                        Text("Preferred End Time:")
                        Spacer()
                        DatePicker("", selection: $settings.preferredEndTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.top, 8)

                // View mode picker
                Picker("View Mode", selection: $selectedViewMode) {
                    ForEach(ScheduleViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Content view based on selected mode
                Group {
                    switch selectedViewMode {
                    case .day:
                        DayScheduleView()
                            .environmentObject(assignmentsStore)
                            .environmentObject(scheduleManager)
                    case .week:
                        WeekScheduleView()
                            .environmentObject(assignmentsStore)
                            .environmentObject(scheduleManager)
                    case .month:
                        MonthScheduleView()
                            .environmentObject(assignmentsStore)
                            .environmentObject(scheduleManager)
                    }
                }
            }
            .navigationTitle("Schedule")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign Out") {
                        print("DEBUG: Sign out pressed")
                        auth.signOut()
                        // Optional: cancel any running Tasks if needed
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        scheduleManager.forceRegenerate()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    localClassrooms: classroomsStore.allClassrooms,
                    onSaveClassrooms: { selected in
                        classroomsStore.allClassrooms = selected
                        classroomsStore.rememberSelection(from: selected)
                        Task {
                            await assignmentsStore.refreshAssignments(forSelectedClassrooms: selected, auth: auth)
                            scheduleManager.forceRegenerate()
                        }
                    }
                )
                .environmentObject(assignmentsStore)
                .environmentObject(settings)
                .environmentObject(scheduleManager)
                .environmentObject(classroomsStore)
            }
        }
    }
}

fileprivate extension ScheduleView {
    struct RiskLabel: View {
        let text: String
        let backgroundColor: Color

        var body: some View {
            Text(text)
                .padding(4)
                .background(backgroundColor)
                .foregroundColor(.white)
                .cornerRadius(4)
                .font(.caption)
        }
    }
}

#if DEBUG
#Preview {
    ScheduleView()
        .environmentObject(AssignmentsStore())
        .environmentObject(ScheduleSettings())
        .environmentObject(ScheduleManager(assignments: [], settings: ScheduleSettings()))
        .environmentObject(ClassroomsStore())
}
#endif
