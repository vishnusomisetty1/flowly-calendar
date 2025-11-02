import Foundation

struct ScheduleGenerator {
    static let minimumTimeBlockMinutes = 15
    
    static func generateSchedule(
        assignments: [Assignment],
        startDate: Date,
        days: Int = 30
    ) -> [ScheduleItem] {
        let calendar = Calendar.current
        let endDate = calendar.date(byAdding: .day, value: days, to: startDate) ?? startDate
        
        // Filter to incomplete assignments with due dates within the period
        let now = Date()
        let eligibleAssignments = assignments.filter { assignment in
            guard !assignment.isCompleted,
                  assignment.hasRealDueDate,
                  assignment.dueDate <= endDate,
                  assignment.dueDate >= startDate else { return false }
            return true
        }
        
        guard !eligibleAssignments.isEmpty else { return [] }
        
        // Calculate priority score for each assignment
        let assignmentsWithPriority = eligibleAssignments.map { assignment -> (Assignment, Double) in
            let priority = calculatePriority(assignment: assignment, currentDate: now, endDate: endDate)
            return (assignment, priority)
        }.sorted { $0.1 > $1.1 } // Sort by priority (highest first)
        
        var scheduleItems: [ScheduleItem] = []
        var dayWorkLoad: [Date: Int] = [:] // Track minutes scheduled per day
        
        // Distribute work across available days
        for (assignment, _) in assignmentsWithPriority {
            let totalDuration = assignment.durationMinutes ?? 45 // Default to 45 minutes if not set
            let daysRemaining = calendar.dateComponents([.day], from: now, to: assignment.dueDate).day ?? 1
            
            // If total time is less than minimum block, schedule it all closer to due date
            if totalDuration < minimumTimeBlockMinutes {
                scheduleItemCloseToDueDate(
                    assignment: assignment,
                    totalDuration: totalDuration,
                    daysRemaining: daysRemaining,
                    currentDate: now,
                    endDate: endDate,
                    calendar: calendar,
                    scheduleItems: &scheduleItems,
                    dayWorkLoad: &dayWorkLoad
                )
            } else {
                // Distribute evenly across available days
                let blocks = distributeWorkEvenly(
                    assignment: assignment,
                    totalDuration: totalDuration,
                    daysRemaining: max(daysRemaining, 1),
                    startDate: startDate,
                    endDate: min(endDate, assignment.dueDate),
                    calendar: calendar,
                    dayWorkLoad: &dayWorkLoad
                )
                scheduleItems.append(contentsOf: blocks)
            }
        }
        
        return scheduleItems.sorted { $0.startTime < $1.startTime }
    }
    
    private static func calculatePriority(assignment: Assignment, currentDate: Date, endDate: Date) -> Double {
        let calendar = Calendar.current
        let daysRemaining = max(1, calendar.dateComponents([.day], from: currentDate, to: assignment.dueDate).day ?? 1)
        
        // Importance: based on points (higher points = more important)
        // Default to medium importance if no points
        let importance = Double(assignment.points ?? 50) / 100.0 // Normalize to 0-1 scale
        
        // Urgency: based on days remaining (fewer days = more urgent)
        let totalDays = max(1, calendar.dateComponents([.day], from: currentDate, to: endDate).day ?? 30)
        let urgency = 1.0 - (Double(daysRemaining) / Double(totalDays))
        
        // Combined priority: 60% importance, 40% urgency
        let priority = (importance * 0.6) + (urgency * 0.4)
        
        return priority
    }
    
    private static func distributeWorkEvenly(
        assignment: Assignment,
        totalDuration: Int,
        daysRemaining: Int,
        startDate: Date,
        endDate: Date,
        calendar: Calendar,
        dayWorkLoad: inout [Date: Int]
    ) -> [ScheduleItem] {
        var items: [ScheduleItem] = []
        
        let now = Date()
        let effectiveStartDate = max(startDate, now)
        let effectiveEndDate = min(endDate, assignment.dueDate)
        
        // Calculate available days
        guard let daysDiff = calendar.dateComponents([.day], from: effectiveStartDate, to: effectiveEndDate).day,
              daysDiff > 0 else {
            // If no days available, schedule all at once close to due date
            scheduleSingleBlock(
                assignment: assignment,
                duration: totalDuration,
                targetDate: assignment.dueDate,
                calendar: calendar,
                scheduleItems: &items,
                dayWorkLoad: &dayWorkLoad
            )
            return items
        }
        
        // Calculate how many blocks we need (minimum 15 minutes each)
        let numBlocks = max(1, min(daysDiff, totalDuration / minimumTimeBlockMinutes))
        let actualBlockSize = max(minimumTimeBlockMinutes, totalDuration / numBlocks)
        let remainder = totalDuration - (actualBlockSize * numBlocks)
        
        // Distribute blocks evenly across available days
        let dayInterval = max(1, daysDiff / numBlocks)
        var scheduledBlocks = 0
        var currentDay = effectiveStartDate
        
        while scheduledBlocks < numBlocks && currentDay <= effectiveEndDate {
            let dayStart = calendar.startOfDay(for: currentDay)
            
            // Add remainder to last block
            let blockDuration = (scheduledBlocks == numBlocks - 1) ? actualBlockSize + remainder : actualBlockSize
            
            // Try to find an available time slot
            let preferredTimes = [9, 14, 19] // 9 AM, 2 PM, 7 PM
            var scheduled = false
            
            for hour in preferredTimes {
                var comps = calendar.dateComponents([.year, .month, .day], from: dayStart)
                comps.hour = hour
                comps.minute = 0
                
                if let timeSlot = calendar.date(from: comps), timeSlot >= now {
                    let endTime = calendar.date(byAdding: .minute, value: blockDuration, to: timeSlot) ?? timeSlot
                    
                    items.append(ScheduleItem(
                        assignmentId: assignment.id,
                        startTime: timeSlot,
                        endTime: endTime,
                        title: assignment.title,
                        durationMinutes: blockDuration
                    ))
                    
                    dayWorkLoad[dayStart] = (dayWorkLoad[dayStart] ?? 0) + blockDuration
                    scheduled = true
                    scheduledBlocks += 1
                    break
                }
            }
            
            // Move to next scheduled day
            if scheduled, let nextDay = calendar.date(byAdding: .day, value: dayInterval, to: currentDay) {
                currentDay = nextDay
            } else if let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDay) {
                currentDay = nextDay
            } else {
                break
            }
        }
        
        // If we didn't schedule all blocks, schedule remainder close to due date
        if scheduledBlocks < numBlocks {
            let remainingDuration = totalDuration - items.reduce(0) { $0 + $1.durationMinutes }
            if remainingDuration > 0 {
                scheduleSingleBlock(
                    assignment: assignment,
                    duration: remainingDuration,
                    targetDate: assignment.dueDate,
                    calendar: calendar,
                    scheduleItems: &items,
                    dayWorkLoad: &dayWorkLoad
                )
            }
        }
        
        return items
    }
    
    private static func scheduleItemCloseToDueDate(
        assignment: Assignment,
        totalDuration: Int,
        daysRemaining: Int,
        currentDate: Date,
        endDate: Date,
        calendar: Calendar,
        scheduleItems: inout [ScheduleItem],
        dayWorkLoad: inout [Date: Int]
    ) {
        // Schedule within last 2 days before due date (or day before if only 1 day remains)
        let daysBeforeDue = min(2, max(1, daysRemaining))
        guard let targetDate = calendar.date(byAdding: .day, value: -daysBeforeDue, to: assignment.dueDate),
              targetDate >= currentDate,
              targetDate <= endDate else {
            // If can't schedule before due date, schedule as early as possible
            if let earliest = calendar.date(byAdding: .day, value: 1, to: currentDate),
               earliest <= assignment.dueDate {
                scheduleSingleBlock(
                    assignment: assignment,
                    duration: totalDuration,
                    targetDate: earliest,
                    calendar: calendar,
                    scheduleItems: &scheduleItems,
                    dayWorkLoad: &dayWorkLoad
                )
            }
            return
        }
        
        scheduleSingleBlock(
            assignment: assignment,
            duration: totalDuration,
            targetDate: targetDate,
            calendar: calendar,
            scheduleItems: &scheduleItems,
            dayWorkLoad: &dayWorkLoad
        )
    }
    
    private static func scheduleSingleBlock(
        assignment: Assignment,
        duration: Int,
        targetDate: Date,
        calendar: Calendar,
        scheduleItems: inout [ScheduleItem],
        dayWorkLoad: inout [Date: Int]
    ) {
        let dayStart = calendar.startOfDay(for: targetDate)
        let existingWork = dayWorkLoad[dayStart] ?? 0
        
        // Try preferred times
        let preferredTimes = [9, 14, 19]
        
        for hour in preferredTimes {
            var comps = calendar.dateComponents([.year, .month, .day], from: dayStart)
            comps.hour = hour
            comps.minute = 0
            
            if let timeSlot = calendar.date(from: comps), timeSlot >= Date() {
                let endTime = calendar.date(byAdding: .minute, value: duration, to: timeSlot) ?? timeSlot
                
                scheduleItems.append(ScheduleItem(
                    assignmentId: assignment.id,
                    startTime: timeSlot,
                    endTime: endTime,
                    title: assignment.title,
                    durationMinutes: duration
                ))
                
                dayWorkLoad[dayStart] = existingWork + duration
                return
            }
        }
        
        // If preferred times don't work, use 2 PM as default
        var comps = calendar.dateComponents([.year, .month, .day], from: dayStart)
        comps.hour = 14
        comps.minute = 0
        
        if let timeSlot = calendar.date(from: comps), timeSlot >= Date() {
            let endTime = calendar.date(byAdding: .minute, value: duration, to: timeSlot) ?? timeSlot
            
            scheduleItems.append(ScheduleItem(
                assignmentId: assignment.id,
                startTime: timeSlot,
                endTime: endTime,
                title: assignment.title,
                durationMinutes: duration
            ))
            
            dayWorkLoad[dayStart] = existingWork + duration
        }
    }
}

