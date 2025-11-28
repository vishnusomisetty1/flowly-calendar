import SwiftUI

class ScheduleSettings: ObservableObject {
    @AppStorage("preferredStartHour") var preferredStartHour: Int = 15
    @AppStorage("preferredStartMinute") var preferredStartMinute: Int = 0

    @AppStorage("preferredEndHour") var preferredEndHour: Int = 18
    @AppStorage("preferredEndMinute") var preferredEndMinute: Int = 0

    @AppStorage("maxOverflowHoursPerDay") var maxOverflowHoursPerDay: Double = 2
    @AppStorage("urgencyWeighting") var urgencyWeighting: Double = 0.5
    @AppStorage("showOverflowHours") var showOverflowHours: Bool = true

    // Computed Date values for today
    var preferredStartTime: Date {
        get {
            Calendar.current.date(bySettingHour: preferredStartHour, minute: preferredStartMinute, second: 0, of: Date())!
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            preferredStartHour = components.hour ?? 15
            preferredStartMinute = components.minute ?? 0
        }
    }

    var preferredEndTime: Date {
        get {
            Calendar.current.date(bySettingHour: preferredEndHour, minute: preferredEndMinute, second: 0, of: Date())!
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            preferredEndHour = components.hour ?? 18
            preferredEndMinute = components.minute ?? 0
        }
    }
}

struct DetailedScheduleSettingsView: View {
    @ObservedObject var settings: ScheduleSettings
    @Environment(\.dismiss) private var dismiss

    @State private var tempPreferredStartTime: Date
    @State private var tempPreferredEndTime: Date
    @State private var tempMaxOverflowHoursPerDay: Double
    @State private var tempUrgencyWeighting: Double
    @State private var tempShowOverflowHours: Bool

    init(settings: ScheduleSettings) {
        self.settings = settings
        _tempPreferredStartTime = State(initialValue: settings.preferredStartTime)
        _tempPreferredEndTime = State(initialValue: settings.preferredEndTime)
        _tempMaxOverflowHoursPerDay = State(initialValue: settings.maxOverflowHoursPerDay)
        _tempUrgencyWeighting = State(initialValue: settings.urgencyWeighting)
        _tempShowOverflowHours = State(initialValue: settings.showOverflowHours)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Preferred Study Hours")) {
                    DatePicker("Start Time", selection: $tempPreferredStartTime, displayedComponents: .hourAndMinute)
                    DatePicker("End Time", selection: $tempPreferredEndTime, displayedComponents: .hourAndMinute)
                }
                Section(header: Text("Session Parameters")) {
                    Stepper(value: $tempMaxOverflowHoursPerDay, in: 0...8, step: 0.5) {
                        Text("Max Overflow Hours: \(tempMaxOverflowHoursPerDay, specifier: "%.1f") h")
                    }
                    VStack(alignment: .leading) {
                        Text("Urgency Weighting: \(tempUrgencyWeighting, specifier: "%.2f")")
                        Slider(value: $tempUrgencyWeighting, in: 0...1)
                    }
                }
                Section {
                    Toggle("Show Overflow Hours in Schedule", isOn: $tempShowOverflowHours)
                }
            }
            .navigationTitle("Schedule Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Apply") {
                        applyChanges()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func applyChanges() {
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: tempPreferredStartTime)
        settings.preferredStartHour = startComponents.hour ?? 15
        settings.preferredStartMinute = startComponents.minute ?? 0

        let endComponents = calendar.dateComponents([.hour, .minute], from: tempPreferredEndTime)
        settings.preferredEndHour = endComponents.hour ?? 18
        settings.preferredEndMinute = endComponents.minute ?? 0

        settings.maxOverflowHoursPerDay = tempMaxOverflowHoursPerDay
        settings.urgencyWeighting = tempUrgencyWeighting
        settings.showOverflowHours = tempShowOverflowHours
    }
}
