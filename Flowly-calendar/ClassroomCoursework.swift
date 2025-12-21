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

        // For assignments without due dates, use a placeholder date (won't be used for sorting/grouping)
        let assignmentDueDate = due ?? Date.distantFuture

        return Assignment(
            title: title,
            dueDate: assignmentDueDate,
            classroom: courseName,
            description: description ?? "",
            courseId: courseId,
            isCompleted: false,
            hasRealDueDate: hasRealDue
        )
    }

    private static func composeDate(_ d: DueDate?, dueTime: DueTime?) -> Date? {
        guard let d else { return nil }
        
        // IMPORTANT: Google Classroom API returns dates in UTC timezone
        // We need to create the date in UTC first, then it will be correctly converted
        
        var utcComps = DateComponents()
        utcComps.year = d.year
        utcComps.month = d.month
        utcComps.day = d.day
        utcComps.hour = dueTime?.hours ?? 23
        utcComps.minute = dueTime?.minutes ?? 59
        utcComps.second = dueTime?.seconds ?? 0
        utcComps.timeZone = TimeZone(identifier: "UTC")  // Explicitly set to UTC
        
        // Create UTC calendar to build the date
        var utcCalendar = Calendar.current
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        
        // Create the date in UTC
        guard let utcDate = utcCalendar.date(from: utcComps) else { return nil }
        
        // Return the UTC date - Swift Date objects store UTC internally
        // When displayed or compared, they'll automatically convert to local timezone
        return utcDate
    }
}
