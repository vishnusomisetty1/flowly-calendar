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
    var durationMinutes: Int? = nil  // Time needed to complete the task (in minutes), entered by user
    var points: Int? = nil  // Points the assignment is worth, entered by user (for importance)
}

struct ScheduleItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var assignmentId: UUID
    var startTime: Date
    var endTime: Date
    var title: String
    var durationMinutes: Int
}

struct GoogleClassroom: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var isSelected: Bool = false
}
