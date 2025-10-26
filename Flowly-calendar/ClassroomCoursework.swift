import Foundation

struct ClassroomCoursework: Codable {
    let id: String
    let courseId: String
    let title: String
    let description: String?
    let dueDate: DueDate?
    let dueTime: DueTime?
    let state: String?
    let workType: String? // "ASSIGNMENT", "SHORT_ANSWER_QUESTION", "MULTIPLE_CHOICE_QUESTION", "MATERIAL", etc.

    struct DueDate: Codable { let year: Int; let month: Int; let day: Int }
    struct DueTime: Codable { let hours: Int?; let minutes: Int?; let seconds: Int?; let nanos: Int? }
}

struct ClassroomCourseworkResponse: Codable {
    let courseWork: [ClassroomCoursework]?
    let nextPageToken: String?
}

struct StudentSubmission: Codable {
    let id: String
    let courseWorkId: String
    let state: String? // "NEW", "CREATED", "TURNED_IN", "RETURNED", "RECLAIMED_BY_STUDENT"
    let submissionHistory: [SubmissionHistory]?

    struct SubmissionHistory: Codable {
        let stateHistory: [StateHistory]?

        struct StateHistory: Codable {
            let state: String?
            let stateTimestamp: String?
        }
    }
}

struct StudentSubmissionResponse: Codable {
    let studentSubmissions: [StudentSubmission]?
    let nextPageToken: String?
}

enum ClassroomCourseworkAPI {
    static func listCoursework(accessToken: String, courseId: String, pageToken: String? = nil) async throws -> ClassroomCourseworkResponse {
        var comps = URLComponents(string: "https://classroom.googleapis.com/v1/courses/\(courseId)/courseWork")!
        var q: [URLQueryItem] = [ URLQueryItem(name: "pageSize", value: "100") ]
        if let pageToken { q.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        comps.queryItems = q

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Coursework", code: -1)
        }
        return try JSONDecoder().decode(ClassroomCourseworkResponse.self, from: data)
    }

    static func listAllCoursework(accessToken: String, courseId: String) async throws -> [ClassroomCoursework] {
        var all: [ClassroomCoursework] = []
        var token: String? = nil
        repeat {
            let res = try await listCoursework(accessToken: accessToken, courseId: courseId, pageToken: token)
            all.append(contentsOf: res.courseWork ?? [])
            token = res.nextPageToken
        } while token != nil
        return all
    }

    static func listStudentSubmissions(accessToken: String, courseId: String, courseWorkId: String, pageToken: String? = nil) async throws -> StudentSubmissionResponse {
        var comps = URLComponents(string: "https://classroom.googleapis.com/v1/courses/\(courseId)/courseWork/\(courseWorkId)/studentSubmissions")!
        var q: [URLQueryItem] = [ URLQueryItem(name: "pageSize", value: "100") ]
        if let pageToken { q.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        comps.queryItems = q

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "StudentSubmissions", code: -1)
        }
        return try JSONDecoder().decode(StudentSubmissionResponse.self, from: data)
    }

    static func getAllStudentSubmissions(accessToken: String, courseId: String, courseWorkId: String) async throws -> [StudentSubmission] {
        var all: [StudentSubmission] = []
        var token: String? = nil
        repeat {
            let res = try await listStudentSubmissions(accessToken: accessToken, courseId: courseId, courseWorkId: courseWorkId, pageToken: token)
            all.append(contentsOf: res.studentSubmissions ?? [])
            token = res.nextPageToken
        } while token != nil
        return all
    }
}

extension ClassroomCoursework {
    func toAssignment(courseName: String) -> Assignment {
        let due = Self.composeDate(dueDate, dueTime: dueTime)
        let hasRealDue = due != nil

        // For assignments without due dates, set due date to 3 days from now
        // This gives students time to work on study materials
        let assignmentDueDate = due ?? Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()

        return Assignment(
            title: title,
            dueDate: assignmentDueDate,
            classroom: courseName,
            description: description ?? "",
            estimatedMinutes: 45,
            priority: 2,
            courseId: courseId,
            hasRealDueDate: hasRealDue
        )
    }

    private static func composeDate(_ d: DueDate?, dueTime: DueTime?) -> Date? {
        guard let d else { return nil }
        var comps = DateComponents()
        comps.year = d.year; comps.month = d.month; comps.day = d.day
        comps.hour = dueTime?.hours ?? 23
        comps.minute = dueTime?.minutes ?? 59
        comps.second = dueTime?.seconds ?? 0
        return Calendar.current.date(from: comps)
    }
}
