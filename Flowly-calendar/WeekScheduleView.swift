import SwiftUI
import Foundation

struct WeekScheduleView: View {
    @EnvironmentObject var assignmentsStore: AssignmentsStore
    @EnvironmentObject var scheduleManager: ScheduleManager

    @State private var selectedWeekStart = Calendar.current.startOfDay(for: Date())

    private var calendar = Calendar.current

    private var weekDays: [Date] {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: selectedWeekStart) else {
            return []
        }

        var days: [Date] = []
        var currentDay = weekInterval.start
        while currentDay < weekInterval.end {
            days.append(currentDay)
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) {
                currentDay = nextDay
            } else {
                break
            }
        }
        return days
    }

    private func blocksForDay(_ date: Date) -> [DailyAssignmentBlock] {
        return scheduleManager.plannedDays
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
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
            // Week navigation
            HStack {
                Button {
                    if let prevWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedWeekStart) {
                        selectedWeekStart = calendar.startOfDay(for: prevWeek)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.blue)
                }

                Spacer()

                Text(weekRangeString)
                    .font(.headline)

                Spacer()

                Button {
                    if let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedWeekStart) {
                        selectedWeekStart = calendar.startOfDay(for: nextWeek)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.blue)
                }
            }
            .padding()

            // Week schedule
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(weekDays, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(day, style: .date)
                                .font(.headline)
                                .foregroundColor(calendar.isDateInToday(day) ? .blue : .primary)

                            let blocks = blocksForDay(day)
                            if blocks.isEmpty {
                                Text("No scheduled tasks")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.leading)
                            } else {
                                ForEach(blocks, id: \.id) { block in
                                    blockView(block: block)
                                }
                            }
                        }
                        .padding(.horizontal)
                        Divider()
                    }
                }
                .padding(.vertical)
            }
        }
    }

    private var weekRangeString: String {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: selectedWeekStart),
              let endDate = calendar.date(byAdding: .day, value: 6, to: weekInterval.start) else {
            return ""
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let startStr = formatter.string(from: weekInterval.start)
        let endStr = formatter.string(from: endDate)

        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        let year = yearFormatter.string(from: weekInterval.start)

        return "\(startStr) - \(endStr), \(year)"
    }

    @ViewBuilder
    private func blockView(block: DailyAssignmentBlock) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                let assignmentTitle = assignmentsStore.assignments.first(where: { $0.id.uuidString == block.assignmentId })?.title ?? block.assignmentId
                Text(assignmentTitle)
                    .fontWeight(.semibold)
                    .font(.subheadline)

                let durationMinutes = Int((block.endTime.timeIntervalSince(block.startTime) / 60).rounded())
                Text("\(block.startTime.formatted(date: .omitted, time: .shortened)) - \(block.endTime.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if block.overflowHours > 0 {
                    Text("Outside preferred hours")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            Spacer()
            if block.overflowHours > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
        }
        .padding(8)
        .background(
            block.overflowHours > 0 ? Color.red.opacity(0.1) :
            block.preferredHours > 0 ? Color.green.opacity(0.1) :
            Color.clear
        )
        .cornerRadius(6)
    }
}
