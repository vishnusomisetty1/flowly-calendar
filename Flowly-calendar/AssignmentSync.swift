// AssignmentSync.swift
import Foundation

enum AssignmentSync {
    static func fetchForSelectedClasses(token: String, classes: [GoogleClassroom]) async throws -> [Assignment] {
        let targets = classes.filter { $0.isSelected }
        guard !targets.isEmpty else { return [] }

        var all: [Assignment] = []

        for g in targets {
            let cw = try await ClassroomCourseworkAPI.listAllCoursework(accessToken: token, courseId: g.id)

            // Simple filter for active assignments
            let active = cw.filter { coursework in
                // Only include PUBLISHED assignments
                guard (coursework.state ?? "PUBLISHED") == "PUBLISHED" else { return false }

                // Only include actual assignments, not materials, videos, or other content
                let workType = coursework.workType ?? "ASSIGNMENT"
                guard workType == "ASSIGNMENT" else { return false }

                return true
            }

            // map and (re)ensure courseId is set
            let mapped: [Assignment] = active.map { c in
                var a = c.toAssignment(courseName: g.name)
                a.courseId = g.id
                return a
            }
            all.append(contentsOf: mapped)
        }
        return all
    }
}