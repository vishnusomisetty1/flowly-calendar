import SwiftUI
import Foundation

struct DayScheduleView: View {
    @EnvironmentObject var assignmentsStore: AssignmentsStore
    @EnvironmentObject var scheduleManager: ScheduleManager

    @State private var selectedDate = Date()

    private var calendar = Calendar.current

    private var blocksForSelectedDay: [DailyAssignmentBlock] {
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        return scheduleManager.plannedDays
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
            .flatMap { $0.assignmentBlocks }
            .filter { block in
                block.endTime > block.startTime &&
                block.endTime.timeIntervalSince(block.startTime) >= 60 &&
                (block.preferredHours > 0 || block.overflowHours > 0)
            }
            .sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Date picker
            DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .padding()

            // Schedule blocks
            if blocksForSelectedDay.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("No scheduled tasks for this day")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(blocksForSelectedDay, id: \.id) { block in
                            blockView(block: block)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    @ViewBuilder
    private func blockView(block: DailyAssignmentBlock) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                let assignmentTitle = assignmentsStore.assignments.first(where: { $0.id.uuidString == block.assignmentId })?.title ?? block.assignmentId
                Text(assignmentTitle)
                    .fontWeight(.semibold)

                let durationMinutes = Int((block.endTime.timeIntervalSince(block.startTime) / 60).rounded())
                if block.preferredHours > 0 {
                    Text("Within Preferred Hours: \(durationMinutes) min")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if block.overflowHours > 0 {
                    Text("Outside of Preferred Hours: \(durationMinutes) min")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                Text("\(block.startTime.formatted(date: .omitted, time: .shortened)) - \(block.endTime.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

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
        .padding(12)
        .background(
            block.overflowHours > 0 ? Color.red.opacity(0.1) :
            block.preferredHours > 0 ? Color.green.opacity(0.1) :
            Color.clear
        )
        .cornerRadius(8)
    }
}
