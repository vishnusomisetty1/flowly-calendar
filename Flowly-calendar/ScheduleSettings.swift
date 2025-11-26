import SwiftUI

class ScheduleSettings: ObservableObject {
    @AppStorage("preferredStartTime") private var preferredStartTimeInterval: Double = {
        let components = DateComponents(hour: 15, minute: 0)
        return Calendar.current.date(from: components)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
    }()
    @AppStorage("preferredEndTime") private var preferredEndTimeInterval: Double = {
        let components = DateComponents(hour: 18, minute: 0)
        return Calendar.current.date(from: components)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
    }()
    @AppStorage("maxOverflowHoursPerDay") var maxOverflowHoursPerDay: Double = 2
    @AppStorage("frontLoadingFactor") var frontLoadingFactor: Double = 0.5
    @AppStorage("urgencyWeighting") var urgencyWeighting: Double = 0.5
    @AppStorage("showOverflowHours") var showOverflowHours: Bool = true

    // Use optional Dates and initialize them after self is fully initialized
    @Published var preferredStartTime: Date?
    @Published var preferredEndTime: Date?

    init() {
        // Set to nil initially to avoid using self before fully initialized
        preferredStartTime = nil
        preferredEndTime = nil
        preferredStartTime = Date(timeIntervalSince1970: preferredStartTimeInterval)
        preferredEndTime = Date(timeIntervalSince1970: preferredEndTimeInterval)
    }
}

struct DetailedScheduleSettingsView: View {
    @ObservedObject var settings: ScheduleSettings
    @Environment(\.dismiss) private var dismiss

    // Local copies for editing, to avoid immediate changes on bindings
    @State private var tempPreferredStartTime: Date
    @State private var tempPreferredEndTime: Date
    @State private var tempMaxOverflowHoursPerDay: Double
    @State private var tempFrontLoadingFactor: Double
    @State private var tempUrgencyWeighting: Double
    @State private var tempShowOverflowHours: Bool

    init(settings: ScheduleSettings) {
        self.settings = settings
        // Provide default fallback values for optionals to avoid unexpected nils
        _tempPreferredStartTime = State(initialValue: settings.preferredStartTime ?? Date())
        _tempPreferredEndTime = State(initialValue: settings.preferredEndTime ?? Date())
        _tempMaxOverflowHoursPerDay = State(initialValue: settings.maxOverflowHoursPerDay)
        _tempFrontLoadingFactor = State(initialValue: settings.frontLoadingFactor)
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
                        Text("Front-loading Factor: \(tempFrontLoadingFactor, specifier: "%.2f")")
                        Slider(value: $tempFrontLoadingFactor, in: 0...2)
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
        settings.preferredStartTime = tempPreferredStartTime
        settings.preferredEndTime = tempPreferredEndTime
        settings.maxOverflowHoursPerDay = tempMaxOverflowHoursPerDay
        settings.frontLoadingFactor = tempFrontLoadingFactor
        settings.urgencyWeighting = tempUrgencyWeighting
        settings.showOverflowHours = tempShowOverflowHours
    }
}

