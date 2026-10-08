import Foundation

func testL10nFollowsExplicitOverride() {
    L10n.override = .zhHans
    expect(L10n.MenuBar.quit == "退出 MacPulse", "Chinese override returns Chinese strings")
    L10n.override = .en
    expect(L10n.MenuBar.quit == "Quit MacPulse", "English override returns English strings")
    L10n.override = nil
}

func testSystemOverrideResolvesInsteadOfFallingBackToEnglish() {
    L10n.override = nil
    let resolved = L10n.language
    L10n.override = .system
    expect(L10n.language == resolved,
           "explicit .system resolves exactly like the default, not falling through to English")
    L10n.override = nil
}

func testMissingStoredPreferenceDefaultsToChinese() {
    expect(AppLanguage.stored(nil) == .zhHans, "no stored preference defaults to Simplified Chinese")
    expect(AppLanguage.stored("garbage") == .zhHans, "an unreadable stored preference defaults to Simplified Chinese")
    expect(AppLanguage.stored("en") == .en, "a stored English preference is honored")
    expect(AppLanguage.stored("zh-Hans") == .zhHans, "a stored Chinese preference is honored")
    expect(AppLanguage.stored("system") == .system, "a stored follow-system preference is honored")
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
    testSystemOverrideResolvesInsteadOfFallingBackToEnglish()
    testMissingStoredPreferenceDefaultsToChinese()
    testL10nFormatterStringsAreLocalized()
    testHistoryValidationErrorIsLocalized()
}
