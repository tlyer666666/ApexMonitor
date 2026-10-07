import AppKit
import Combine
import Foundation

enum MenuBarDisplay: String, CaseIterable {
    case text
    case graph

    var label: String {
        switch self {
        case .text: return "文本"
        case .graph: return "迷你图"
        }
    }
}

enum AppAppearance: String, CaseIterable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// User-facing preferences persisted in UserDefaults. Views bind to the
/// published values; AppDelegate applies them (sampler interval, menu bar
/// rendering, global appearance) as they change.
@MainActor
final class AppSettings: ObservableObject {
    @Published var updateInterval: Double {
        didSet { defaults.set(updateInterval, forKey: Self.updateIntervalKey) }
    }
    @Published var menuBarDisplay: MenuBarDisplay {
        didSet { defaults.set(menuBarDisplay.rawValue, forKey: Self.menuBarDisplayKey) }
    }
    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    private let defaults: UserDefaults

    static let updateIntervalKey = "updateInterval"
    static let menuBarDisplayKey = "menuBarDisplay"
    static let appearanceKey = "appearance"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedInterval = defaults.double(forKey: Self.updateIntervalKey)
        updateInterval = [1.0, 2.0, 5.0].contains(storedInterval) ? storedInterval : 1.0
        menuBarDisplay = MenuBarDisplay(rawValue: defaults.string(forKey: Self.menuBarDisplayKey) ?? "") ?? .text
        appearance = AppAppearance(rawValue: defaults.string(forKey: Self.appearanceKey) ?? "") ?? .system
    }
}
