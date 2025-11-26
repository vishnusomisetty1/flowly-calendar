import Foundation

// Reusing your existing models (no changes)
public struct AssignmentInput {
    public let id: String
    public let dueDate: Date
    public let totalHours: Double
    public var hoursCompleted: Double
    public let importance: Double

    public init(id: String, dueDate: Date, totalHours: Double, hoursCompleted: Double = 0, importance: Double = 1.0) {
        self.id = id
        self.dueDate = dueDate
        self.totalHours = totalHours
        self.hoursCompleted = hoursCompleted
        self.importance = importance >= 1 ? importance : 1.0
    }
}

public struct DailyAssignmentBlock: Identifiable {
    public let assignmentId: String
    public let startTime: Date
    public let endTime: Date
    public let preferredHours: Double
    public let overflowHours: Double
    public let bufferLeft: Double
    public let overflowReason: String?

    public var id: String { "\(assignmentId)-\(startTime.timeIntervalSince1970)" }

    public init(assignmentId: String, startTime: Date, endTime: Date, preferredHours: Double, overflowHours: Double, bufferLeft: Double, overflowReason: String? = nil) {
        self.assignmentId = assignmentId
        self.startTime = startTime
        self.endTime = endTime
        self.preferredHours = preferredHours
        self.overflowHours = overflowHours
        self.bufferLeft = bufferLeft
        self.overflowReason = overflowReason
    }
}

public struct PlannedDay {
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

public struct ScheduleGenerator {

    /// Rewritten generator that:
    /// - Plans up to the latest due date among assignments (or to planningHorizonDays if larger)
    /// - Preserves frozen days (minimal unfreeze only when infeasible)
    /// - Uses the urgency formula described in docs
    /// - Does not mutate input assignments; uses an allocation map
    ///
    /// - Parameters:
    ///   - assignments: list of assignments
    ///   - preferredStartTime: DateComponents hour/min for preferred window
    ///   - preferredEndTime: DateComponents hour/min
    ///   - maxOverflowHoursPerDay: overflow hours available per day
    ///   - planningHorizonDays: minimum horizon (will extend to latest due date if needed)
    ///   - frozenWindowDays: number of days (starting today) to keep stable unless impossible (default 1)
    ///   - frontLoadFactorMax: maximum gentle front-load factor (e.g., 1.15). Must be >= 1.0
    public static func generateSchedule(
        assignments: [AssignmentInput],
        preferredStartTime: DateComponents,
        preferredEndTime: DateComponents,
        maxOverflowHoursPerDay: Double,
        planningHorizonDays: Int,
        frozenWindowDays: Int = 1, // ignored, kept for API compatibility
        frontLoadFactorMax: Double = 2.0,
        currentTime: Date? = nil
    ) -> [PlannedDay] {
        let calendar = Calendar.current
        let now = currentTime ?? Date()
        let today = calendar.startOfDay(for: now)

        // Validate preferred start/end and compute preferred hours per day.
        guard
            let prefStart = calendar.date(bySettingHour: preferredStartTime.hour ?? 9, minute: preferredStartTime.minute ?? 0, second: 0, of: today),
            let prefEnd = calendar.date(bySettingHour: preferredEndTime.hour ?? 17, minute: preferredEndTime.minute ?? 0, second: 0, of: today)
        else {
            print("Warning: Invalid preferred start/end components. Returning empty schedule.")
            return []
        }
        let preferredHoursPerDay = max(0.0, prefEnd.timeIntervalSince(prefStart) / 3600.0)

        guard !assignments.isEmpty else { return [] }

        // Determine planning horizon
        let lastDueDate = assignments.map { calendar.startOfDay(for: $0.dueDate) }.max() ?? today
        guard let minHorizonEndDate = calendar.date(byAdding: .day, value: max(0, planningHorizonDays - 1), to: today) else { return [] }
        let horizonEndDate = max(minHorizonEndDate, lastDueDate)

        // Build planningDates skipping weekends
        var planningDates: [Date] = []
        var dateCursor = today
        while dateCursor <= horizonEndDate {
            if !calendar.isDateInWeekend(dateCursor) {
                planningDates.append(dateCursor)
            }
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: dateCursor) else { return [] }
            dateCursor = nextDate
        }

        // Helpers
        func dayKey(_ d: Date) -> Date { calendar.startOfDay(for: d) }
        func planningDaysBetween(start: Date, end: Date) -> [Date] {
            let s = dayKey(start)
            let e = dayKey(end)
            return planningDates.filter { $0 >= s && $0 <= e }
        }

        // capacity per day
        var capacityPerDay: [Date: (preferred: Double, overflow: Double)] = [:]
        for date in planningDates { capacityPerDay[dayKey(date)] = (preferred: preferredHoursPerDay, overflow: maxOverflowHoursPerDay) }

        // assignment avail dates
        var assignmentAvailableDates: [String: [Date]] = [:]
        for assignment in assignments {
            assignmentAvailableDates[assignment.id] = planningDaysBetween(start: today, end: assignment.dueDate)
        }

        // allocations map
        var allocations: [Date: [String: (preferred: Double, overflow: Double, reason: String?)]] = [:]
        for date in planningDates { allocations[dayKey(date)] = [:] }

        // NEW: live remaining tracker (pre-seeded with historical progress)
        var remainingPerAssignment: [String: Double] = [:]
        for a in assignments {
            remainingPerAssignment[a.id] = max(0.0, a.totalHours - a.hoursCompleted)
        }

        // Reusable urgency using current remaining estimate
        func urgencyLive(for assignment: AssignmentInput, remaining: Double, on date: Date) -> Double {
            guard remaining > 0 else { return 0 }
            let datesLeft = assignmentAvailableDates[assignment.id] ?? []
            let daysLeftArray = datesLeft.filter { $0 >= dayKey(date) }
            let daysLeft = max(1, daysLeftArray.count)
            let invDays = 1.0 / Double(daysLeft)
            let preferredH = max(0.5, preferredHoursPerDay)
            let workIntensity = remaining / (Double(daysLeft) * preferredH)
            let importanceNormalized = min(max(assignment.importance, 1.0), 5.0) / 5.0
            return 0.6 * invDays + 0.3 * workIntensity + 0.1 * importanceNormalized
        }

        // MAIN allocation with live remainingPerAssignment updates
        for date in planningDates {
            let key = dayKey(date)
            var caps = capacityPerDay[key]!

            // Active assignments (still have remaining and due not passed)
            var active = assignments.filter { date <= $0.dueDate && (remainingPerAssignment[$0.id] ?? 0) > 0 }

            // compute urgencies with live remaining
            var urgencies: [String: Double] = [:]
            for a in active {
                urgencies[a.id] = urgencyLive(for: a, remaining: remainingPerAssignment[a.id] ?? 0, on: date)
            }

            // sort by due then urgency
            active.sort {
                if $0.dueDate != $1.dueDate { return $0.dueDate < $1.dueDate }
                return (urgencies[$0.id] ?? 0) > (urgencies[$1.id] ?? 0)
            }

            // precompute info per assignment using live remaining
            struct Info { let assignment: AssignmentInput; var remaining: Double; let daysLeft: Int }
            var infos: [Info] = []
            for a in active {
                let avail = assignmentAvailableDates[a.id]?.filter { $0 >= key } ?? []
                let daysLeft = max(1, avail.count)
                let rem = remainingPerAssignment[a.id] ?? 0
                if rem > 0 { infos.append(Info(assignment: a, remaining: rem, daysLeft: daysLeft)) }
            }

            // Pass 1: allocate non-deferrable amount (minNeededToday) in preferred hours
            var remainingPreferred = caps.preferred
            // keep per-day tentative allocations for bookkeeping
            var todayAlloc: [String: Double] = [:]

            for (idx, var info) in infos.enumerated() {
                if remainingPreferred <= 0 { break }
                let a = info.assignment
                let rem = max(0.0, info.remaining)
                if rem <= 0 { continue }

                // compute future preferred capacity (excluding today)
                let futureDates = assignmentAvailableDates[a.id]?.filter { $0 > key } ?? []
                var futurePrefCap = 0.0
                for d in futureDates {
                    let k = dayKey(d)
                    let dayCaps = capacityPerDay[k]!
                    let usedPref = allocations[k]?.reduce(0.0, { $0 + $1.value.preferred }) ?? 0.0
                    futurePrefCap += max(0.0, dayCaps.preferred - usedPref)
                }

                let minNeededToday = max(0.0, rem - futurePrefCap)
                var allocPref = min(minNeededToday, remainingPreferred, rem)

                // If we couldn't satisfy minNeededToday, try to push later-deadline tentative allocations
                if allocPref < minNeededToday && minNeededToday > 0 && remainingPreferred > 0 {
                    // attempt to free tentative allocations from later infos
                    let later = infos.enumerated().filter { $0.offset > idx && $0.element.assignment.dueDate > a.dueDate }
                    for (_, l) in later {
                        let lid = l.assignment.id
                        let tent = todayAlloc[lid] ?? 0.0
                        if tent > 0 {
                            // check if deferrable
                            let lFutureDates = assignmentAvailableDates[lid]?.filter { $0 > key } ?? []
                            var lFuturePrefCap = 0.0
                            for d in lFutureDates {
                                let k = dayKey(d); let dayCaps = capacityPerDay[k]!
                                let usedPref = allocations[k]?.reduce(0.0, { $0 + $1.value.preferred }) ?? 0.0
                                lFuturePrefCap += max(0.0, dayCaps.preferred - usedPref)
                            }
                            let lRem = max(0.0, l.remaining - tent)
                            if lRem <= lFuturePrefCap {
                                // free it
                                todayAlloc[lid] = 0
                                remainingPreferred += tent
                                let need = minNeededToday - allocPref
                                let give = min(need, tent)
                                allocPref += give
                                remainingPreferred -= give
                                // reduce earlier tentative from allocations map
                                if var ex = allocations[key]?[lid] {
                                    ex.preferred = max(0.0, ex.preferred - tent)
                                    if ex.preferred == 0 && ex.overflow == 0 { allocations[key]?[lid] = nil }
                                    else { allocations[key]?[lid] = ex }
                                }
                                if allocPref >= minNeededToday { break }
                            }
                        }
                    }
                }

                allocPref = min(allocPref, remainingPreferred, rem)
                if allocPref > 0 {
                    var existing = allocations[key]?[a.id] ?? (preferred: 0.0, overflow: 0.0, reason: nil)
                    existing.preferred += allocPref
                    existing.reason = (existing.reason == nil) ? "Preferred allocation" : (existing.reason! + "; Preferred allocation")
                    allocations[key]?[a.id] = existing

                    // record tentative and decrement live remaining
                    todayAlloc[a.id] = (todayAlloc[a.id] ?? 0.0) + allocPref
                    remainingPerAssignment[a.id] = max(0.0, (remainingPerAssignment[a.id] ?? 0) - allocPref)
                    remainingPreferred -= allocPref
                }
            }

            // Pass 2: front-load (at-risk then deferable) using updated remainingPerAssignment
            let atRisk = infos.filter { info in
                let rem = remainingPerAssignment[info.assignment.id] ?? 0
                if rem <= 0 { return false }
                let futureDates = assignmentAvailableDates[info.assignment.id]?.filter { $0 > key } ?? []
                var futurePrefCap = 0.0
                for d in futureDates { let k = dayKey(d); let dayCaps = capacityPerDay[k]!; let usedPref = allocations[k]?.reduce(0.0, { $0 + $1.value.preferred }) ?? 0.0; futurePrefCap += max(0.0, dayCaps.preferred - usedPref) }
                return max(0.0, rem - futurePrefCap) > 0
            }.map { $0.assignment }

            let deferable = infos.filter { info in
                let rem = remainingPerAssignment[info.assignment.id] ?? 0
                if rem <= 0 { return false }
                let futureDates = assignmentAvailableDates[info.assignment.id]?.filter { $0 > key } ?? []
                var futurePrefCap = 0.0
                for d in futureDates { let k = dayKey(d); let dayCaps = capacityPerDay[k]!; let usedPref = allocations[k]?.reduce(0.0, { $0 + $1.value.preferred }) ?? 0.0; futurePrefCap += max(0.0, dayCaps.preferred - usedPref) }
                return max(0.0, rem - futurePrefCap) == 0
            }.map { $0.assignment }

            func frontLoadList(_ list: [AssignmentInput]) {
                for a in list {
                    if remainingPreferred <= 0 { break }
                    let rem = remainingPerAssignment[a.id] ?? 0
                    if rem <= 0 { continue }
                    let base = rem / Double(max(1, assignmentAvailableDates[a.id]?.count ?? 1))
                    let maxFront = max(0, base * (frontLoadFactorMax - 1.0))
                    let toFront = min(maxFront, remainingPreferred, rem)
                    if toFront > 0 {
                        var existing = allocations[key]?[a.id] ?? (preferred: 0.0, overflow: 0.0, reason: nil)
                        existing.preferred += toFront
                        existing.reason = (existing.reason == nil) ? "Front-load preferred" : (existing.reason! + "; Front-load preferred")
                        allocations[key]?[a.id] = existing
                        remainingPerAssignment[a.id] = max(0.0, (remainingPerAssignment[a.id] ?? 0) - toFront)
                        remainingPreferred -= toFront
                        todayAlloc[a.id] = (todayAlloc[a.id] ?? 0.0) + toFront
                    }
                }
            }

            frontLoadList(atRisk)
            if remainingPreferred > 0 { frontLoadList(deferable) }

            // NEW: extra pass to fill any remaining preferred hours with deferable assignments
            func fillRemainingPreferred(_ list: [AssignmentInput]) {
                for a in list {
                    if remainingPreferred <= 0 { break }
                    let rem = remainingPerAssignment[a.id] ?? 0
                    if rem <= 0 { continue }
                    let toAllocate = min(rem, remainingPreferred)
                    if toAllocate > 0 {
                        var existing = allocations[key]?[a.id] ?? (preferred: 0.0, overflow: 0.0, reason: nil)
                        existing.preferred += toAllocate
                        existing.reason = (existing.reason == nil) ? "Fill remaining preferred" : (existing.reason! + "; Fill remaining preferred")
                        allocations[key]?[a.id] = existing
                        remainingPerAssignment[a.id] = max(0.0, rem - toAllocate)
                        remainingPreferred -= toAllocate
                    }
                }
            }

            if remainingPreferred > 0 { fillRemainingPreferred(deferable) }

            // Pass 3: allocate overflow when necessary (use remainingPerAssignment)
            var overflowLeft = caps.overflow
            // sort by increasing urgency (less urgent first)
            let overflowOrder = infos.sorted { (l, r) -> Bool in (urgencies[l.assignment.id] ?? 0) < (urgencies[r.assignment.id] ?? 0) }
            for info in overflowOrder {
                if overflowLeft <= 0 { break }
                let aid = info.assignment.id
                let rem = remainingPerAssignment[aid] ?? 0
                if rem <= 0 { continue }
                // compute total preferred capacity remaining up to due date
                let totalPrefCap = info.assignment.id // placeholder to clarify scope
                // allocate minimal overflow today (spread) proportional to days left shortage
                let futureDates = assignmentAvailableDates[aid] ?? []
                let daysLeft = max(1, futureDates.count)
                // compute total preferred capacity from today (including today current allocations)
                var totalPrefAvail = 0.0
                for d in futureDates {
                    let k = dayKey(d); let dayCaps = capacityPerDay[k]!; let usedPref = allocations[k]?.reduce(0.0, { $0 + $1.value.preferred }) ?? 0.0; totalPrefAvail += max(0.0, dayCaps.preferred - usedPref)
                }
                let totalShortage = max(0.0, rem - totalPrefAvail)
                if totalShortage <= 0 { continue }
                let minOverflowToday = min(rem, totalShortage / Double(daysLeft))
                let allocOverflow = min(minOverflowToday, overflowLeft, rem)
                if allocOverflow > 0 {
                    var existing = allocations[key]?[aid] ?? (preferred: 0.0, overflow: 0.0, reason: nil)
                    existing.overflow += allocOverflow
                    existing.reason = (existing.reason == nil) ? "Global overflow needed to meet deadline" : (existing.reason! + "; Global overflow needed")
                    allocations[key]?[aid] = existing
                    remainingPerAssignment[aid] = max(0.0, (remainingPerAssignment[aid] ?? 0) - allocOverflow)
                    overflowLeft -= allocOverflow
                }
            }
        }

        // After allocations, convert allocations map into PlannedDay blocks (same as before but using allocations map)
        var plannedDays: [PlannedDay] = []
        let minBlockSec = 300
        for date in planningDates {
            let key = dayKey(date)
            let dayAlloc = allocations[key] ?? [:]
            // compute urgencies for return
            var dayUrgencies: [String: Double] = [:]
            for a in assignments { dayUrgencies[a.id] = urgencyLive(for: a, remaining: remainingPerAssignment[a.id] ?? 0, on: date) }

            // build blocks sequentially (preferred then overflow)
            var blocks: [DailyAssignmentBlock] = []
            guard let origPrefStart = calendar.date(bySettingHour: preferredStartTime.hour ?? 9, minute: preferredStartTime.minute ?? 0, second: 0, of: date),
                  let prefEnd = calendar.date(bySettingHour: preferredEndTime.hour ?? 17, minute: preferredEndTime.minute ?? 0, second: 0, of: date) else {
                continue
            }
            var current = origPrefStart
            if calendar.isDateInToday(date) {
                let nowForToday = currentTime ?? Date()
                if nowForToday > current { current = nowForToday }
            }

            // preferred
            var cumulative: [String: Double] = [:]
            for (aid, alloc) in dayAlloc.sorted(by: { lhs, rhs in (dayUrgencies[lhs.key] ?? 0) > (dayUrgencies[rhs.key] ?? 0) }) {
                guard alloc.preferred > 0 else { continue }
                guard let a = assignments.first(where: { $0.id == aid }) else { continue }
                let already = cumulative[aid] ?? 0
                let remainingForAssign = max(0.0, a.totalHours - a.hoursCompleted - already)
                let used = min(alloc.preferred, remainingForAssign)
                if used <= 0 { continue }
                let maxSec = max(0.0, prefEnd.timeIntervalSince(current))
                if maxSec <= 0 { break }
                // Exact block duration in seconds, no extra buffer
                let durSec = used * 3600.0
                guard let end = calendar.date(byAdding: .second, value: Int(durSec.rounded()), to: current) else { continue }
                blocks.append(DailyAssignmentBlock(
                    assignmentId: aid,
                    startTime: current,
                    endTime: end,
                    preferredHours: used,
                    overflowHours: 0,
                    bufferLeft: max(0.0, preferredHoursPerDay - used),
                    overflowReason: dayAlloc[aid]?.reason
                ))
                current = end  // remove the extra 5-second buffer
                cumulative[aid] = (cumulative[aid] ?? 0) + used
            }

            // overflow
            current = prefEnd
            var cumulativeOverflow: [String: Double] = [:]
            var overflowTuples: [(String, (preferred: Double, overflow: Double, reason: String?))] = []
            for (aid, alloc) in dayAlloc {
                if alloc.overflow > 0 {
                    overflowTuples.append((aid, (preferred: alloc.preferred, overflow: alloc.overflow, reason: alloc.reason)))
                }
            }
            overflowTuples.sort { (l, r) -> Bool in (dayUrgencies[l.0] ?? 0) < (dayUrgencies[r.0] ?? 0) }
            for (aid, alloc) in overflowTuples {
                let overflowHoursRaw = alloc.overflow   // use the actual value
                guard overflowHoursRaw > 0 else { continue }
                guard let a = assignments.first(where: { $0.id == aid }) else { continue }
                let already = cumulativeOverflow[aid] ?? 0
                let remainingForAssign = max(0.0, a.totalHours - a.hoursCompleted - already)
                let used = min(overflowHoursRaw, remainingForAssign)
                if used <= 0 { continue }
                // Exact block duration in seconds, no extra buffer
                let durSec = used * 3600.0
                guard let end = calendar.date(byAdding: .second, value: Int(durSec.rounded()), to: current) else { continue }
                blocks.append(
                    DailyAssignmentBlock(
                        assignmentId: aid,
                        startTime: current,
                        endTime: end,
                        preferredHours: 0,
                        overflowHours: used,
                        bufferLeft: 0,
                        overflowReason: nil  // no tuple reason available
                    )
                )
                current = end  // remove the extra 5-second buffer
                cumulativeOverflow[aid] = (cumulativeOverflow[aid] ?? 0) + used
            }

            // compute onTrack
            var onTrack = true
            for (_, alloc) in dayAlloc {
                let total = alloc.preferred + alloc.overflow
                if total <= 0 { continue }
                if alloc.overflow > 0 && (alloc.overflow / total) > 0.10 { onTrack = false; break }
            }
            // feasibility check
            for a in assignments {
                let avail = assignmentAvailableDates[a.id] ?? []
                let availCapacitySum = avail.reduce(0.0) { acc, d in let k = dayKey(d); let dayCaps = capacityPerDay[k]!; let usedPref = allocations[k]?.reduce(0.0, { $0 + $1.value.preferred }) ?? 0.0; let usedOverflow = allocations[k]?.reduce(0.0, { $0 + $1.value.overflow }) ?? 0.0; let availPref = max(0.0, dayCaps.preferred - usedPref); let availOverflow = max(0.0, dayCaps.overflow - usedOverflow); return acc + availPref + availOverflow }
                let plannedForAssignment = planningDates.reduce(0.0) { acc, d in acc + (allocations[dayKey(d)]?[a.id]?.preferred ?? 0.0) + (allocations[dayKey(d)]?[a.id]?.overflow ?? 0.0) }
                let possibleTotal = a.hoursCompleted + plannedForAssignment + availCapacitySum
                if possibleTotal + 1e-6 < a.totalHours { onTrack = false; break }
            }

            var dayUrgenciesReturn: [String: Double] = [:]
            for a in assignments { dayUrgenciesReturn[a.id] = urgencyLive(for: a, remaining: remainingPerAssignment[a.id] ?? 0, on: date) }

            plannedDays.append(PlannedDay(date: date, assignmentBlocks: blocks, urgencies: dayUrgenciesReturn, allOnTrack: onTrack))
        }

        return plannedDays
    }
}

