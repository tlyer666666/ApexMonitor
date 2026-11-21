import AppKit
import Combine
import Foundation

enum MenuBarDisplay: String, CaseIterable {
    case text
    case graph

    var label: String {
        switch self {
        case .text: return L10n.tr("文本", "Text")
        case .graph: return L10n.tr("迷你图", "Mini Graph")
        }
    }
}

/// Which metric the menu bar item presents in text mode (and the mini graph
/// follows). The short badges stay fixed-width Latin abbreviations: the
/// status item has no room for localized full words.
enum MenuBarMetric: String, CaseIterable {
    case cpu
    case memory
    case disk
    case network

    var label: String {
        switch self {
        case .cpu: return L10n.tr("处理器", "CPU")
        case .memory: return L10n.tr("内存", "Memory")
        case .disk: return L10n.tr("磁盘", "Disk")
        case .network: return L10n.tr("网络", "Network")
        }
    }

    /// Text-mode badge: values render after it ("CPU 42%").
    var badge: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "MEM"
        case .disk: return "DSK"
        case .network: return "NET"
        }
    }

    /// Percent metrics share a fixed 0–100 domain; rate metrics scale to
    /// their own peak, exactly like the popover sparklines.
    var usesPercentDomain: Bool {
        self == .cpu || self == .memory
    }

    /// The snapshot field this metric reads.
    var snapshotKeyPath: KeyPath<MetricsSnapshot, Double?> {
        switch self {
        case .cpu: \.cpuPercent
        case .memory: \.memoryPercent
        case .disk: \.diskReadBytesPerSecond
        case .network: \.networkReceiveBytesPerSecond
        }
    }
}

enum AppAppearance: String, CaseIterable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: return L10n.tr("跟随系统", "Match System")
        case .light: return L10n.tr("浅色", "Light")
        case .dark: return L10n.tr("深色", "Dark")
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
/// rendering, global appearance) as they change. The UI language is fixed
/// Simplified Chinese, so historical language preferences are discarded.
@MainActor
final class AppSettings: ObservableObject {
    @Published var updateInterval: Double {
        didSet { defaults.set(updateInterval, forKey: Self.updateIntervalKey) }
    }
    @Published var menuBarDisplay: MenuBarDisplay {
        didSet { defaults.set(menuBarDisplay.rawValue, forKey: Self.menuBarDisplayKey) }
    }
    @Published var menuBarMetric: MenuBarMetric {
        didSet { defaults.set(menuBarMetric.rawValue, forKey: Self.menuBarMetricKey) }
    }
    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    private let defaults: UserDefaults

    static let updateIntervalKey = "updateInterval"
    static let menuBarDisplayKey = "menuBarDisplay"
    static let menuBarMetricKey = "menuBarMetric"
    static let appearanceKey = "appearance"
    private static let legacyAppLanguageKey = "appLanguage"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedInterval = defaults.double(forKey: Self.updateIntervalKey)
        updateInterval = [1.0, 2.0, 5.0].contains(storedInterval) ? storedInterval : 1.0
        menuBarDisplay = MenuBarDisplay(rawValue: defaults.string(forKey: Self.menuBarDisplayKey) ?? "") ?? .text
        menuBarMetric = MenuBarMetric(rawValue: defaults.string(forKey: Self.menuBarMetricKey) ?? "") ?? .cpu
        appearance = AppAppearance(rawValue: defaults.string(forKey: Self.appearanceKey) ?? "") ?? .system
        defaults.removeObject(forKey: Self.legacyAppLanguageKey)
    }
}
