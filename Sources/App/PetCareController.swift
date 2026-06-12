import Foundation
import AgentPetCore

/// Owns the persistent tamagotchi state: feeds the pet when agents finish
/// sessions (meals) and when Claude turns consume tokens, persists across
/// launches, and plays a celebrate burst on level-ups.
@MainActor
final class PetCareController: ObservableObject {
    static let shared = PetCareController()

    @Published private(set) var state = PetCareState()

    private static let storageKey = "agentpet.care.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(PetCareState.self, from: data) {
            state = saved
        }
    }

    var level: Int { PetCare.level(forXP: state.xp) }
    var stageKey: String { PetCare.stageName(forLevel: level) }
    var stageIndex: Int { PetCare.stageIndex(forLevel: level) }
    /// Progress through the current level, 0…1.
    var levelProgress: Double { PetCare.progress(forXP: state.xp) }
    var hunger: PetHunger { PetCare.hunger(state: state, now: Date()) }

    /// A finished agent session — the pet's proper meal.
    func recordMeal() {
        mutate { PetCare.recordMeal(state: &$0, now: Date()) }
    }

    /// Tokens consumed by a Claude turn (transcript usage delta).
    func feedTokens(_ tokens: Int) {
        guard tokens > 0 else { return }
        mutate { PetCare.feedTokens(tokens, state: &$0, now: Date()) }
    }

    /// Rolls the daily counters over; UI refresh timers call this so "today"
    /// numbers reset at midnight even with no feeding events.
    func refreshDay() {
        mutate { PetCare.rollover(&$0, now: Date()) }
    }

    private func mutate(_ change: (inout PetCareState) -> Void) {
        let levelBefore = PetCare.level(forXP: state.xp)
        var s = state
        change(&s)
        guard s != state else { return }
        state = s
        persist()
        let levelAfter = PetCare.level(forXP: s.xp)
        if levelAfter > levelBefore {
            let line = String(
                format: NSLocalizedString("Level up! Lv %d ⭐", comment: "pet level-up celebrate line"),
                levelAfter
            )
            PetController.shared.flashCelebrate(line: line)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
