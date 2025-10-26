import Foundation

@MainActor
final class UserStore: ObservableObject {
    @Published var user: User { didSet { saveUser() } }
    @Published var onboardingDone: Bool {
        didSet { UserDefaults.standard.set(onboardingDone, forKey: "onboardingDone") }
    }

    private let key = "flowly.user.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let loaded = try? JSONDecoder().decode(User.self, from: data) {
            self.user = loaded
        } else {
            self.user = User()
        }
        self.onboardingDone = UserDefaults.standard.bool(forKey: "onboardingDone")
    }

    private func saveUser() {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.set(false, forKey: "onboardingDone")
        onboardingDone = false
        user = User()
    }
}
