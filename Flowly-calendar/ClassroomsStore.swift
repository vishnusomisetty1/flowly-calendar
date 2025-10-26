import Foundation

@MainActor
final class ClassroomsStore: ObservableObject {
    @Published var allClassrooms: [GoogleClassroom] = [] { didSet { saveAll() } }
    @Published var selectedIDs: Set<String> = [] { didSet { saveSelected() } }
    @Published var hasChosenOnce: Bool = false { didSet { UserDefaults.standard.set(hasChosenOnce, forKey: Keys.hasChosenOnce) } }

    private enum Keys {
        static let all = "flowly.classrooms.all.v1"
        static let sel = "flowly.classrooms.selected.v1"
        static let hasChosenOnce = "flowly.classrooms.hasChosenOnce"
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Keys.all),
           let list = try? JSONDecoder().decode([GoogleClassroom].self, from: data) {
            self.allClassrooms = list
        }
        if let data = UserDefaults.standard.data(forKey: Keys.sel),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            self.selectedIDs = Set(ids)
        }
        self.hasChosenOnce = UserDefaults.standard.bool(forKey: Keys.hasChosenOnce)
    }

    func applySelection(to courses: [GoogleClassroom]) -> [GoogleClassroom] {
        guard !selectedIDs.isEmpty else {
            return courses.map { var c = $0; c.isSelected = true; return c }
        }
        return courses.map { var c = $0; c.isSelected = selectedIDs.contains(c.id); return c }
    }

    func rememberSelection(from classes: [GoogleClassroom]) {
        selectedIDs = Set(classes.filter { $0.isSelected }.map { $0.id })
        hasChosenOnce = true
    }

    private func saveAll() {
        if let data = try? JSONEncoder().encode(allClassrooms) {
            UserDefaults.standard.set(data, forKey: Keys.all)
        }
    }

    private func saveSelected() {
        if let data = try? JSONEncoder().encode(Array(selectedIDs)) {
            UserDefaults.standard.set(data, forKey: Keys.sel)
        }
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: Keys.all)
        UserDefaults.standard.removeObject(forKey: Keys.sel)
        UserDefaults.standard.set(false, forKey: Keys.hasChosenOnce)
        allClassrooms = []
        selectedIDs = []
        hasChosenOnce = false
    }
}
