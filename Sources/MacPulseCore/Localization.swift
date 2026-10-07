import Foundation

/// App language selection. `system` follows the user's macOS preference.
public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case zhHans = "zh-Hans"
    case en = "en"

    public var label: String {
        switch self {
        case .system: return L10n.tr("跟随系统", "Follow System")
        case .zhHans: return "简体中文"
        case .en: return "English"
        }
    }
}

/// Bilingual string catalog. The app is Chinese-first; English exists so the
/// GitHub release is usable by international users. `override` is persisted
/// in UserDefaults by the settings window; `nil` follows the system.
public enum L10n {
    public nonisolated(unsafe) static var override: AppLanguage?

    public static var language: AppLanguage {
        if let override { return override }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("zh") ? .zhHans : .en
    }

    public static func tr(_ zh: String, _ en: String) -> String {
        language == .zhHans ? zh : en
    }

    public enum MenuBar {
        public static var appName: String { tr("MacPulse", "MacPulse") }
        public static var popoverSubtitle: String { tr("系统实时状态 · 点击分类查看详情", "Live system stats · click a row for details") }
        public static var waitingForFirstSample: String { tr("等待下一次有效采样", "Waiting for the next valid sample") }
        public static var trendSuffix: String { tr("总使用率 · 最近 5 分钟", "Total usage · last 5 minutes") }
        public static var readWrite: String { tr("读取 / 写入", "Read / Write") }
        public static var receiveSend: String { tr("接收 / 发送", "Receive / Send") }
        public static var launchAtLogin: String { tr("开机启动", "Launch at Login") }
        public static var launchAtLoginOn: String { tr("开机启动 · 已开启", "Launch at Login · On") }
        public static var launchAtLoginOff: String { tr("开机启动 · 已关闭", "Launch at Login · Off") }
        public static var enabled: String { tr("已开启", "On") }
        public static var disabled: String { tr("已关闭", "Off") }
        public static var settings: String { tr("设置…", "Settings…") }
        public static var openDashboard: String { tr("打开监控面板", "Open Dashboard") }
        public static var quit: String { tr("退出 MacPulse", "Quit MacPulse") }
    }

    public enum ContextMenu {
        public static var openDashboard: String { tr("打开主面板", "Open Main Panel") }
    }

    public enum Dashboard {
        public static var rangePicker: String { tr("时间范围", "Time Range") }
        public static func detailNavigation(_ category: String) -> String {
            tr("\(category)详情", "\(category) Details")
        }
        public static var title: String { tr("系统性能", "System Performance") }
        public static var subtitle: String { tr("MacPulse · 实时监控与历史统计", "MacPulse · Live Monitoring & History") }
        public static var updating: String { tr("每秒更新", "Updates every second") }
        public static var justUpdated: String { tr("刚刚更新", "Updated just now") }
        public static func updatedAgo(_ seconds: Int) -> String { tr("最后更新 \(seconds) 秒前", "Updated \(seconds)s ago") }
        public static var localOnlyNote: String { tr("历史数据仅保存在本机", "History stays on this Mac") }
        public static var footer: String { tr("当前范围：%@ · 历史分钟均值与本次运行明细 · 保留 7 天", "Range: %@ · minute means with live detail · 7-day retention") }
        public static var totalUsage: String { tr("总使用率", "Total usage") }
        public static var currentUsage: String { tr("当前占用", "Current usage") }
        public static var memoryDetail: String { tr("物理内存", "Physical memory") }
    }

    public enum Charts {
        public static var usage: String { tr("使用率", "Usage") }
        public static var occupancy: String { tr("占用", "Occupancy") }
        public static var average: String { tr("平均", "Avg") }
        public static var peak: String { tr("峰值", "Peak") }
        public static var peakEstimated: String { tr("峰值≈", "Peak≈") }
        public static var establishingBaseline: String { tr("正在建立基线…", "Establishing baseline…") }
    }

    public enum Details {
        public static var backToOverview: String { tr("返回总览", "Back to Overview") }
        public static var collecting: String { tr("采集中…", "Collecting…") }
        public static var memoryUsage: String { tr("内存用量", "Memory Usage") }
        public static var used: String { tr("已用", "Used") }
        public static var available: String { tr("可用", "Available") }
        public static var total: String { tr("总量", "Total") }
        public static var topProcessesByMemory: String { tr("进程占用 · Top 10（按内存）", "Top Processes · 10 by Memory") }
        public static var topProcessesByCPU: String { tr("进程占用 · Top 10（按 CPU）", "Top Processes · 10 by CPU") }
        public static var processHeader: String { tr("进程", "Process") }
        public static var memoryColumn: String { tr("内存", "Memory") }
        public static var cpuColumn: String { tr("CPU", "CPU") }
        public static func readableCount(_ count: Int) -> String {
            tr("当前权限可读 \(count) 个进程", "\(count) processes readable with current permissions")
        }
        public static var readSpeed: String { tr("读写速度", "Read / Write Speed") }
        public static var read: String { tr("读取", "Read") }
        public static var write: String { tr("写入", "Write") }
        public static var storage: String { tr("存储空间", "Storage") }
        public static var availableSpace: String { tr("可用", "Available") }
        public static var liveTraffic: String { tr("实时流量", "Live Traffic") }
        public static var receive: String { tr("接收", "Receive") }
        public static var send: String { tr("发送", "Send") }
        public static var trafficStats: String { tr("流量统计", "Traffic Statistics") }
        public static var statsWindow: String { tr("统计时段", "Window") }
        public static var coverage: String { tr("统计覆盖", "Coverage") }
        public static var coverageNote: String { tr("按有效采样时长累计；不补齐未监测时段", "Integrated over sampled time; unsampled gaps are never filled") }
        public static var receiveTotal: String { tr("接收总量", "Received") }
        public static var sendTotal: String { tr("发送总量", "Sent") }
        public static func peak(_ rate: String) -> String { tr("峰值 \(rate)", "Peak \(rate)") }
        public static func peakEstimated(_ rate: String) -> String { tr("峰值≈ \(rate)", "Peak≈ \(rate)") }
        public static var legacyNote: String { tr("旧版历史缺少有效时长，以下总量仅包含可核算的新样本；旧数据未删除。", "Legacy history lacks duration metadata; totals below only cover new-format samples. Old data is kept.") }
        public static var estimatedNote: String { tr("部分历史或边界分钟的总量、峰值为估算；未知时长不补齐。", "Totals and peaks crossing window edges are estimated; unknown durations are never filled.") }
        public static var connectionStatus: String { tr("连接状态", "Connection") }
        public static var online: String { tr("在线", "Online") }
        public static var offline: String { tr("离线", "Offline") }
        public static var interfaceDetails: String { tr("接口明细", "Interfaces") }
        public static var connected: String { tr("已连接", "Connected") }
        public static var disconnected: String { tr("未连接", "Disconnected") }
        public static var cpuBreakdown: String { tr("处理器分解", "CPU Breakdown") }
        public static var user: String { tr("用户", "User") }
        public static var system: String { tr("系统", "System") }
        public static var nice: String { tr("友好", "Nice") }
        public static var idle: String { tr("空闲", "Idle") }
        public static var loadAverage: String { tr("负载均值", "Load Average") }
        public static func minutes(_ n: Int) -> String { tr("\(n) 分钟", "\(n) min") }
        public static var singleCoreNote: String { tr("CPU% 以单核 100% 为基准", "CPU% is normalized to one core = 100%") }
    }

    public enum Settings {
        public static var windowTitle: String { tr("MacPulse 设置", "MacPulse Settings") }
        public static var sampling: String { tr("采样", "Sampling") }
        public static var updateInterval: String { tr("更新间隔", "Update interval") }
        public static func everySeconds(_ seconds: Int) -> String { tr("每 \(seconds) 秒", "Every \(seconds)s") }
        public static var intervalNote: String { tr("间隔越长越省电；历史图表仍按时间范围展示。", "Longer intervals save energy; charts still cover the selected range.") }
        public static var menuBar: String { tr("菜单栏", "Menu Bar") }
        public static var displayMode: String { tr("显示方式", "Display") }
        public static var textMode: String { tr("文本", "Text") }
        public static var graphMode: String { tr("迷你图", "Mini Graph") }
        public static var graphNote: String { tr("迷你图展示最近约 30 个采样点的 CPU 占用趋势。", "The mini graph shows the last ~30 CPU samples.") }
        public static var appearance: String { tr("外观", "Appearance") }
        public static var followSystem: String { tr("跟随系统", "Match System") }
        public static var light: String { tr("浅色", "Light") }
        public static var dark: String { tr("深色", "Dark") }
        public static var general: String { tr("通用", "General") }
        public static var launchAtLogin: String { tr("开机启动", "Launch at Login") }
        public static var language: String { tr("语言", "Language") }
        public static var languageNote: String { tr("语言切换即时生效。", "Language changes apply immediately.") }
    }

    public enum Formatter {
        public static var unavailable: String { "—" }
        public static var memoryFallback: String { tr("物理内存", "Physical memory") }
        public static var seconds: String { tr("秒", "s") }
        public static var minutes: String { tr("分钟", "min") }
        public static var hours: String { tr("小时", "h") }
    }

    public enum Errors {
        public static var historyLoadFailed: String {
            tr("历史文件读取失败，原文件已保留；本次数据仅暂存在内存。", "Could not read the history file; it is untouched and this session stays in memory.")
        }
        public static var historySaveFailed: String {
            tr("历史保存失败；本次数据仍在内存，下次保存将重试。", "Saving history failed; data remains in memory and will retry on the next save.")
        }
    }
}
