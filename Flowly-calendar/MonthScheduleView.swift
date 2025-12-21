import SwiftUI
import Foundation

struct MonthScheduleView: View {
    @EnvironmentObject var assignmentsStore: AssignmentsStore
    @EnvironmentObject var scheduleManager: ScheduleManager
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false

    @State private var currentDate = Date()
    @State private var selectedDate: Date?

    private var calendar = Calendar.current
    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(spacing: 0) {
            // Month/Year Header with Navigation
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.blue)
                }

                Spacer()

                Text(monthYearString)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.blue)
                }
            }
            .padding()

            // Weekday headers
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)

            // Calendar grid
            let days = daysInMonth
            let firstWeekday = calendar.component(.weekday, from: days.first ?? Date()) - 1 // 0 = Sunday

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                // Empty cells for days before month starts
                ForEach(0..<firstWeekday, id: \.self) { _ in
                    Color.clear
                        .frame(width: 44, height: 50)
                }

                // Days of the month
                ForEach(days, id: \.self) { date in
                    ScheduleDayCell(
                        date: date,
                        hasScheduledTask: hasScheduledTask(on: date),
                        isSelected: selectedDate != nil && calendar.isDate(date, inSameDayAs: selectedDate!),
                        isToday: calendar.isDateInToday(date)
                    )
                    .onTapGesture {
                        selectedDate = date
                    }
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .background(Color(.systemBackground))
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .sheet(item: Binding(
            get: { selectedDate.map { DayScheduleItem(date: $0) } },
            set: { selectedDate = $0?.date }
        )) { item in
            DaySchedulePopup(date: item.date)
                .environmentObject(assignmentsStore)
                .environmentObject(scheduleManager)
                .presentationDetents([.medium, .large])
        }
    }

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentDate)
    }

    private var daysInMonth: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentDate),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: currentDate)) else {
            return []
        }

        var days: [Date] = []
        var currentDay = firstDay
        while currentDay < monthInterval.end {
            days.append(currentDay)
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) {
                currentDay = nextDay
            } else {
                break
            }
        }

        return days
    }

    private func hasScheduledTask(on date: Date) -> Bool {
        return scheduleManager.plannedDays
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .contains { day in
                day.assignmentBlocks.contains { block in
                    block.endTime > block.startTime &&
                    block.endTime.timeIntervalSince(block.startTime) >= 60 &&
                    (block.preferredHours > 0 || block.overflowHours > 0)
                }
            }
    }

    private func previousMonth() {
        if let date = calendar.date(byAdding: .month, value: -1, to: currentDate) {
            currentDate = date
            selectedDate = nil
        }
    }

    private func nextMonth() {
        if let date = calendar.date(byAdding: .month, value: 1, to: currentDate) {
            currentDate = date
            selectedDate = nil
        }
    }
}

struct ScheduleDayCell: View {
    let date: Date
    let hasScheduledTask: Bool
    let isSelected: Bool
    let isToday: Bool

    private var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("\(dayNumber)")
                .font(.system(size: 16, weight: isToday ? .bold : .regular))
                .foregroundColor(isToday ? .blue : .primary)

            if hasScheduledTask {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
            } else {
                Spacer()
                    .frame(height: 6)
            }
        }
        .frame(width: 44, height: 50)
        .background(
            isSelected ? Color.accentColor.opacity(0.2) : Color.clear
        )
        .cornerRadius(8)
    }
}

struct DayScheduleItem: Identifiable {
    let id = UUID()
    let date: Date
}

struct DaySchedulePopup: View {
    @EnvironmentObject var assignmentsStore: AssignmentsStore
    @EnvironmentObject var scheduleManager: ScheduleManager
    @Environment(\.dismiss) var dismiss

    let date: Date
    private let calendar = Calendar.current

    private var blocksForDay: [DailyAssignmentBlock] {
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

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if blocksForDay.isEmpty {
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
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(blocksForDay, id: \.id) { block in
                            blockView(block: block)
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle(dateString)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
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
            block.overflowHours > 0 ? Color.red.opacity(0.15) :
            block.preferredHours > 0 ? Color.green.opacity(0.15) :
            Color(.secondarySystemBackground)
        )
        .cornerRadius(8)
    }
}
