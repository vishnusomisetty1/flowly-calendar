import Foundation

struct ScheduleGenerator {
    static func generateWeek(user: User, assignments: [Assignment], from startDate: Date = Date()) -> [ScheduleItem] {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: startDate)

        func dayWindow(on day: Date) -> (start: Date, end: Date) {
            let studyStart = cal.date(
                bySettingHour: cal.component(.hour, from: user.studyStartTime),
                minute: cal.component(.minute, from: user.studyStartTime),
                second: 0, of: day
            ) ?? day
            let sleep = cal.date(
                bySettingHour: cal.component(.hour, from: user.sleepTime),
                minute: cal.component(.minute, from: user.sleepTime),
                second: 0, of: day
            ) ?? day.addingTimeInterval(60*60*23)
            return (max(studyStart, day), max(sleep, studyStart.addingTimeInterval(60*60)))
        }

        var work = assignments.map { AIEstimator.annotate($0, user: user) }
        work.sort {
            if $0.dueDate != $1.dueDate { return $0.dueDate < $1.dueDate }
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.estimatedMinutes > $1.estimatedMinutes
        }

        var items: [ScheduleItem] = []

        // Dinner blocks
        for i in 0..<7 {
            let day = cal.date(byAdding: .day, value: i, to: startOfDay)!
            let dinnerStart = cal.date(
                bySettingHour: cal.component(.hour, from: user.dinnerTime),
                minute: cal.component(.minute, from: user.dinnerTime),
                second: 0, of: day
            )!
            let dinnerEnd = cal.date(byAdding: .minute, value: user.dinnerDuration, to: dinnerStart)!
            items.append(ScheduleItem(title: "Dinner", startTime: dinnerStart, endTime: dinnerEnd, type: "meal"))
        }

        // Optional home activity (first day)
        if !user.homeActivity.trimmingCharacters(in: .whitespaces).isEmpty {
            let day0 = startOfDay
            let start = cal.date(bySettingHour: 15, minute: 30, second: 0, of: day0) ?? day0.addingTimeInterval(60*60*15+60*30)
            let end = cal.date(byAdding: .minute, value: 30, to: start)!
            items.append(ScheduleItem(title: user.homeActivity, startTime: start, endTime: end, type: "break"))
        }

        // Fill study blocks
        for i in 0..<7 {
            let day = cal.date(byAdding: .day, value: i, to: startOfDay)!
            let (winStart, winEnd) = dayWindow(on: day)
            var cursor = winStart

            let fixedToday = items.filter { cal.isDate($0.startTime, inSameDayAs: day) }
            let fixedIntervals = fixedToday.map { ($0.startTime, $0.endTime) }.sorted { $0.0 < $1.0 }

            func advancePastClashes() {
                for (s, e) in fixedIntervals where cursor >= s && cursor < e { cursor = e }
            }
            advancePastClashes()
            let dayEnd = winEnd

            outer: while cursor < dayEnd {
                guard let idx = work.firstIndex(where: { $0.estimatedMinutes > 0 }) else { break }
                var a = work[idx]

                // Adaptive scheduling based on study strategy
                let chunk: Int
                let breakLen: Int
                var shouldAddBreak = true

                switch user.studyStrategy {
                case .pomodoro:
                    // Pomodoro: 25 min work blocks with 5 min breaks
                    chunk = 25
                    breakLen = 5
                    shouldAddBreak = true

                case .activeRecall:
                    // Active Recall: Shorter focused sessions with reflection breaks
                    chunk = min(a.estimatedMinutes >= 60 ? 40 : 30, a.estimatedMinutes)
                    breakLen = 10 // Longer breaks for reflection
                    shouldAddBreak = true

                case .spacedRepetition:
                    // Spaced Repetition: Variable length based on review interval
                    chunk = a.reviewInterval > 0 ? 20 : (a.estimatedMinutes >= 60 ? 50 : 40)
                    breakLen = 7
                    shouldAddBreak = true
                }

                var start = cursor
                var end = min(cursor.addingTimeInterval(Double(chunk) * 60), dayEnd)

                for (s, e) in fixedIntervals where start < e && end > s {
                    start = e
                    end = min(e.addingTimeInterval(Double(chunk) * 60), dayEnd)
                }
                if end <= start { break }

                // Create schedule item with strategy-specific settings
                var scheduleItem = ScheduleItem(
                    title: user.studyStrategy == .pomodoro ? "🍅 Study: \(a.title)" : "Study: \(a.title)",
                    startTime: start,
                    endTime: end,
                    type: "study",
                    associatedAssignment: a
                )

                // Add strategy-specific metadata
                if user.studyStrategy == .pomodoro {
                    scheduleItem.studySessionNumber = items.filter { cal.isDate($0.startTime, inSameDayAs: day) && !$0.isBreakTime }.count + 1
                }

                items.append(scheduleItem)

                let minutesPlaced = Int(end.timeIntervalSince(start) / 60)
                a.estimatedMinutes = max(0, a.estimatedMinutes - minutesPlaced)
                work[idx] = a

                // Add break if needed
                if shouldAddBreak {
                    cursor = end
                    advancePastClashes()

                    // Add break item
                    let breakEnd = min(cursor.addingTimeInterval(Double(breakLen) * 60), dayEnd)
                    if breakEnd > cursor {
                        items.append(ScheduleItem(
                            title: breakLen >= 10 ? "☕ Break & Reflect" : "☕ Short Break",
                            startTime: cursor,
                            endTime: breakEnd,
                            type: "break",
                            isBreakTime: true
                        ))
                        cursor = breakEnd
                    }
                } else {
                    cursor = end
                }

                advancePastClashes()

                if work.allSatisfy({ $0.estimatedMinutes == 0 }) { break outer }
                if cursor.addingTimeInterval(15*60) > dayEnd { break outer }
            }
        }

        return items.sorted { $0.startTime < $1.startTime }
    }
}
