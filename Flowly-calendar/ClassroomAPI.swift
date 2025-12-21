import Foundation

struct ClassroomCourse: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let section: String?
    let courseState: String?
}

struct ClassroomCoursesResponse: Codable {
    let courses: [ClassroomCourse]?
    let nextPageToken: String?
}

enum ClassroomAPIError: LocalizedError {
    case badStatus(Int, String?)
    case decode(Error)
    case noData

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, let body):
            let snip = body?.prefix(200) ?? ""
            return "HTTP \(code)" + (snip.isEmpty ? "" : " – \(snip)")
        case .decode(let e): return "Decode failed: \(e.localizedDescription)"
        case .noData: return "No HTTP response"
        }
    }
}

enum ClassroomAPI {
    static func listCourses(accessToken: String, student: Bool = true, pageToken: String? = nil) async throws -> ClassroomCoursesResponse {
        var comps = URLComponents(string: "https://classroom.googleapis.com/v1/courses")!
        var q: [URLQueryItem] = [
            URLQueryItem(name: "courseStates", value: "ACTIVE"),
            URLQueryItem(name: student ? "studentId" : "teacherId", value: "me"),
            URLQueryItem(name: "pageSize", value: "100")
        ]
        if let pageToken { q.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        comps.queryItems = q

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ClassroomAPIError.noData }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw ClassroomAPIError.badStatus(http.statusCode, body)
        }
        do { return try JSONDecoder().decode(ClassroomCoursesResponse.self, from: data) }
        catch { throw ClassroomAPIError.decode(error) }
    }

    static func listAllMyCourses(accessToken: String) async throws -> [ClassroomCourse] {
        var all: [String: ClassroomCourse] = [:]
        for isStudent in [true, false] {
            var token: String? = nil
            repeat {
                let res = try await listCourses(accessToken: accessToken, student: isStudent, pageToken: token)
                res.courses?.forEach { all[$0.id] = $0 }
                token = res.nextPageToken
            } while token != nil
        }
        return all.values
            .filter { ($0.courseState ?? "ACTIVE") == "ACTIVE" }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
