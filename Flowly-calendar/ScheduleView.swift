import SwiftUI
import Foundation

struct ScheduleView: View {
    @EnvironmentObject var assignmentsStore: AssignmentsStore
    @EnvironmentObject var settings: ScheduleSettings
    @EnvironmentObject var scheduleManager: ScheduleManager

    private var daysWithValidBlocks: [PlannedDay] {
        let allDays = scheduleManager.plannedDays
        print("[DEBUG] ScheduleView: Total planned days: \(allDays.count)")
        for (idx, day) in allDays.enumerated() {
            print("[DEBUG] ScheduleView: Day \(idx): date=\(day.date), blocks=\(day.assignmentBlocks.count)")
            for (blockIdx, block) in day.assignmentBlocks.enumerated() {
                print("[DEBUG] ScheduleView:   Block \(blockIdx): assignmentId=\(block.assignmentId), start=\(block.startTime), end=\(block.endTime), preferred=\(block.preferredHours), overflow=\(block.overflowHours)")
            }
        }

        let filtered = allDays.filter { day in
            day.assignmentBlocks.contains {
                ($0.preferredHours > 0 || $0.overflowHours > 0 || ($0.preferredHours == 0 && $0.overflowHours == 0)) &&
                $0.endTime > $0.startTime &&
                $0.endTime.timeIntervalSince($0.startTime) >= 60
            }
        }
        print("[DEBUG] ScheduleView: Filtered days with valid blocks: \(filtered.count)")
        return filtered
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
        NavigationView {
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
            .navigationTitle("Schedule")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        scheduleManager.forceRegenerate()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
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
}
#endif
