import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var assignmentsStore: AssignmentsStore
    
    @State private var startDate = Date()
    @State private var daysPeriod = 30
    @State private var showSettings = false
    
    private var endDate: Date {
        Calendar.current.date(byAdding: .day, value: daysPeriod, to: startDate) ?? startDate
    }
    
    private var scheduleItems: [ScheduleItem] {
        ScheduleGenerator.generateSchedule(
            assignments: assignmentsStore.assignments,
            startDate: startDate,
            days: daysPeriod
        )
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Period selector
                HStack {
                    Button(action: { showSettings.toggle() }) {
                        HStack {
                            Image(systemName: "calendar")
                            Text("\(formatDate(startDate)) - \(formatDate(endDate))")
                                .font(.subheadline)
                        }
                    }
                    .foregroundColor(.blue)
                    
                    Spacer()
                    
                    Button(action: previousPeriod) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.blue)
                    }
                    
                    Button(action: nextPeriod) {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.blue)
                    }
                }
                .padding()
                
                // Schedule list
                if scheduleItems.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No assignments to schedule")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Make sure you have incomplete assignments with due dates and durations set.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(groupedScheduleItems.keys.sorted(), id: \.self) { date in
                            Section {
                                ForEach(groupedScheduleItems[date] ?? []) { item in
                                    ScheduleItemRow(item: item)
                                }
                            } header: {
                                Text(formatSectionDate(date))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Schedule")
            .sheet(isPresented: $showSettings) {
                ScheduleSettingsView(
                    startDate: $startDate,
                    daysPeriod: $daysPeriod
                )
            }
        }
    }
    
    private var groupedScheduleItems: [Date: [ScheduleItem]] {
        let calendar = Calendar.current
        var grouped: [Date: [ScheduleItem]] = [:]
        
        for item in scheduleItems {
            let day = calendar.startOfDay(for: item.startTime)
            if grouped[day] == nil {
                grouped[day] = []
            }
            grouped[day]?.append(item)
        }
        
        return grouped
    }
    
    private func previousPeriod() {
        if let newDate = Calendar.current.date(byAdding: .day, value: -daysPeriod, to: startDate) {
            startDate = newDate
        }
    }
    
    private func nextPeriod() {
        if let newDate = Calendar.current.date(byAdding: .day, value: daysPeriod, to: startDate) {
            startDate = newDate
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func formatSectionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }
}

struct ScheduleItemRow: View {
    let item: ScheduleItem
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Time
            VStack(alignment: .leading, spacing: 2) {
                Text(formatTime(item.startTime))
                    .font(.headline)
                Text(formatTime(item.endTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 70, alignment: .leading)
            
            Divider()
            
            // Assignment info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .fontWeight(.medium)
                
                HStack {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("\(item.durationMinutes) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ScheduleSettingsView: View {
    @Binding var startDate: Date
    @Binding var daysPeriod: Int
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    
                    Stepper("Days: \(daysPeriod)", value: $daysPeriod, in: 7...90, step: 7)
                } header: {
                    Text("Schedule Period")
                } footer: {
                    Text("Adjust the start date and number of days to schedule assignments.")
                }
            }
            .navigationTitle("Schedule Settings")
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
