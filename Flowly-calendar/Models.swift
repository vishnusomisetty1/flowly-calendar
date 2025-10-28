//
//  Models.swift
//  Flowly-calendar
//
//  Created by Vishnu Somisetty on 10/23/25.
//

import Foundation

enum StudyStrategy: String, Codable, Equatable {
    case activeRecall = "active_recall"
    case spacedRepetition = "spaced_repetition"
    case pomodoro = "pomodoro"

    var displayName: String {
        switch self {
        case .activeRecall: return "Active Recall"
        case .spacedRepetition: return "Spaced Repetition"
        case .pomodoro: return "Pomodoro Technique"
        }
    }

    var description: String {
        switch self {
        case .activeRecall:
            return "Test yourself by recalling information from memory. Perfect for strengthening long-term retention."
        case .spacedRepetition:
            return "Review material at increasing intervals (1 day → 3 days → 7 days). Maximizes memory efficiency."
        case .pomodoro:
            return "Focus in 25-30 minute bursts with short breaks. Perfect for sustained concentration."
        }
    }

    var icon: String {
        switch self {
        case .activeRecall: return "brain.head.profile"
        case .spacedRepetition: return "repeat"
        case .pomodoro: return "timer"
        }
    }
}

struct User: Codable, Equatable {
    var homeActivity: String = ""
    var studyStartTime: Date = Date()
    var sleepTime: Date = Date()
    var dinnerTime: Date = Date()
    var dinnerDuration: Int = 30
    var googleEmail: String = ""
    var googleToken: String = ""
    var studyStrategy: StudyStrategy = .pomodoro // Default to pomodoro
}

struct ScheduleItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var startTime: Date
    var endTime: Date
    var type: String
    var isCompleted: Bool = false
    var associatedAssignment: Assignment?

    // Study strategy specific fields
    var isBreakTime: Bool = false // For pomodoro breaks
    var studySessionNumber: Int = 0 // For tracking pomodoro sessions
    var reviewInterval: Int = 0 // For spaced repetition (days until next review)
}

// Models.swift
struct Assignment: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var dueDate: Date
    var classroom: String
    var description: String
    var estimatedMinutes: Int = 45
    var priority: Int = 2

    // NEW: which Classroom course this belongs to
    var courseId: String? = nil
    // NEW: whether this assignment has a real due date (not auto-generated)
    var hasRealDueDate: Bool = true
    // NEW: for spaced repetition - days until next review
    var reviewInterval: Int = 0
    // NEW: whether this assignment has been completed/turned in
    var isCompleted: Bool = false
}

struct Reminder: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var eventDate: Date
    var classroom: String
    var description: String
    var courseId: String?
    var isCompleted: Bool = false
    
    // For club classes - these are just reminders of events, not assignments
    var reminderType: ReminderType = .event
    
    enum ReminderType: String, Codable, Equatable {
        case event = "event"
        case meeting = "meeting"
        case deadline = "deadline"
        
        var displayName: String {
            switch self {
            case .event: return "Event"
            case .meeting: return "Meeting"
            case .deadline: return "Deadline"
            }
        }
    }
}

enum ClassType: String, Codable, Equatable {
    case regular = "regular"
    case club = "club"
    
    var displayName: String {
        switch self {
        case .regular: return "Regular Class"
        case .club: return "Club Class"
        }
    }
    
    var description: String {
        switch self {
        case .regular: return "Regular academic class with assignments"
        case .club: return "Club class with reminders only (no assignments)"
        }
    }
}

struct GoogleClassroom: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var isSelected: Bool = false
    var classType: ClassType = .regular
}
