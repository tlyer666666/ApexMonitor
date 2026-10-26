import Foundation
import ServiceManagement

enum LoginItemStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
}

/// Main-app login item via the native SMAppService API (macOS 13+).
/// The system owns the source of truth; this wrapper exposes the full status
/// (including approval-pending) plus the last registration error, so the UI
/// can distinguish "off" from "waiting for approval" from "failed".
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var status: LoginItemStatus
    @Published private(set) var lastError: String?

    var isEnabled: Bool { status == .enabled }

    var label: String {
        switch status {
        case .enabled: return L10n.MenuBar.launchAtLoginOn
        case .requiresApproval: return L10n.MenuBar.launchAtLoginApproval
        case .disabled: return L10n.MenuBar.launchAtLoginOff
        }
    }

    var symbol: String {
        switch status {
        case .enabled: return "checkmark.circle.fill"
        case .requiresApproval: return "hourglass"
        case .disabled: return "powerplug"
        }
    }

    init() {
        status = Self.resolve(SMAppService.mainApp.status)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = L10n.MenuBar.launchAtLoginError
        }
        status = Self.resolve(SMAppService.mainApp.status)
    }

    /// Re-reads the system status, e.g. after the user edits login items in
    /// System Settings while this app is running.
    func refresh() {
        status = Self.resolve(SMAppService.mainApp.status)
    }

    private static func resolve(_ serviceStatus: SMAppService.Status) -> LoginItemStatus {
        switch serviceStatus {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered, .notFound: return .disabled
        @unknown default: return .disabled
        }
    }
}
