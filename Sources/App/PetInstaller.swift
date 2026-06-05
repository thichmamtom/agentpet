import Foundation
import AgentPetCore

/// Petdex's asset CDN added hotlink protection: requests without a Referer from
/// its own site get 403, which broke all pet downloads. We're a documented
/// Petdex interop client, so we send the expected Referer.
enum PetdexAssets {
    static func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue("https://petdex.crafter.run/", forHTTPHeaderField: "Referer")
        return r
    }
}

/// Downloads a pet pack (pet.json + spritesheet) into `~/.agentpet/pets/<slug>/`.
/// Shared by the Browse gallery and first-run onboarding.
enum PetInstaller {
    private struct PackMeta: Decodable { let id: String?; let spritesheetPath: String }

    /// Returns the installed pack's id (pet.json `id`), or nil on failure.
    @discardableResult
    static func download(slug: String, petJsonURL: URL, spritesheetURL: URL) async -> String? {
        do {
            let fm = FileManager.default
            let dir = URL(fileURLWithPath: AgentPetPaths.baseDir)
                .appendingPathComponent("pets").appendingPathComponent(slug)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)

            let (petJsonData, _) = try await URLSession.shared.data(for: PetdexAssets.request(petJsonURL))
            let meta = try JSONDecoder().decode(PackMeta.self, from: petJsonData)
            try petJsonData.write(to: dir.appendingPathComponent("pet.json"))

            let (sheetData, _) = try await URLSession.shared.data(for: PetdexAssets.request(spritesheetURL))
            try sheetData.write(to: dir.appendingPathComponent(meta.spritesheetPath))

            return meta.id ?? slug
        } catch {
            return nil
        }
    }
}

/// Installs a starter pet on the very first launch so the app isn't empty.
@MainActor
enum DefaultPetBootstrap {
    private static let triedKey = "agentpet.defaultPetTried"
    private static let manifestURL = URL(string: "https://petdex.crafter.run/api/manifest")!
    /// Preferred starter (a non-franchise original); falls back to any pet.
    private static let preferredSlug = "boba"

    struct Entry: Decodable { let slug: String; let spritesheetUrl: String; let petJsonUrl: String }
    private struct Manifest: Decodable { let pets: [Lenient<Entry>] }

    static func installIfNeeded() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: triedKey) else { return }
        guard ImagePetStore.shared.packs.isEmpty, PetController.shared.selectedPetID == nil else {
            d.set(true, forKey: triedKey)
            return
        }
        d.set(true, forKey: triedKey)   // attempt once, even if offline

        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: manifestURL),
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return }
            let pets = manifest.pets.compactMap(\.value)
            let pick = pets.first { $0.slug == preferredSlug } ?? pets.first
            guard let pick,
                  let petJsonURL = URL(string: pick.petJsonUrl),
                  let sheetURL = URL(string: pick.spritesheetUrl) else { return }

            let id = await PetInstaller.download(slug: pick.slug, petJsonURL: petJsonURL, spritesheetURL: sheetURL)
            ImagePetStore.shared.reload()
            if let id, PetController.shared.selectedPetID == nil {
                PetController.shared.selectedPetID = id
            }
        }
    }
}

/// Tolerant decode wrapper: a malformed element yields nil instead of failing.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) { value = try? T(from: decoder) }
}
