import Foundation
import ServiceManagement

/// Launch-at-login toggle backed by `SMAppService` (macOS 13+). Works only for
/// the bundled `AgentPet.app`; a no-op when run as a bare binary.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Ignore: typically fails only when not running from a bundle.
        }
    }
}
