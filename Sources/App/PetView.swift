import SwiftUI

/// The pet itself, rendered in the floating window: an original vector sprite
/// that reacts to the current mood.
struct PetView: View {
    @ObservedObject private var pet = PetController.shared

    var body: some View {
        PetSpriteView(kind: pet.kind, mood: pet.mood)
            .frame(width: 120, height: 120)
            .contentShape(Rectangle())
    }
}
