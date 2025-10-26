import Foundation

enum AccountKey {
    static func forEmail(_ email: String?) -> String {
        let e = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return e.isEmpty ? "local" : e.lowercased()
    }
}
