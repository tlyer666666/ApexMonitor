import Foundation

func testStringsAreSimplifiedChineseOnly() {
    expect(L10n.MenuBar.quit == "退出 MacPulse", "the menu bar quit label stays Simplified Chinese")
    expect(L10n.Dashboard.title == "系统性能", "the dashboard title stays Simplified Chinese")
    expect(L10n.Settings.windowTitle == "MacPulse 设置", "the settings window title stays Simplified Chinese")
    expect(L10n.MenuBar.launchAtLoginApproval == "开机启动 · 待批准", "approval-pending login items get their own label")
    expect(L10n.Errors.historyLoadFailed.isEmpty == false, "history failures explain themselves in Chinese")
}

func testFormatterMarkersStayChinese() {
    expect(L10n.Formatter.unavailable == "—", "the unavailable marker is shared")
    expect(L10n.Formatter.memoryFallback == "物理内存", "memory fallback stays Chinese")
}

func testDashboardCadenceTextReflectsConfiguredInterval() {
    expect(L10n.Dashboard.updateCadence(1) == "每秒更新", "one-second cadence keeps the every-second wording")
    expect(L10n.Dashboard.updateCadence(2) == "每 2 秒更新", "two-second cadence names its interval")
    expect(L10n.Dashboard.updateCadence(5) == "每 5 秒更新", "five-second cadence names its interval")
    expect(L10n.Dashboard.updateCadence(2.4) == "每 2 秒更新", "fractional cadences round to whole seconds")
}

func runL10nTests() {
    testStringsAreSimplifiedChineseOnly()
    testFormatterMarkersStayChinese()
    testDashboardCadenceTextReflectsConfiguredInterval()
}
