import Foundation
import SwiftUI
import Combine

/// Holds assignments and settings, regenerates the schedule automatically when settings/assignments change.
@MainActor
class ScheduleManager: ObservableObject {
    @Published var plannedDays: [PlannedDay] = [] {
        didSet {
            print("[DEBUG] ScheduleManager.plannedDays changed: \(plannedDays.count) days (was \(oldValue.count))")
            if !plannedDays.isEmpty {
                print("[DEBUG]   First day: \(plannedDays.first?.date ?? Date()), blocks: \(plannedDays.first?.assignmentBlocks.count ?? 0)")
            } else if !oldValue.isEmpty {
                print("[DEBUG]   WARNING: Schedule was cleared! Stack trace:")
                Thread.callStackSymbols.prefix(5).forEach { print("[DEBUG]     \($0)") }
            }
        }
    }

    private var assignments: [AssignmentInput]
    var settings: ScheduleSettings {
        didSet {
            // Cancel old observations
            cancellables.removeAll()
            // Set up new observations
            observeSettings()
            checkAndRegenerateIfNeeded()
        }
    }
    private var cancellables = Set<AnyCancellable>()

    // Track inputs to detect changes
    private var lastAssignmentsHash: String = ""
    private var lastSettingsHash: String = ""
    private var justLoadedSchedule: Bool = false  // Track if we just loaded a schedule

    // Persistence keys - increment version when hash format changes
    private let scheduleKey = "flowly.schedule.plannedDays.v2"
    private let assignmentsHashKey = "flowly.schedule.assignmentsHash.v2"
    private let settingsHashKey = "flowly.schedule.settingsHash.v2"
    private let hashFormatVersionKey = "flowly.schedule.hashFormatVersion"
    private let currentHashFormatVersion = 2

    init(assignments: [AssignmentInput], settings: ScheduleSettings) {
        self.assignments = assignments
        self.settings = settings
        // Observe key settings
        observeSettings()
        // Try to load saved schedule first
        let loadedSuccessfully = loadSchedule()
        // Only regenerate if we didn't successfully load a schedule AND we have assignments
        if !loadedSuccessfully && !assignments.isEmpty {
            checkAndRegenerateIfNeeded()
        } else if !loadedSuccessfully && assignments.isEmpty {
            // If no assignments and couldn't load, don't clear immediately
            // The schedule will be updated when updateAssignments() is called with real assignments
            // Only clear if there's definitely no schedule to load
            print("[DEBUG] ScheduleManager.init: No assignments, skipping clear (will be updated by updateAssignments)")
        }
    }

    func updateAssignments(_ newAssignments: [AssignmentInput]) {
        guard AuthManager.shared.isSignedIn else {
            print("[DEBUG] updateAssignments: Skipping update because user is signed out")
            return
        }
        print("[DEBUG] updateAssignments: Called with \(newAssignments.count) assignments, current plannedDays.count=\(plannedDays.count), justLoadedSchedule=\(justLoadedSchedule)")

        // If we just loaded a schedule and the new assignments match what we loaded, skip everything
        if justLoadedSchedule {
            let newHash = hashAssignments(newAssignments)
            if newHash == lastAssignmentsHash {
                print("[DEBUG] updateAssignments: Just loaded schedule with same assignments, skipping update")
                return
            }
        }

        assignments = newAssignments
        // Try to load saved schedule for these assignments first
        let loadedSuccessfully = loadSchedule()
        print("[DEBUG] updateAssignments: loadSchedule returned \(loadedSuccessfully), plannedDays.count=\(plannedDays.count)")
        // Only regenerate if we didn't successfully load a schedule AND we have assignments
        if !loadedSuccessfully && !assignments.isEmpty {
            print("[DEBUG] updateAssignments: Calling checkAndRegenerateIfNeeded()")
            checkAndRegenerateIfNeeded()
        } else if !loadedSuccessfully && assignments.isEmpty {
            // If no assignments and couldn't load, only clear if we didn't just load
            if !justLoadedSchedule {
                print("[DEBUG] updateAssignments: Clearing schedule (no assignments, didn't load)")
                DispatchQueue.main.async {
                    self.plannedDays = []
                }
            } else {
                print("[DEBUG] updateAssignments: Skipping clear (just loaded schedule)")
            }
        } else {
            print("[DEBUG] updateAssignments: Loaded successfully, keeping schedule")
        }
        // If loaded successfully, do nothing - schedule is already set
    }

    private func observeSettings() {
        // Observe all relevant settings
        settings.objectWillChange.sink { [weak self] _ in
            print("[DEBUG] ScheduleManager: Settings changed, checking if regeneration needed")
            self?.checkAndRegenerateIfNeeded()
        }.store(in: &cancellables)
    }

    private func hashAssignments(_ assignments: [AssignmentInput]) -> String {
        // Create a deterministic hash from assignment IDs, due dates, and remaining hours
        // Sort by ID to ensure consistent ordering
        let sortedAssignments = assignments.sorted { $0.id < $1.id }
        let hashData = sortedAssignments.map { assignment in
            // Round to avoid floating point precision issues
            let roundedTotal = String(format: "%.2f", assignment.totalHours)
            let roundedCompleted = String(format: "%.2f", assignment.hoursCompleted)
            // Use date components instead of timeIntervalSince1970 to avoid timezone issues
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: assignment.dueDate)
            let dateStr = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)-\(components.hour ?? 0)-\(components.minute ?? 0)"
            return "\(assignment.id)|\(dateStr)|\(roundedTotal)|\(roundedCompleted)"
        }.joined(separator: "||")

        print("[DEBUG] hashAssignments: \(assignments.count) assignments")
        for (idx, assignment) in sortedAssignments.enumerated() {
            print("[DEBUG]   [\(idx)] id=\(assignment.id), due=\(assignment.dueDate), total=\(assignment.totalHours), completed=\(assignment.hoursCompleted)")
        }
        print("[DEBUG] hashAssignments: hashData=\(hashData.prefix(100))...")

        // Use a simple deterministic hash function
        let hash = deterministicHash(hashData)
        print("[DEBUG] hashAssignments: result=\(hash)")
        return hash
    }

    private func hashSettings(_ settings: ScheduleSettings) -> String {
        // Create a deterministic hash from relevant settings
        // Round to avoid floating point precision issues
        let roundedStart = String(format: "%.0f", settings.preferredStartInterval)
        let roundedEnd = String(format: "%.0f", settings.preferredEndInterval)
        let roundedBias = String(format: "%.2f", settings.loadBias)
        let hashString = "\(roundedStart)|\(roundedEnd)|\(roundedBias)"

        print("[DEBUG] hashSettings: startInterval=\(settings.preferredStartInterval), endInterval=\(settings.preferredEndInterval), loadBias=\(settings.loadBias)")
        print("[DEBUG] hashSettings: hashString=\(hashString)")

        let hash = deterministicHash(hashString)
        print("[DEBUG] hashSettings: result=\(hash)")
        return hash
    }

    // Simple deterministic hash function (djb2 algorithm)
    private func deterministicHash(_ string: String) -> String {
        var hash: UInt64 = 5381
        for char in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(char)
        }
        return String(hash)
    }

    private func checkAndRegenerateIfNeeded() {
        guard AuthManager.shared.isSignedIn else {
            print("[DEBUG] checkAndRegenerateIfNeeded: Skipping regeneration because user is signed out")
            return
        }
        print("[DEBUG] checkAndRegenerateIfNeeded: Called, justLoadedSchedule=\(justLoadedSchedule), plannedDays.count=\(plannedDays.count)")
        let currentAssignmentsHash = hashAssignments(assignments)
        let currentSettingsHash = hashSettings(settings)

        // Check if inputs have changed
        if currentAssignmentsHash != lastAssignmentsHash || currentSettingsHash != lastSettingsHash {
            print("[DEBUG] checkAndRegenerateIfNeeded: Inputs changed, regenerating")
            print("[DEBUG]   lastAssignmentsHash=\(lastAssignmentsHash.isEmpty ? "empty" : String(lastAssignmentsHash.prefix(10)))...")
            print("[DEBUG]   currentAssignmentsHash=\(currentAssignmentsHash.isEmpty ? "empty" : String(currentAssignmentsHash.prefix(10)))...")
            print("[DEBUG]   lastSettingsHash=\(lastSettingsHash.isEmpty ? "empty" : String(lastSettingsHash.prefix(10)))...")
            print("[DEBUG]   currentSettingsHash=\(currentSettingsHash.isEmpty ? "empty" : String(currentSettingsHash.prefix(10)))...")

            lastAssignmentsHash = currentAssignmentsHash
            lastSettingsHash = currentSettingsHash
            // Only regenerate if we have assignments, or if we're clearing the schedule
            if assignments.isEmpty {
                // Don't clear if we just loaded a schedule
                if justLoadedSchedule {
                    print("[DEBUG] checkAndRegenerateIfNeeded: Just loaded schedule, skipping clear")
                    // Update hashes to match current state so we don't trigger again
                    lastAssignmentsHash = currentAssignmentsHash
                    lastSettingsHash = currentSettingsHash
                    return
                }
                // Clear schedule if no assignments, but only if we actually had assignments before
                if !lastAssignmentsHash.isEmpty && lastAssignmentsHash != "5381" {
                    print("[DEBUG] checkAndRegenerateIfNeeded: Clearing schedule because assignments became empty")
                    DispatchQueue.main.async {
                        self.plannedDays = []
                        self.saveSchedule()
                    }
                } else {
                    print("[DEBUG] checkAndRegenerateIfNeeded: Assignments empty but no previous schedule, skipping clear")
                }
            } else {
                // Don't regenerate if we just loaded - the schedule is already correct
                if justLoadedSchedule {
                    print("[DEBUG] checkAndRegenerateIfNeeded: Just loaded schedule, skipping regeneration")
                    // Update hashes to match current state so we don't trigger again
                    lastAssignmentsHash = currentAssignmentsHash
                    lastSettingsHash = currentSettingsHash
                    return
                }
                regenerateSchedule()
            }
        } else {
            print("[DEBUG] checkAndRegenerateIfNeeded: Inputs unchanged, skipping regeneration")
        }
    }

    @discardableResult
    private func loadSchedule() -> Bool {
        print("[DEBUG] loadSchedule: Attempting to load saved schedule")

        // Check if saved schedule uses the current hash format version
        let savedFormatVersion = UserDefaults.standard.integer(forKey: hashFormatVersionKey)
        if savedFormatVersion != currentHashFormatVersion {
            print("[DEBUG] loadSchedule: Saved schedule uses old hash format (v\(savedFormatVersion)), current is v\(currentHashFormatVersion). Clearing old schedule.")
            // Clear old schedule data
            UserDefaults.standard.removeObject(forKey: scheduleKey)
            UserDefaults.standard.removeObject(forKey: assignmentsHashKey)
            UserDefaults.standard.removeObject(forKey: settingsHashKey)
            plannedDays = []
            return false
        }

        // Load saved schedule
        guard let data = UserDefaults.standard.data(forKey: scheduleKey) else {
            print("[DEBUG] loadSchedule: No saved schedule data found")
            plannedDays = []
            return false
        }

        guard let savedDays = try? JSONDecoder().decode([PlannedDay].self, from: data) else {
            print("[DEBUG] loadSchedule: Failed to decode saved schedule")
            plannedDays = []
            return false
        }

        // Verify the saved schedule matches current inputs
        let savedAssignmentsHash = UserDefaults.standard.string(forKey: assignmentsHashKey) ?? ""
        let savedSettingsHash = UserDefaults.standard.string(forKey: settingsHashKey) ?? ""

        let currentAssignmentsHash = hashAssignments(assignments)
        let currentSettingsHash = hashSettings(settings)

        print("[DEBUG] loadSchedule: savedAssignmentsHash=\(savedAssignmentsHash.isEmpty ? "empty" : String(savedAssignmentsHash.prefix(10)))...")
        print("[DEBUG] loadSchedule: currentAssignmentsHash=\(currentAssignmentsHash.isEmpty ? "empty" : String(currentAssignmentsHash.prefix(10)))...")
        print("[DEBUG] loadSchedule: savedSettingsHash=\(savedSettingsHash.isEmpty ? "empty" : String(savedSettingsHash.prefix(10)))...")
        print("[DEBUG] loadSchedule: currentSettingsHash=\(currentSettingsHash.isEmpty ? "empty" : String(currentSettingsHash.prefix(10)))...")

        // Only use saved schedule if inputs match
        guard savedAssignmentsHash == currentAssignmentsHash && savedSettingsHash == currentSettingsHash else {
            print("[DEBUG] loadSchedule: Hashes don't match - saved schedule is for different inputs")
            plannedDays = []
            return false
        }

        // Check if schedule is still valid (not too old - e.g., within last 7 days)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let isValid = savedDays.contains { day in
            let dayStart = calendar.startOfDay(for: day.date)
            return dayStart >= today || calendar.dateComponents([.day], from: dayStart, to: today).day ?? 0 <= 7
        }

        guard isValid else {
            print("[DEBUG] loadSchedule: Saved schedule is too old or invalid")
            plannedDays = []
            return false
        }

        print("[DEBUG] loadSchedule: Successfully loaded \(savedDays.count) planned days")
        // Mark that we're about to load, so observers don't interfere
        justLoadedSchedule = true
        // Set synchronously since we're already on MainActor
        plannedDays = savedDays
        lastAssignmentsHash = currentAssignmentsHash
        lastSettingsHash = currentSettingsHash
        // Reset the flag after a delay to allow any pending operations to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.justLoadedSchedule = false
            print("[DEBUG] loadSchedule: Reset justLoadedSchedule flag")
        }
        return true
    }

    private func saveSchedule() {
        // Save schedule to UserDefaults
        guard let data = try? JSONEncoder().encode(plannedDays) else {
            print("[DEBUG] saveSchedule: Failed to encode schedule")
            return
        }
        UserDefaults.standard.set(data, forKey: scheduleKey)
        UserDefaults.standard.set(lastAssignmentsHash, forKey: assignmentsHashKey)
        UserDefaults.standard.set(lastSettingsHash, forKey: settingsHashKey)
        UserDefaults.standard.set(currentHashFormatVersion, forKey: hashFormatVersionKey)
        print("[DEBUG] saveSchedule: Saved \(plannedDays.count) planned days with hash=\(String(lastAssignmentsHash.prefix(10)))... (format v\(currentHashFormatVersion))")
    }

    /// Force regeneration of the schedule, bypassing the load check
    func forceRegenerate() {
        print("[DEBUG] ScheduleManager: Force regenerating schedule")
        
        // Skip regeneration if user is signed out to prevent phantom Google sign-in
        guard AuthManager.shared.isSignedIn else {
            print("[DEBUG] ScheduleManager: Skipping forceRegenerate — user signed out")
            return
        }

        // Update hashes to current state to prevent immediate re-check
        lastAssignmentsHash = hashAssignments(assignments)
        lastSettingsHash = hashSettings(settings)
        regenerateSchedule()
    }

    private func regenerateSchedule() {
        // Skip regeneration if no assignments or user is signed out
        guard !assignments.isEmpty else {
            DispatchQueue.main.async {
                self.plannedDays = []
                self.saveSchedule()
            }
            return
        }
        
        guard AuthManager.shared.isSignedIn else {
            print("[DEBUG] ScheduleManager: Skipping regenerateSchedule — user signed out")
            return
        }

        let calendar = Calendar.current
        let startComps = calendar.dateComponents([.hour, .minute], from: settings.preferredStartTime)
        let endComps = calendar.dateComponents([.hour, .minute], from: settings.preferredEndTime)
        // Save updated preferred start and end times to internal settings
        settings.preferredStartTime = calendar.date(from: startComps) ?? settings.preferredStartTime
        settings.preferredEndTime = calendar.date(from: endComps) ?? settings.preferredEndTime

        // Calculate planning horizon based on assignment due dates
        let today = calendar.startOfDay(for: Date())
        let latestDue = assignments.map { $0.dueDate }.max() ?? today
        let daysBetween = max(1, calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: latestDue)).day ?? 0) + 1

        let schedule = ScheduleGenerator.generateSchedule(
            assignments: assignments,
            preferredStartTime: startComps,
            preferredEndTime: endComps,
            planningHorizonDays: daysBetween,
            loadBias: settings.loadBias,
            currentTime: Date()
        )

        DispatchQueue.main.async {
            self.plannedDays = schedule
            self.saveSchedule()
        }
    }
}
