import Foundation
import ServiceManagement

/// Main-app login item via the native SMAppService API (macOS 13+).
/// The system owns the source of truth; this wrapper only toggles and
/// republishes the observed status.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled: Bool

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration can fail in sandboxed/undetermined contexts; the
            // status re-read below remains authoritative either way.
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
