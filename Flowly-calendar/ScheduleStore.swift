import Foundation

@MainActor
final class ScheduleStore: ObservableObject {
    @Published var items: [ScheduleItem] = [] {
        didSet { save() }
    }

    private var keyPrefix = "flowly.schedule."
    private var accountKey: String = "local"

    func load(for account: String) {
        accountKey = account
        let key = keyPrefix + accountKey + ".v1"
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([ScheduleItem].self, from: data) {
            items = list
        } else {
            items = []
        }
    }

    func replace(with newItems: [ScheduleItem]) {
        items = newItems
    }

    func append(_ item: ScheduleItem) {
        items.append(item)
    }

    func reset(for account: String? = nil) {
        let key = keyPrefix + (account ?? accountKey) + ".v1"
        UserDefaults.standard.removeObject(forKey: key)
        if account == nil || account == accountKey {
            items = []
        }
    }

    func migrateLocalIfNeeded(to emailKey: String) {
        guard emailKey != "local" else { return }
        let localKey = keyPrefix + "local.v1"
        let destKey  = keyPrefix + emailKey + ".v1"
        guard UserDefaults.standard.data(forKey: destKey) == nil,
              let localData = UserDefaults.standard.data(forKey: localKey) else { return }
        UserDefaults.standard.set(localData, forKey: destKey)
        // keep local copy or clear—your call. Here we KEEP it.
    }

    private func save() {
        let key = keyPrefix + accountKey + ".v1"
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
