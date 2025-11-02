// AssignmentSync.swift
import Foundation

enum AssignmentSync {
    static func fetchForSelectedClasses(token: String, classes: [GoogleClassroom]) async throws -> [Assignment] {
        let targets = classes.filter { $0.isSelected }
        guard !targets.isEmpty else { return [] }

        var all: [Assignment] = []

        for g in targets {
            let cw = try await ClassroomCourseworkAPI.listAllCoursework(accessToken: token, courseId: g.id)

            // Filter for active assignments
            let active = cw.filter { coursework in
                guard (coursework.state ?? "PUBLISHED") == "PUBLISHED" else { return false }
                let workType = coursework.workType ?? "ASSIGNMENT"
                guard workType == "ASSIGNMENT" else { return false }
                return true
            }

            // Map and fetch completion status
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
                                courseWorkId: c.id
                            )
                            
                            // Check if there's a submission that's been turned in
                            let isCompleted = submissions.contains { submission in
                                submission.state == "TURNED_IN"
                            }
                            
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
}