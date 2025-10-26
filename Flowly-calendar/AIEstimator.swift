import Foundation

enum AIEstimator {
    static func estimateMinutes(for a: Assignment, user: User) -> Int {
        var base = 45
        let text = (a.title + " " + a.description).lowercased()

        // Study-related keywords get shorter, more focused time estimates
        let studyHits = ["study", "review", "slides", "notes", "read", "practice", "quiz prep"]
        let hardHits = ["essay","draft","analysis","lab","report","project","presentation","research","annotat","proof","derivation","case study","design","prototype"]
        let mediumHits = ["worksheet","problem set","pset","quiz","reading","outline","vocab"]

        // Check if it's a study assignment
        let isStudyAssignment = studyHits.contains { text.contains($0) }

        if isStudyAssignment {
            // Study assignments get shorter, focused time blocks
            base = 30 // Start with 30 minutes for study
            base += studyHits.reduce(0) { $0 + (text.contains($1) ? 1 : 0) } * 10
        } else {
            // Regular assignments
            base += hardHits.reduce(0) { $0 + (text.contains($1) ? 1 : 0) } * 30
            base += mediumHits.reduce(0) { $0 + (text.contains($1) ? 1 : 0) } * 15
        }

        let descLen = a.description.split(separator: " ").count
        base += min(90, (descLen / 50) * 10)

        // Handle assignments without real due dates differently
        if !a.hasRealDueDate {
            // Study assignments without due dates get moderate priority
            base = min(base, 60) // Cap at 60 minutes for study materials
        } else {
            // Regular due date logic
            let daysToDue = Calendar.current.dateComponents([.day], from: Date(), to: a.dueDate).day ?? 7
            if daysToDue <= 0 { base += 45 }
            else if daysToDue <= 1 { base += 30 }
            else if daysToDue <= 3 { base += 15 }
        }

        if text.contains("ap ") || text.contains("honors") { base += 15 }

        let est = max(20, min(240, base))
        return (est + 5) / 5 * 5
    }

    static func priority(for a: Assignment) -> Int {
        let text = (a.title + " " + a.description).lowercased()
        let isStudyAssignment = ["study", "review", "slides", "notes", "read", "practice"].contains { text.contains($0) }

        if !a.hasRealDueDate && isStudyAssignment {
            // Study materials without due dates get lower priority
            return 3
        }

        let daysToDue = Calendar.current.dateComponents([.day], from: Date(), to: a.dueDate).day ?? 7
        let est = estimateMinutes(for: a, user: User())
        if daysToDue <= 1 || est >= 120 { return 1 }
        if daysToDue <= 3 || est >= 60  { return 2 }
        return 3
    }

    static func annotate(_ a: Assignment, user: User) -> Assignment {
        var b = a
        b.estimatedMinutes = estimateMinutes(for: a, user: user)
        b.priority = priority(for: a)
        return b
    }
}
