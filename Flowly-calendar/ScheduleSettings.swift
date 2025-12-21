import SwiftUI

class ScheduleSettings: ObservableObject {
    @AppStorage("preferredStartInterval") var preferredStartInterval: TimeInterval = 15 * 3600 // 15:00
    @AppStorage("preferredEndInterval") var preferredEndInterval: TimeInterval = 18 * 3600   // 18:00

    @AppStorage("urgencyWeighting") var urgencyWeighting: Double = 0.5
    @AppStorage("showOverflowHours") var showOverflowHours: Bool = true
    @AppStorage("loadBias") var loadBias: Double = 1.0

    // Computed Date values for today
    var preferredStartTime: Date {
        get { Calendar.current.startOfDay(for: Date()).addingTimeInterval(preferredStartInterval) }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            preferredStartInterval = TimeInterval((components.hour ?? 15) * 3600 + (components.minute ?? 0) * 60)
        }
    }

    var preferredEndTime: Date {
        get { Calendar.current.startOfDay(for: Date()).addingTimeInterval(preferredEndInterval) }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            preferredEndInterval = TimeInterval((components.hour ?? 18) * 3600 + (components.minute ?? 0) * 60)
        }
    }
}

struct DetailedScheduleSettingsView: View {
    @ObservedObject var settings: ScheduleSettings
    @Environment(\.dismiss) private var dismiss

    @State private var tempPreferredStartTime: Date
    @State private var tempPreferredEndTime: Date
    @State private var tempUrgencyWeighting: Double
    @State private var tempShowOverflowHours: Bool
    @State private var tempLoadBias: Double

    init(settings: ScheduleSettings) {
        self.settings = settings
        _tempPreferredStartTime = State(initialValue: settings.preferredStartTime)
        _tempPreferredEndTime = State(initialValue: settings.preferredEndTime)
        _tempUrgencyWeighting = State(initialValue: settings.urgencyWeighting)
        _tempShowOverflowHours = State(initialValue: settings.showOverflowHours)
        _tempLoadBias = State(initialValue: settings.loadBias)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Preferred Study Hours")) {
                    DatePicker("Start Time", selection: $tempPreferredStartTime, displayedComponents: .hourAndMinute)
                    DatePicker("End Time", selection: $tempPreferredEndTime, displayedComponents: .hourAndMinute)
                }
                Section(header: Text("Session Parameters")) {
                    VStack(alignment: .leading) {
                        Text("Urgency Weighting: \(tempUrgencyWeighting, specifier: "%.2f")")
                        Slider(value: $tempUrgencyWeighting, in: 0...1)
                    }
                }
                Section(header: Text("Load Bias")) {
                    VStack(alignment: .leading) {
                        HStack {
                            Slider(value: $tempLoadBias, in: 0.5...1.5, step: 0.01)
                            Text("\(tempLoadBias, specifier: "%.2f")")
                                .frame(width: 50, alignment: .trailing)
                        }
                        Text("1.0 = balanced, <1.0 = front-load, >1.0 = back-load")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
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
        settings.preferredStartInterval = TimeInterval((startComponents.hour ?? 15) * 3600 + (startComponents.minute ?? 0) * 60)

        let endComponents = calendar.dateComponents([.hour, .minute], from: tempPreferredEndTime)
        settings.preferredEndInterval = TimeInterval((endComponents.hour ?? 18) * 3600 + (endComponents.minute ?? 0) * 60)

        settings.urgencyWeighting = tempUrgencyWeighting
        settings.loadBias = tempLoadBias
        settings.showOverflowHours = tempShowOverflowHours
    }
}
