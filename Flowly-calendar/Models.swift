//
//  Models.swift
//  Flowly-calendar
//

import Foundation

struct User: Codable, Equatable {
    var googleEmail: String = ""
    var googleToken: String = ""
}

struct Assignment: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var dueDate: Date
    var classroom: String
    var description: String
    var courseId: String?
    var isCompleted: Bool = false  // Whether the assignment has been turned in
    var hasRealDueDate: Bool = true  // Whether this assignment has an actual due date from Google Classroom
    /// Migrated to AI estimated importance (1-5 scale, default 3)
    var aiEstimatedImportance: Int = 3
    /// Migrated to AI estimated time in minutes (default 30)
    var aiEstimatedTime: Int = 30
    var minutesCompleted: Int = 0
}

struct ScheduleItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var assignmentId: UUID
    var startTime: Date
    var endTime: Date
    var title: String
}

struct GoogleClassroom: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var isSelected: Bool = false
}
