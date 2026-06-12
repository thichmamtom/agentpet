import Foundation

/// Reads subscription limits straight from the providers — no helper app
/// needed. Claude: the OAuth token Claude Code keeps in the Keychain (or
/// `~/.claude/.credentials.json`) against `api.anthropic.com/api/oauth/usage`.
/// Codex: `~/.codex/auth.json` against the ChatGPT wham usage endpoint.
/// Read-only: tokens are never written back or refreshed; a stale token just
/// means the provider drops out until its CLI runs again.
@MainActor
final class NativeUsageProbe: ObservableObject {
    static let shared = NativeUsageProbe()

    @Published private(set) var providers: [OpenUsageClient.Provider] = []

    private var timer: Timer?
    private static let pollInterval: TimeInterval = 300

    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
    }

    /// True when some subscription is nearly exhausted.
    var limitLow: Bool {
        providers.compactMap(\.fractionLeft).contains { $0 < 0.15 }
    }

    /// Native probes first; OpenUsage (when running) fills in the providers we
    /// don't probe ourselves.
    static func combined() -> [OpenUsageClient.Provider] {
        let native = shared.providers
        let nativeIDs = Set(native.map(\.id))
        return native + OpenUsageClient.shared.providers.filter { !nativeIDs.contains($0.id) }
    }

    func poll() {
        Task.detached(priority: .utility) {
            var found: [OpenUsageClient.Provider] = []
            if let claude = await Self.probeClaude() { found.append(claude) }
            if let codex = await Self.probeCodex() { found.append(codex) }
            let result = found
            await MainActor.run { [weak self] in self?.providers = result }
        }
    }

    // MARK: - Claude (api.anthropic.com/api/oauth/usage)

    nonisolated private static func probeClaude() async -> OpenUsageClient.Provider? {
        guard let token = claudeAccessToken() else { return nil }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.69", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // Windows are {"utilization": <percent used>, "resets_at": …}.
        var fractions: [Double] = []
        for key in ["five_hour", "seven_day"] {
            if let window = json[key] as? [String: Any],
               let used = window["utilization"] as? Double {
                fractions.append(max(0, min(1, (100 - used) / 100)))
            }
        }
        guard !fractions.isEmpty else { return nil }
        return OpenUsageClient.Provider(
            id: "claude",
            displayName: "Claude",
            plan: nil,
            fractionLeft: fractions.min(),
            todayLabel: nil
        )
    }

    /// Claude Code's OAuth access token: Keychain first (current versions),
    /// then the legacy credentials file.
    nonisolated private static func claudeAccessToken() -> String? {
        if let text = keychainPassword(service: "Claude Code-credentials"),
           let token = parseClaudeCredentials(text) {
            return token
        }
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json").path
        if let text = try? String(contentsOfFile: path, encoding: .utf8),
           let token = parseClaudeCredentials(text) {
            return token
        }
        return nil
    }

    nonisolated private static func parseClaudeCredentials(_ raw: String) -> String? {
        let text = decodeHexIfNeeded(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        return token
    }

    // MARK: - Codex (chatgpt.com/backend-api/wham/usage)

    nonisolated private static func probeCodex() async -> OpenUsageClient.Provider? {
        guard let auth = codexAuth() else { return nil }
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.timeoutInterval = 8
        request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AgentPet", forHTTPHeaderField: "User-Agent")
        if let account = auth.accountId {
            request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return nil }

        // used-percent comes in response headers; the body's rate_limit
        // windows are the fallback.
        var fractions: [Double] = []
        for header in ["x-codex-primary-used-percent", "x-codex-secondary-used-percent"] {
            if let raw = http.value(forHTTPHeaderField: header), let used = Double(raw) {
                fractions.append(max(0, min(1, (100 - used) / 100)))
            }
        }
        if fractions.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let rateLimit = json["rate_limit"] as? [String: Any] {
            for key in ["primary_window", "secondary_window"] {
                if let window = rateLimit[key] as? [String: Any],
                   let used = window["used_percent"] as? Double {
                    fractions.append(max(0, min(1, (100 - used) / 100)))
                }
            }
        }
        guard !fractions.isEmpty else { return nil }
        return OpenUsageClient.Provider(
            id: "codex",
            displayName: "Codex",
            plan: nil,
            fractionLeft: fractions.min(),
            todayLabel: nil
        )
    }

    nonisolated private static func codexAuth() -> (token: String, accountId: String?)? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".codex/auth.json").path,
            home.appendingPathComponent(".config/codex/auth.json").path,
        ]
        var text: String?
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            text = try? String(contentsOfFile: path, encoding: .utf8)
            if text != nil { break }
        }
        if text == nil { text = keychainPassword(service: "Codex Auth") }
        guard let text,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String, !access.isEmpty
        else { return nil }
        return (access, tokens["account_id"] as? String)
    }

    // MARK: - Helpers

    /// `security find-generic-password -w` for the current user.
    nonisolated private static func keychainPassword(service: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["find-generic-password", "-s", service, "-w"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !out.isEmpty else { return nil }
        return out
    }

    /// `security … -w` hex-encodes values that contain newlines; JSON payloads
    /// then arrive as one long hex string.
    nonisolated private static func decodeHexIfNeeded(_ text: String) -> String {
        guard !text.hasPrefix("{"), text.count % 2 == 0, text.count > 2,
              text.allSatisfy({ $0.isHexDigit }) else { return text }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return text }
            bytes.append(byte)
            index = next
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
