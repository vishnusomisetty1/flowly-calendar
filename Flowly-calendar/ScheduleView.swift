import SwiftUI
import Foundation

struct ScheduleView: View {
    @EnvironmentObject var assignmentsStore: AssignmentsStore
    @State var plannedDays: [PlannedDay] = []

    // User preferences for preferred window
    @State var preferredStartTime = DateComponents(hour: 15, minute: 0)
    @State var preferredEndTime = DateComponents(hour: 18, minute: 0)
    @State var maxOverflowHoursPerDay = 2.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(
                    plannedDays.filter { day in
                        return day.assignmentBlocks.contains { block in
                            (block.preferredHours > 0 || block.overflowHours > 0) &&
                            block.endTime > block.startTime &&
                            block.endTime.timeIntervalSince(block.startTime) >= 60
                        }
                    },
                    id: \.date
                ) { day in
                    VStack(alignment: .leading) {
                        Text(day.date, style: .date)
                            .font(.headline)
                        ForEach(day.assignmentBlocks.filter { block in
                            (block.preferredHours > 0 || block.overflowHours > 0) &&
                            block.endTime > block.startTime &&
                            block.endTime.timeIntervalSince(block.startTime) >= 60
                        }, id: \.id) { block in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(block.assignmentId)
                                        .fontWeight(.semibold)
                                    if let label = ScheduleView.atRiskOrDeferrableLabel(
                                        plannedDays: plannedDays,
                                        day: day,
                                        block: block
                                    ) {
                                        label
                                            .padding(4)
                                            .background(label.backgroundColor)
                                            .foregroundColor(.white)
                                            .cornerRadius(4)
                                            .font(.caption)
                                            .padding(.top, 2)
                                    }
                                    if let urgency = day.urgencies[block.assignmentId] {
                                        Text(String(format: "Urgency: %.2f", urgency))
                                            .font(.caption)
                                            .foregroundColor(.purple)
                                    }
                                    let durationMinutes = Int((block.endTime.timeIntervalSince(block.startTime) / 60).rounded())
                                    if block.preferredHours > 0 {
                                        Text("Preferred: \(durationMinutes) min")
                                    } else if block.overflowHours > 0 {
                                        Text("Overflow: \(durationMinutes) min")
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
                            .background(Color.green.opacity(block.preferredHours > 0 ? 0.3 : 0))
                            .cornerRadius(6)
                        }
                    }
                    Divider()
                }
            }
            .padding()
        }
        .onAppear {
            generateSchedule()
        }
        .onChange(of: assignmentsStore.assignments) { _ in
            generateSchedule()
        }
    }

    func generateSchedule() {
        // Only include incomplete assignments with real due dates and remaining work
        let inputs = assignmentsStore.assignments.filter { !$0.isCompleted && $0.hasRealDueDate }.compactMap { a -> AssignmentInput? in
            let remainingMinutes = max(0, a.aiEstimatedTime - a.minutesCompleted)
            guard remainingMinutes > 0 else { return nil } // skip assignments with no remaining work
            return AssignmentInput(
                id: a.title,
                dueDate: a.dueDate,
                totalHours: Double(remainingMinutes) / 60.0, // convert remaining minutes to hours
                hoursCompleted: 0, // start fresh with remaining
                importance: Double(a.aiEstimatedImportance)
            )
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let latestDue = inputs.map { $0.dueDate }.max()
        let planningHorizonDays: Int
        if let latest = latestDue {
            let days = max(1, calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: latest)).day ?? 0) + 1
            planningHorizonDays = days
        } else {
            planningHorizonDays = 1
        }
        plannedDays = ScheduleGenerator.generateSchedule(
            assignments: inputs,
            preferredStartTime: preferredStartTime,
            preferredEndTime: preferredEndTime,
            maxOverflowHoursPerDay: maxOverflowHoursPerDay,
            planningHorizonDays: planningHorizonDays,
            currentTime: Date()  // pass current time for today
        )
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

    static func atRiskOrDeferrableLabel(plannedDays: [PlannedDay], day: PlannedDay, block: DailyAssignmentBlock) -> RiskLabel? {
        // Show label only if block has preferred or overflow hours
        guard (block.preferredHours > 0 || block.overflowHours > 0) else { return nil }

        let assignmentId: String = block.assignmentId

        // Sum remaining work
        var remainingWork: Double = 0.0
        for pd in plannedDays where pd.date >= day.date {
            for b in pd.assignmentBlocks where b.assignmentId == assignmentId {
                remainingWork += b.preferredHours + b.overflowHours
            }
        }

        // Sum future preferred capacity
        var futurePreferredCapacity: Double = 0.0
        for pd in plannedDays where pd.date >= day.date && pd.date <= day.date { // Use day.date for dueDate placeholder
            for b in pd.assignmentBlocks where b.assignmentId == assignmentId {
                futurePreferredCapacity += b.preferredHours
            }
        }

        if remainingWork > futurePreferredCapacity {
            return RiskLabel(text: "At-Risk", backgroundColor: .orange)
        } else {
            return RiskLabel(text: "Deferrable", backgroundColor: .blue)
        }
    }
}

#if DEBUG
#Preview {
    ScheduleView()
        .environmentObject(AssignmentsStore())
}
#endif
