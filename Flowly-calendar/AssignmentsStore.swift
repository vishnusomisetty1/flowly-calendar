import Foundation

@MainActor
final class AssignmentsStore: ObservableObject {
    @Published var assignments: [Assignment] = [] {
        didSet { save() }
    }

    // Filter date for missing assignments (defaults to 1 week before current date)
    var missingAssignmentsFilterDate: Date {
        Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
    }
    
    // Organized assignment groups based on current time (not just start of day)
    func missingAssignments(filteredAfter date: Date? = nil) -> [Assignment] {
        let calendar = Calendar.current
        let now = Date()
        let startOfNow = calendar.startOfDay(for: now)
        let filterDate = date ?? missingAssignmentsFilterDate
        let startOfFilterDate = calendar.startOfDay(for: filterDate)
        
        return assignments.filter { assignment in
            guard !assignment.isCompleted && assignment.hasRealDueDate else { return false }
            // Compare using start of day for both dates to avoid timezone issues
            let assignmentStartOfDay = calendar.startOfDay(for: assignment.dueDate)
            // Must be before now AND after the filter date
            return assignmentStartOfDay < startOfNow && assignmentStartOfDay >= startOfFilterDate
        }
        .sorted { 
            calendar.startOfDay(for: $0.dueDate) < calendar.startOfDay(for: $1.dueDate)
        }
    }
    
    // Convenience property for backwards compatibility
    var missingAssignments: [Assignment] {
        missingAssignments(filteredAfter: nil)
    }
    
    func updateDuration(for assignmentId: UUID, minutes: Int?) {
        if let index = assignments.firstIndex(where: { $0.id == assignmentId }) {
            assignments[index].durationMinutes = minutes
        }
    }
    
    func updatePoints(for assignmentId: UUID, points: Int?) {
        if let index = assignments.firstIndex(where: { $0.id == assignmentId }) {
            assignments[index].points = points
        }
    }
    
    var incompleteAssignments: [Assignment] {
        let calendar = Calendar.current
        let now = Date()
        let startOfNow = calendar.startOfDay(for: now)
        
        return assignments.filter { assignment in
            guard !assignment.isCompleted && assignment.hasRealDueDate else { return false }
            // Compare using start of day for both dates to avoid timezone issues
            let assignmentStartOfDay = calendar.startOfDay(for: assignment.dueDate)
            return assignmentStartOfDay >= startOfNow
        }
        .sorted { 
            calendar.startOfDay(for: $0.dueDate) < calendar.startOfDay(for: $1.dueDate)
        }
    }
    
    var otherAssignments: [Assignment] {
        // Assignments without real due dates (not completed)
        return assignments.filter { 
            !$0.isCompleted && !$0.hasRealDueDate 
        }
        .sorted { $0.title < $1.title }  // Sort by title since no due date
    }
    
    // Filter date for completed assignments (defaults to 1 week before current date)
    var completedAssignmentsFilterDate: Date {
        Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
    }
    
    func completedAssignments(filteredAfter date: Date? = nil) -> [Assignment] {
        let calendar = Calendar.current
        let filterDate = date ?? completedAssignmentsFilterDate
        let startOfFilterDate = calendar.startOfDay(for: filterDate)
        
        return assignments.filter { assignment in
            guard assignment.isCompleted else { return false }
            // Only show completed assignments with due dates on or after the filter date
            if assignment.hasRealDueDate {
                let assignmentStartOfDay = calendar.startOfDay(for: assignment.dueDate)
                return assignmentStartOfDay >= startOfFilterDate
            } else {
                // For assignments without due dates, show all completed ones (or could filter by completion date if tracked)
                return true
            }
        }
        .sorted { $0.dueDate < $1.dueDate }
    }
    
    // Convenience property for backwards compatibility
    var completedAssignments: [Assignment] {
        completedAssignments(filteredAfter: nil)
    }
    
    // Legacy properties for backwards compatibility
    var assignmentsBeforeToday: [Assignment] {
        let now = Date()
        return assignments.filter { !$0.isCompleted && $0.hasRealDueDate && $0.dueDate < now }
    }
    
    var assignmentsAfterToday: [Assignment] {
        let now = Date()
        return assignments.filter { !$0.isCompleted && $0.hasRealDueDate && $0.dueDate >= now }
    }
    
    func toggleCompletion(for assignmentId: UUID) {
        if let index = assignments.firstIndex(where: { $0.id == assignmentId }) {
            assignments[index].isCompleted.toggle()
        }
    }

    private var keyPrefix = "flowly.assignments."
    private var accountKey: String = "local"

    func load(for account: String) {
        accountKey = account
        let key = keyPrefix + accountKey + ".v1"
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([Assignment].self, from: data) {
            assignments = list
        } else {
            assignments = []
        }
    }

    func replace(with newAssignments: [Assignment]) {
        assignments = newAssignments
    }

    func reset(for account: String? = nil) {
        let key = keyPrefix + (account ?? accountKey) + ".v1"
        UserDefaults.standard.removeObject(forKey: key)
        if account == nil || account == accountKey {
            assignments = []
        }
    }

    func migrateLocalIfNeeded(to emailKey: String) {
        guard emailKey != "local" else { return }
        let localKey = keyPrefix + "local.v1"
        let destKey  = keyPrefix + emailKey + ".v1"
        guard UserDefaults.standard.data(forKey: destKey) == nil,
              let localData = UserDefaults.standard.data(forKey: localKey) else { return }
        UserDefaults.standard.set(localData, forKey: destKey)
    }

    private func save() {
        let key = keyPrefix + accountKey + ".v1"
        if let data = try? JSONEncoder().encode(assignments) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
