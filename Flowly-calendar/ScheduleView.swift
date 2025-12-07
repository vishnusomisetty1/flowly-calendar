import SwiftUI
import Foundation

struct ScheduleView: View {
    @EnvironmentObject var assignmentsStore: AssignmentsStore
    @EnvironmentObject var settings: ScheduleSettings
    @State private var plannedDays: [PlannedDay] = []

    private var daysWithValidBlocks: [PlannedDay] {
        plannedDays.filter { day in
            day.assignmentBlocks.contains {
                ($0.preferredHours > 0 || $0.overflowHours > 0 || ($0.preferredHours == 0 && $0.overflowHours == 0)) &&
                $0.endTime > $0.startTime &&
                $0.endTime.timeIntervalSince($0.startTime) >= 60
            }
        }
    }

    private var blocksByDay: [Date: [DailyAssignmentBlock]] {
        var dict: [Date: [DailyAssignmentBlock]] = [:]
        for day in daysWithValidBlocks {
            let validBlocks = day.assignmentBlocks.filter {
                ($0.preferredHours > 0 || $0.overflowHours > 0 || ($0.preferredHours == 0 && $0.overflowHours == 0)) &&
                $0.endTime > $0.startTime &&
                $0.endTime.timeIntervalSince($0.startTime) >= 60
            }
            dict[day.date] = validBlocks
        }
        return dict
    }
    

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Settings/info panel
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Preferred Start Time:")
                    Spacer()
                    if let _ = Optional(settings.preferredStartTime) {
                        DatePicker("", selection: Binding(
                            get: { settings.preferredStartTime },
                            set: { newValue in
                                settings.preferredStartTime = newValue
                                generateSchedule()
                            }
                        ), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    } else {
                        Text("Not set")
                    }
                }
                HStack {
                    Text("Preferred End Time:")
                    Spacer()
                    if let _ = Optional(settings.preferredEndTime) {
                        DatePicker("", selection: Binding(
                            get: { settings.preferredEndTime },
                            set: { newValue in
                                settings.preferredEndTime = newValue
                                generateSchedule()
                            }
                        ), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    } else {
                        Text("Not set")
                    }
                }
                // Added Load Bias slider section
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Load Bias: \(settings.loadBias, specifier: "%.2f")")
                        Spacer()
                    }
                    Slider(value: Binding(
                        get: { settings.loadBias },
                        set: { newValue in
                            settings.loadBias = min(max(newValue, 0.5), 1.5)
                            generateSchedule()
                        }
                    ), in: 0.5...1.5, step: 0.01)
                    Text("1.00 = balanced, <1.00 = front-load, >1.00 = back-load")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(daysWithValidBlocks, id: \.date) { day in
                        VStack(alignment: .leading) {
                            Text(day.date, style: .date)
                                .font(.headline)
                            if let validBlocks = blocksByDay[day.date] {
                                ForEach(validBlocks, id: \.id) { block in
                                    blockView(day: day, block: block)
                                }
                            }
                        }
                        Divider()
                    }
                }
                .padding()
            }
        }
        .onAppear {
            print("DEBUG: Generating schedule on appear")
            generateSchedule()
        }
        .onChange(of: assignmentsStore.assignments) { _ in
            print("DEBUG: Assignments changed, regenerating schedule")
            generateSchedule()
        }
    }

    @ViewBuilder
    private func blockView(day: PlannedDay, block: DailyAssignmentBlock) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                let assignmentTitle = assignmentsStore.assignments.first(where: { $0.id.uuidString == block.assignmentId })?.title ?? block.assignmentId
                Text(assignmentTitle)
                    .fontWeight(.semibold)

                if let urgency = day.urgencies[block.assignmentId] {
                    Text(String(format: "Urgency: %.2f", urgency))
                        .font(.caption)
                        .foregroundColor(.purple)
                }

                let durationMinutes = Int((block.endTime.timeIntervalSince(block.startTime) / 60).rounded())
                if block.preferredHours > 0 {
                    Text("Within Preferred Hours: \(durationMinutes) min")
                } else if block.overflowHours > 0 {
                    Text("Outside of Preferred Hours: \(durationMinutes) min")
                }

                Text("\(block.startTime.formatted(date: .omitted, time: .shortened)) - \(block.endTime.formatted(date: .omitted, time: .shortened))")

                if let reason = block.overflowReason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            Spacer()
            if block.overflowHours > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
        }
        .padding(8)
        .background(
            block.overflowHours > 0 ? Color.red.opacity(0.3) :
            block.preferredHours > 0 ? Color.green.opacity(0.3) :
            Color.clear
        )
        .cornerRadius(6)
    }

    private func generateSchedule() {
        print("DEBUG: Starting schedule generation")
        print("DEBUG: Preferred Start Time (raw):", settings.preferredStartTime ?? "nil")
        print("DEBUG: Preferred End Time (raw):", settings.preferredEndTime ?? "nil")

        // Only use incomplete assignments for scheduling
        let inputs = assignmentsStore.incompleteAssignments.compactMap { a -> AssignmentInput? in
            guard a.hasRealDueDate else {
                print("DEBUG: Skipping assignment \(a.title) — no real due date")
                return nil
            }
            let remainingMinutes = max(0, a.aiEstimatedTime - a.minutesCompleted)
            guard remainingMinutes > 0 else {
                print("DEBUG: Skipping assignment \(a.title) — no remaining time")
                return nil
            }
            return AssignmentInput(
                id: a.id.uuidString,
                dueDate: a.dueDate,
                totalHours: Double(remainingMinutes) / 60.0,
                hoursCompleted: 0,
                importance: Double(a.aiEstimatedImportance)
            )
        }

        print("DEBUG: Filtered assignment inputs (\(inputs.count)):")
        for input in inputs {
            print(" - \(input.id), due: \(input.dueDate), totalHours: \(input.totalHours), importance: \(input.importance)")
        }

        guard !inputs.isEmpty else {
            print("DEBUG: No assignments available for scheduling.")
            plannedDays = []
            return
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let latestDue = inputs.map { $0.dueDate }.max() ?? today
        let daysBetween = max(1, calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: latestDue)).day ?? 0) + 1

        print("DEBUG: Scheduling over \(daysBetween) days")

        let start = settings.preferredStartTime ?? Calendar.current.date(from: DateComponents(hour: 15, minute: 0))!
        let end = settings.preferredEndTime ?? Calendar.current.date(from: DateComponents(hour: 18, minute: 0))!

        plannedDays = ScheduleGenerator.generateSchedule(
            assignments: inputs,
            preferredStartTime: Calendar.current.dateComponents([.hour, .minute], from: start),
            preferredEndTime: Calendar.current.dateComponents([.hour, .minute], from: end),
            planningHorizonDays: daysBetween,
            loadBias: settings.loadBias,
            currentTime: Date()
        )

        print("DEBUG: Schedule generation complete. Planned days: \(plannedDays.count)")
        for day in plannedDays {
            print(" - \(day.date): \(day.assignmentBlocks.count) blocks")
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
}
#endif
