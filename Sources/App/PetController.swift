import Foundation
import AgentPetCore

/// Resolves the aggregate session mood for the pet and plays a short
/// `celebrate` burst when work just finished. Also owns the selected pet kind.
@MainActor
final class PetController: ObservableObject {
    static let shared = PetController()

    @Published private(set) var mood: PetMood = .idle
    @Published var kind: PetKind {
        didSet { UserDefaults.standard.set(kind.rawValue, forKey: Self.kindKey) }
    }

    private var lastResolved: PetMood = .idle
    private var latestSessions: [AgentSession] = []
    private var celebrateTimer: Timer?

    private static let kindKey = "agentpet.petKind"
    private static let celebrateDuration: TimeInterval = 3

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.kindKey)
        kind = saved.flatMap(PetKind.init(rawValue:)) ?? .blob
    }

    func start() {}

    /// Called by the daemon whenever the session list changes.
    func update(sessions: [AgentSession]) {
        latestSessions = sessions
        let resolved = MoodResolver.aggregate(sessions)
        defer { lastResolved = resolved }

        if resolved == .done && lastResolved != .done {
            mood = .celebrate
            celebrateTimer?.invalidate()
            celebrateTimer = Timer.scheduledTimer(withTimeInterval: Self.celebrateDuration, repeats: false) { _ in
                Task { @MainActor [weak self] in self?.settleAfterCelebrate() }
            }
            return
        }
        if mood == .celebrate && resolved == .done {
            return  // let the celebration finish
        }
        celebrateTimer?.invalidate()
        mood = resolved
    }

    private func settleAfterCelebrate() {
        mood = MoodResolver.aggregate(latestSessions)
    }
}
