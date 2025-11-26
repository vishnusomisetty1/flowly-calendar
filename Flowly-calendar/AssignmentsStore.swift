import Foundation

@MainActor
final class AssignmentsStore: ObservableObject {
    @Published var assignments: [Assignment] = [] {
        didSet { save() }
    }

    // Organized assignment groups based on current time (not just start of day)
    func missingAssignments(filteredAfter date: Date? = nil) -> [Assignment] {
        let calendar = Calendar.current
        let now = Date()
        let startOfNow = calendar.startOfDay(for: now)
        
        return assignments.filter { assignment in
            guard !assignment.isCompleted && assignment.hasRealDueDate else { return false }
            // Compare using start of day for both dates to avoid timezone issues
            let assignmentStartOfDay = calendar.startOfDay(for: assignment.dueDate)
            // Must be before now
            return assignmentStartOfDay < startOfNow
        }
        .sorted { 
            calendar.startOfDay(for: $0.dueDate) < calendar.startOfDay(for: $1.dueDate)
        }
    }
    
    // Convenience property for backwards compatibility
    var missingAssignments: [Assignment] {
        missingAssignments(filteredAfter: nil)
    }
    
    // Removed updateDuration and updatePoints methods - migrated to AI estimated properties
    
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
    
    func completedAssignments(filteredAfter date: Date? = nil) -> [Assignment] {
        let calendar = Calendar.current
        
        return assignments.filter { assignment in
            guard assignment.isCompleted else { return false }
            // Show all completed assignments regardless of filter date
            return true
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

// Uses Assignment model from Models.swift
