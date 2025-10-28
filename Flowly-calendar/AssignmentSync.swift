// AssignmentSync.swift
import Foundation

enum AssignmentSync {
    static func fetchForSelectedClasses(token: String, classes: [GoogleClassroom]) async throws -> [Assignment] {
        let targets = classes.filter { $0.isSelected && $0.classType == .regular }
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

            // map and (re)ensure courseId is set, and fetch completion status
            let mapped: [Assignment] = await withTaskGroup(of: Assignment.self, returning: [Assignment].self) { group in
                for c in active {
                    group.addTask {
                        var a = c.toAssignment(courseName: g.name)
                        a.courseId = g.id
                        
                        // Fetch submission status to determine if assignment is completed
                        do {
                            let submissions = try await ClassroomCourseworkAPI.getAllStudentSubmissions(
                                accessToken: token, 
                                courseId: g.id, 
                                courseWorkId: c.id ?? ""
                            )
                            
                            // Check if there's a submission that's been turned in
                            let isCompleted = submissions.contains { submission in
                                submission.state == "TURNED_IN"
                            }
                            
                            // Set completion status
                            a.isCompleted = isCompleted
                            return a
                        } catch {
                            // If we can't fetch submission status, assume not completed
                            return a
                        }
                    }
                }
                
                var results: [Assignment] = []
                for await assignment in group {
                    results.append(assignment)
                }
                return results
            }
            all.append(contentsOf: mapped)
        }
        return all
    }
    
    static func fetchRemindersForSelectedClasses(token: String, classes: [GoogleClassroom]) async throws -> [Reminder] {
        let targets = classes.filter { $0.isSelected && $0.classType == .club }
        guard !targets.isEmpty else { return [] }

        var all: [Reminder] = []

        for g in targets {
            let cw = try await ClassroomCourseworkAPI.listAllCoursework(accessToken: token, courseId: g.id)

            // For club classes, we treat all coursework as reminders
            let active = cw.filter { coursework in
                // Only include PUBLISHED coursework
                guard (coursework.state ?? "PUBLISHED") == "PUBLISHED" else { return false }
                return true
            }

            // map coursework to reminders
            let mapped: [Reminder] = active.map { c in
                var reminder = c.toReminder(courseName: g.name)
                reminder.courseId = g.id
                return reminder
            }
            all.append(contentsOf: mapped)
        }
        return all
    }
}