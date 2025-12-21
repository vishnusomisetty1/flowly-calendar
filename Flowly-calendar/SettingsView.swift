import SwiftUI

// Ensure Schedule class exists
class Schedule: ObservableObject {
    @Published var days: [PlannedDay]
    init(days: [PlannedDay]) {
        self.days = days
    }
}

struct SettingsScheduleView: View {
    @ObservedObject var schedule: Schedule

    var body: some View {
        List {
            ForEach(schedule.days, id: \.date) { day in
                Section(header: Text(day.date, style: .date)) {
                    ForEach(day.assignmentBlocks, id: \.id) { block in
                        let durationMinutes = Int((block.endTime.timeIntervalSince(block.startTime) / 60).rounded())
                        let backgroundColor = block.overflowHours > 0 ? Color.orange.opacity(0.3) : Color.green.opacity(0.3)
                        
                        VStack(alignment: .leading) {
                            Text(block.assignmentId)
                            Text("Duration: \(durationMinutes) min")
                        }
                        .padding(5)
                        .background(backgroundColor)
                        .cornerRadius(5)
                    }
                }
            }
        }
    }
}
