import Foundation

func testL10nFollowsExplicitOverride() {
    L10n.override = .zhHans
    expect(L10n.MenuBar.quit == "退出 MacPulse", "Chinese override returns Chinese strings")
    L10n.override = .en
    expect(L10n.MenuBar.quit == "Quit MacPulse", "English override returns English strings")
    L10n.override = nil
}

func testL10nFormatterStringsAreLocalized() {
    L10n.override = .en
    expect(L10n.Formatter.unavailable == "—", "unavailable marker is shared across languages")
    L10n.override = .zhHans
    expect(L10n.Formatter.memoryFallback == "物理内存", "memory fallback stays Chinese in Chinese mode")
    L10n.override = nil
}

func testHistoryValidationErrorIsLocalized() {
    L10n.override = .en
    expect(L10n.Errors.historyLoadFailed.isEmpty == false, "English load-failure message is non-empty")
    L10n.override = nil
}

func runL10nTests() {
    testL10nFollowsExplicitOverride()
    testL10nFormatterStringsAreLocalized()
    testHistoryValidationErrorIsLocalized()
}
