import Foundation
import SwiftUI
import Combine

/// Holds assignments and settings, regenerates the schedule automatically when settings/assignments change.
class ScheduleManager: ObservableObject {
    @Published var plannedDays: [PlannedDay] = []
    
    private var assignments: [AssignmentInput]
    private var settings: ScheduleSettings
    private var cancellables = Set<AnyCancellable>()

    init(assignments: [AssignmentInput], settings: ScheduleSettings) {
        self.assignments = assignments
        self.settings = settings
        // Observe key settings
        observeSettings()
        regenerateSchedule()
    }

    func updateAssignments(_ newAssignments: [AssignmentInput]) {
        assignments = newAssignments
        regenerateSchedule()
    }

    private func observeSettings() {
        // Observe all relevant settings
        settings.objectWillChange.sink { [weak self] _ in
            self?.regenerateSchedule()
        }.store(in: &cancellables)
    }

    private func regenerateSchedule() {
        let calendar = Calendar.current
        let startComps = calendar.dateComponents([.hour, .minute], from: settings.preferredStartTime)
        let endComps = calendar.dateComponents([.hour, .minute], from: settings.preferredEndTime)
        // Save updated preferred start and end times to internal settings
        settings.preferredStartTime = calendar.date(from: startComps) ?? settings.preferredStartTime
        settings.preferredEndTime = calendar.date(from: endComps) ?? settings.preferredEndTime
        // Use .frontLoadingFactor as frontLoadFactorMax
        let schedule = ScheduleGenerator.generateSchedule(
            assignments: assignments,
            preferredStartTime: startComps,
            preferredEndTime: endComps,
            planningHorizonDays: nil,
            loadBias: settings.loadBias,
            currentTime: Date()
        )
        // Debug print front-load factor for each assignment
        
        DispatchQueue.main.async {
            self.plannedDays = schedule
        }
    }
}
