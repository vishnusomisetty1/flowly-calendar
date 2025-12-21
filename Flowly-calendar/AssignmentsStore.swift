import Foundation

@MainActor
final class AssignmentsStore: ObservableObject {
@Published var assignments: [Assignment] = []

    /// Refresh assignments for the selected classrooms, preserving custom assignments and local edits.
    /// - Parameters:
    ///   - selected: The selected GoogleClassroom objects.
    ///   - auth: The AuthManager for authentication.
    @MainActor
    func refreshAssignments(forSelectedClassrooms selected: [GoogleClassroom], auth: AuthManager) async {
        let selectedClassroomIds = Set(selected.filter { $0.isSelected }.map { $0.id })
        var assignmentsToKeep = assignments.filter { assignment in
            assignment.courseId == nil || (assignment.courseId != nil && selectedClassroomIds.contains(assignment.courseId!))
        }
        if auth.isSignedIn && !selectedClassroomIds.isEmpty {
            do {
                let token = try await auth.getFreshAccessToken(requiredScopes: [
                    "https://www.googleapis.com/auth/classroom.courses.readonly",
                    "https://www.googleapis.com/auth/classroom.coursework.me.readonly",
                    "https://www.googleapis.com/auth/classroom.coursework.me"
                ]).token
                let fetched = try await AssignmentSync.fetchForSelectedClasses(token: token, classes: selected.filter { $0.isSelected })
                var mergedById = Dictionary(uniqueKeysWithValues: assignmentsToKeep.map { ($0.id, $0) })
                for assignment in fetched {
                    if let local = mergedById[assignment.id] {
                        mergedById[assignment.id] = local
                    } else {
                        mergedById[assignment.id] = assignment
                    }
                }
                assignmentsToKeep = Array(mergedById.values)
            } catch {
                print("DEBUG: Failed to fetch assignments: \(error)")
            }
        }
        replace(with: assignmentsToKeep)
    }

@MainActor
func updateAssignment(
    id: UUID,
    title: String? = nil,
    description: String? = nil,
    dueDate: Date? = nil,
    isCompleted: Bool? = nil,
    aiEstimatedTime: Int? = nil,
    aiEstimatedImportance: Int? = nil,
    hasRealDueDate: Bool? = nil
) {
    guard let index = assignments.firstIndex(where: { $0.id == id }) else { return }
    if let title = title { assignments[index].title = title }
    if let description = description { assignments[index].description = description }
    if let dueDate = dueDate { assignments[index].dueDate = dueDate }
    if let isCompleted = isCompleted { assignments[index].isCompleted = isCompleted }
    if let aiEstimatedTime = aiEstimatedTime { assignments[index].aiEstimatedTime = aiEstimatedTime }
    if let aiEstimatedImportance = aiEstimatedImportance { assignments[index].aiEstimatedImportance = aiEstimatedImportance }
    if let hasRealDueDate = hasRealDueDate { assignments[index].hasRealDueDate = hasRealDueDate }
    save()
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

@MainActor
func toggleCompletion(for assignmentId: UUID) {
    guard let index = assignments.firstIndex(where: { $0.id == assignmentId }) else { return }
    assignments[index].isCompleted.toggle()
    save() // Persist immediately

    // Debug log to verify persistence
    print("DEBUG: Toggled assignment \(assignments[index].title) to \(assignments[index].isCompleted)")
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
    save()
}

/// Merges fetched assignments with existing assignments, preserving custom assignments (courseId == nil)
/// and all local modifications (like completion state, edits, etc.), including those without real due dates.
/// - Parameter fetchedAssignments: assignments fetched from remote (usually courseId != nil)
@MainActor
func mergeAssignments(_ fetchedAssignments: [Assignment]) {
    // Dictionary of current assignments by id
    var currentById = Dictionary(uniqueKeysWithValues: assignments.map { ($0.id, $0) })

    // Start with all current assignments (including custom and local changes)
    var mergedById = currentById

    // For each fetched assignment:
    for fetched in fetchedAssignments {
        if let local = currentById[fetched.id] {
            // Preserve all local assignments and custom assignments (courseId == nil), and local changes
            mergedById[fetched.id] = local
        } else {
            mergedById[fetched.id] = fetched
        }
    }
    // Remove duplicates by id (dictionary ensures this)
    // Ensure custom assignments (courseId == nil) and no-due-date assignments are preserved and not overwritten
    let merged = Array(mergedById.values)
    replace(with: merged)
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
    // Ensure all assignments (including no due date and custom) are included
    do {
        let data = try JSONEncoder().encode(assignments)
        UserDefaults.standard.set(data, forKey: key)
        UserDefaults.standard.synchronize() // Force write to disk immediately
    } catch {
        print("DEBUG: Failed to save assignments: \(error)")
    }
}
}

// Uses Assignment model from Models.swift
