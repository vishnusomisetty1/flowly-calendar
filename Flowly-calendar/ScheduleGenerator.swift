import Foundation

public struct AssignmentInput {
    public let id: String
    public let dueDate: Date
    public let totalHours: Double
    public let hoursCompleted: Double
    public let importance: Double
    public init(id: String, dueDate: Date, totalHours: Double, hoursCompleted: Double, importance: Double) {
        self.id = id
        self.dueDate = dueDate
        self.totalHours = totalHours
        self.hoursCompleted = hoursCompleted
        self.importance = importance
    }
}

public struct DailyAssignmentBlock: Identifiable, Codable {
    public let id: UUID
    public let assignmentId: String
    public let startTime: Date
    public let endTime: Date
    public let preferredHours: Double
    public let overflowHours: Double
    public let bufferLeft: Double
    public let overflowReason: String?
    public init(assignmentId: String, startTime: Date, endTime: Date, preferredHours: Double, overflowHours: Double, bufferLeft: Double, overflowReason: String?) {
        self.id = UUID()
        self.assignmentId = assignmentId
        self.startTime = startTime
        self.endTime = endTime
        self.preferredHours = preferredHours
        self.overflowHours = overflowHours
        self.bufferLeft = bufferLeft
        self.overflowReason = overflowReason
    }
}

public struct PlannedDay: Codable {
    public let date: Date
    public let assignmentBlocks: [DailyAssignmentBlock]
    public let urgencies: [String: Double]
    public let allOnTrack: Bool
    public init(date: Date, assignmentBlocks: [DailyAssignmentBlock], urgencies: [String: Double], allOnTrack: Bool) {
        self.date = date
        self.assignmentBlocks = assignmentBlocks
        self.urgencies = urgencies
        self.allOnTrack = allOnTrack
    }
}

// Helper: a single window to allocate into
fileprivate struct AllocationWindow {
    enum WindowType { case preferred, overflow, early }
    let assignment: AssignmentInput
    let date: Date // day start
    let type: WindowType
    let start: Date
    let end: Date
    var durationSeconds: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

// Core allocator: builds candidate windows for each assignment across the planning horizon then allocates hours.
fileprivate func allocateAssignmentsAcrossHorizon(assignments: [AssignmentInput], startDate: Date, endDate: Date, loadBias: Double, preferredStartTime: DateComponents, preferredEndTime: DateComponents, currentTime: Date = Date()) -> [(assignment: AssignmentInput, start: Date, end: Date, overflow: Bool)] {
    print("[DEBUG] Starting horizon allocation. assignments=\(assignments.count), loadBias=\(loadBias)")
    var allocations: [(assignment: AssignmentInput, start: Date, end: Date, overflow: Bool)] = []
    let calendar = Calendar.current

    // Build planning days (inclusive)
    var dayCursor = calendar.startOfDay(for: startDate)
    let horizonEndDay = calendar.startOfDay(for: endDate)
    var planningDays: [Date] = []
    while dayCursor <= horizonEndDay {
        planningDays.append(dayCursor)
        guard let next = calendar.date(byAdding: .day, value: 1, to: dayCursor) else { break }
        dayCursor = next
    }

    // For each assignment, collect windows (preferred, overflow, early) up to its dueDate and respecting currentTime
    var windowsByAssignment: [String: [AllocationWindow]] = [:]
    var remainingSecondsByAssignment: [String: TimeInterval] = [:]

    for assignment in assignments {
        print("[DEBUG] Processing assignment: \(assignment.id), remainingHours=\(max(0, assignment.totalHours - assignment.hoursCompleted))")
        let remainingHours = max(0, assignment.totalHours - assignment.hoursCompleted)
        let remainingSeconds = remainingHours * 3600.0
        remainingSecondsByAssignment[assignment.id] = remainingSeconds

        var windows: [AllocationWindow] = []
        for day in planningDays {
            // don't include days after assignment due date
            if day > calendar.startOfDay(for: assignment.dueDate) { break }

            // day local boundaries
            let dayStart = calendar.startOfDay(for: day)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!.addingTimeInterval(-1)

            // preferred window for this day
            let prefStartHour = preferredStartTime.hour ?? 17
            let prefStartMin = preferredStartTime.minute ?? 0
            let prefEndHour = preferredEndTime.hour ?? 18
            let prefEndMin = preferredEndTime.minute ?? 0

            let prefStart = calendar.date(bySettingHour: prefStartHour, minute: prefStartMin, second: 0, of: dayStart) ?? dayStart
            let prefEnd = calendar.date(bySettingHour: prefEndHour, minute: prefEndMin, second: 0, of: dayStart) ?? dayStart

            // early: dayStart .. prefStart
            // overflow: prefEnd .. dayEnd
            // truncate any window on the assignment due day to assignment.dueDate
            let isDueDay = calendar.isDate(assignment.dueDate, inSameDayAs: day)
            let dueCutoff = assignment.dueDate

            // preferred
            var pStart = prefStart
            var pEnd = prefEnd
            if isDueDay {
                if pEnd > dueCutoff { pEnd = dueCutoff }
            }
            if pEnd > pStart {
                // respect current time for today's windows
                pStart = max(pStart, currentTime)
                if pEnd > pStart {
                    windows.append(AllocationWindow(assignment: assignment, date: dayStart, type: .preferred, start: pStart, end: pEnd))
                }
            }

            // overflow
            var oStart = prefEnd
            var oEnd = dayEnd
            if isDueDay {
                if oEnd > dueCutoff { oEnd = dueCutoff }
            }
            if oEnd > oStart {
                oStart = max(oStart, currentTime)
                if oEnd > oStart {
                    windows.append(AllocationWindow(assignment: assignment, date: dayStart, type: .overflow, start: oStart, end: oEnd))
                }
            }

            // early
            var eStart = dayStart
            var eEnd = prefStart
            if isDueDay {
                if eEnd > dueCutoff { eEnd = dueCutoff }
            }
            if eEnd > eStart {
                eStart = max(eStart, currentTime)
                if eEnd > eStart {
                    windows.append(AllocationWindow(assignment: assignment, date: dayStart, type: .early, start: eStart, end: eEnd))
                }
            }
        }
        windowsByAssignment[assignment.id] = windows
    }

    // Dictionary tracking occupied intervals per day to avoid overlapping allocations
    var occupiedIntervalsByDay: [Date: [(start: Date, end: Date)]] = [:]

    // Helper function to find non-overlapping free intervals within a proposed interval for a given day
    func freeIntervals(in intervalStart: Date, to intervalEnd: Date, occupied: [(start: Date, end: Date)]) -> [(start: Date, end: Date)] {
        var free: [(start: Date, end: Date)] = []
        var currentStart = intervalStart

        // occupied intervals should be sorted by start
        let sortedOccupied = occupied.sorted { $0.start < $1.start }

        for occ in sortedOccupied {
            if occ.end <= currentStart {
                // This occupied interval ends before currentStart, no overlap
                continue
            }
            if occ.start >= intervalEnd {
                // This occupied is after the interval, no more overlaps
                break
            }
            if occ.start > currentStart {
                // free interval before this occupied interval
                free.append((start: currentStart, end: min(occ.start, intervalEnd)))
            }
            // move currentStart past this occupied interval
            currentStart = max(currentStart, occ.end)
            if currentStart >= intervalEnd {
                break
            }
        }
        // any free interval after last occupied interval
        if currentStart < intervalEnd {
            free.append((start: currentStart, end: intervalEnd))
        }
        return free
    }

    // Allocation strategy:
    // Strictly allocate by type in order (preferred → overflow → early) fully filling each before moving on.
    for assignment in assignments {
        guard var remaining = remainingSecondsByAssignment[assignment.id], remaining > 0 else { continue }
        let windows = windowsByAssignment[assignment.id] ?? []

        // partition windows by type and sort by date ascending
        let prefWindows = windows.filter { $0.type == .preferred }.sorted { $0.date < $1.date }
        let overflowWindows = windows.filter { $0.type == .overflow }.sorted { $0.date < $1.date }
        let earlyWindows = windows.filter { $0.type == .early }.sorted { $0.date < $1.date }

        // 1) Preferred - fill fully before moving on
        for win in prefWindows {
            guard remaining > 0 else { break }
            let windowSeconds = win.durationSeconds
            if windowSeconds <= 0 { continue }
            let day = win.date
            let occupied = occupiedIntervalsByDay[day] ?? []

            // Find free intervals within this window that do not overlap with existing allocations
            let freeIntervalsInWindow = freeIntervals(in: win.start, to: win.end, occupied: occupied)

            // Allocate into free intervals up to remaining need
            for freeInterval in freeIntervalsInWindow {
                guard remaining > 0 else { break }
                let freeDuration = freeInterval.end.timeIntervalSince(freeInterval.start)
                if freeDuration <= 0 { continue }
                let allocSeconds = min(remaining, freeDuration)
                let allocStart = freeInterval.start
                let allocEnd = allocStart.addingTimeInterval(allocSeconds)
                allocations.append((assignment, allocStart, allocEnd, false))
                print("[DEBUG] Allocated preferred (non-overlapping): id=\(assignment.id) start=\(allocStart) end=\(allocEnd)")
                remaining -= allocSeconds

                // Record this allocation to occupied intervals for the day
                occupiedIntervalsByDay[day, default: []].append((start: allocStart, end: allocEnd))
            }
        }

        // 2) Overflow - only if remaining > 0
        for win in overflowWindows {
            guard remaining > 0 else { break }
            let windowSeconds = win.durationSeconds
            if windowSeconds <= 0 { continue }
            let day = win.date
            let occupied = occupiedIntervalsByDay[day] ?? []

            // Find free intervals within this window that do not overlap with existing allocations
            let freeIntervalsInWindow = freeIntervals(in: win.start, to: win.end, occupied: occupied)

            // Allocate into free intervals up to remaining need
            for freeInterval in freeIntervalsInWindow {
                guard remaining > 0 else { break }
                let freeDuration = freeInterval.end.timeIntervalSince(freeInterval.start)
                if freeDuration <= 0 { continue }
                let allocSeconds = min(remaining, freeDuration)
                let allocStart = freeInterval.start
                let allocEnd = allocStart.addingTimeInterval(allocSeconds)
                allocations.append((assignment, allocStart, allocEnd, true))
                print("[DEBUG] Allocated overflow (non-overlapping): id=\(assignment.id) start=\(allocStart) end=\(allocEnd)")
                remaining -= allocSeconds

                // Record this allocation to occupied intervals for the day
                occupiedIntervalsByDay[day, default: []].append((start: allocStart, end: allocEnd))
            }
        }

        // 3) Early - only if remaining > 0
        for win in earlyWindows {
            guard remaining > 0 else { break }
            let windowSeconds = win.durationSeconds
            if windowSeconds <= 0 { continue }
            let day = win.date
            let occupied = occupiedIntervalsByDay[day] ?? []

            // Find free intervals within this window that do not overlap with existing allocations
            let freeIntervalsInWindow = freeIntervals(in: win.start, to: win.end, occupied: occupied)

            // Allocate into free intervals up to remaining need
            for freeInterval in freeIntervalsInWindow {
                guard remaining > 0 else { break }
                let freeDuration = freeInterval.end.timeIntervalSince(freeInterval.start)
                if freeDuration <= 0 { continue }
                let allocSeconds = min(remaining, freeDuration)
                let allocStart = freeInterval.start
                let allocEnd = allocStart.addingTimeInterval(allocSeconds)
                allocations.append((assignment, allocStart, allocEnd, true))
                print("[DEBUG] Allocated early (non-overlapping): id=\(assignment.id) start=\(allocStart) end=\(allocEnd)")
                remaining -= allocSeconds

                // Record this allocation to occupied intervals for the day
                occupiedIntervalsByDay[day, default: []].append((start: allocStart, end: allocEnd))
            }
        }

        remainingSecondsByAssignment[assignment.id] = remaining
    }

    return allocations
}

public struct ScheduleGenerator {

    public static func generateSchedule(
        assignments: [AssignmentInput],
        preferredStartTime: DateComponents,
        preferredEndTime: DateComponents,
        planningHorizonDays: Int? = nil,
        loadBias: Double,
        currentTime: Date? = nil
    ) -> [PlannedDay] {
        let sortedAssignments = assignments.sorted {
            if $0.dueDate != $1.dueDate {
                return $0.dueDate < $1.dueDate
            } else {
                return $0.importance > $1.importance
            }
        }
        print("[DEBUG] generateSchedule called. assignments=\(sortedAssignments.count), horizonDays=\(planningHorizonDays ?? -1)")
        let calendar = Calendar.current
        let now = currentTime ?? Date()
        let today = calendar.startOfDay(for: now)

        guard !sortedAssignments.isEmpty else { return [] }

        // compute horizon end date (inclusive)
        let lastDueDate = sortedAssignments.map { $0.dueDate }.max() ?? today
        let horizonEndDate: Date
        if let days = planningHorizonDays, days > 0 {
            let minHorizon = calendar.date(byAdding: .day, value: days - 1, to: today) ?? today
            horizonEndDate = max(minHorizon, calendar.startOfDay(for: lastDueDate))
        } else {
            horizonEndDate = calendar.startOfDay(for: lastDueDate)
        }

        // Generate allocations
        let rawAllocations = allocateAssignmentsAcrossHorizon(
            assignments: sortedAssignments,
            startDate: today,
            endDate: horizonEndDate,
            loadBias: loadBias,
            preferredStartTime: preferredStartTime,
            preferredEndTime: preferredEndTime,
            currentTime: now
        )

        // Group allocations by day into DailyAssignmentBlock
        var blocksByDay: [Date: [DailyAssignmentBlock]] = [:]
        for (assignment, start, end, overflow) in rawAllocations {
            let blockDate = calendar.startOfDay(for: start)
            let durationHours = max(0.0, end.timeIntervalSince(start) / 3600.0)
            let preferredH = overflow ? 0.0 : durationHours
            let overflowH = overflow ? durationHours : 0.0
            let block = DailyAssignmentBlock(assignmentId: assignment.id, startTime: start, endTime: end, preferredHours: preferredH, overflowHours: overflowH, bufferLeft: 0, overflowReason: overflow ? "Allocated in overflow/early" : nil)
            blocksByDay[blockDate, default: []].append(block)
        }

        // Build planning dates list
        var dates: [Date] = []
        var d = today
        while d <= horizonEndDate {
            dates.append(d)
            guard let n = calendar.date(byAdding: .day, value: 1, to: d) else { break }
            d = n
        }

        // Build PlannedDay array keeping same shape as before
        var planned: [PlannedDay] = []
        for date in dates {
            let blocks = blocksByDay[date] ?? []
            let urgencies = sortedAssignments.reduce(into: [String: Double]()) { acc, a in
                let remainingHours = max(0.0, a.totalHours - a.hoursCompleted)
                let hoursUntilDue = max(1.0, a.dueDate.timeIntervalSince(date) / 3600.0) // avoid division by zero
                let urgency = remainingHours / hoursUntilDue
                acc[a.id] = urgency
            }
            let onTrack = true
            planned.append(PlannedDay(date: date, assignmentBlocks: blocks, urgencies: urgencies, allOnTrack: onTrack))
        }
        print("[DEBUG] Planned days generated: \(planned.count)")

        return planned
    }
}
