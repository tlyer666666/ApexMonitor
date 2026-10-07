import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store: MonitorStore
    private let loginItem = LoginItem()
    private let settings: AppSettings
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var dashboardWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var snapshotObserver: AnyCancellable?
    private var settingsObservers: [AnyCancellable] = []

    init(historyFile: HistoryFileStore = .defaultStore(), defaults: UserDefaults = .standard) {
        store = MonitorStore(historyFile: historyFile)
        settings = AppSettings(defaults: defaults)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = settings.appearance.nsAppearance
        configureStatusItem()
        configurePopover()
        observeSnapshots()
        observeSettings()
        store.start(interval: settings.updateInterval)
        // Launching the app is an explicit user action: show the dashboard
        // instead of sitting hidden in the menu bar.
        openDashboard()
    }

    /// Reopening the app while it runs must surface the dashboard; the status
    /// item keeps a window on screen, so `hasVisibleWindows` cannot be trusted.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openDashboard()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.title = "CPU —"
        button.imagePosition = .noImage
        button.toolTip = "MacPulse 系统性能（左键弹层 · 右键菜单）"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        // Deliver right-clicks to the action so a context menu can be shown.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePopover(sender)
            return
        }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    /// Right-click menu: the tray-only escape hatch for opening the panel or
    /// quitting. Temporarily assigning statusItem.menu is the standard trick
    /// to anchor an NSMenu under a status item that also uses a popover.
    private func showContextMenu() {
        popover.performClose(nil)
        let menu = NSMenu()
        menu.autoenablesItems = false
        let dashboard = NSMenuItem(title: "打开主面板", action: #selector(openDashboardFromMenu), keyEquivalent: "")
        dashboard.target = self
        menu.addItem(dashboard)
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let launchAtLogin = NSMenuItem(
            title: "开机启动",
            action: #selector(toggleLaunchAtLoginFromMenu),
            keyEquivalent: ""
        )
        launchAtLogin.target = self
        launchAtLogin.state = loginItem.isEnabled ? .on : .off
        menu.addItem(launchAtLogin)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 MacPulse", action: #selector(quitFromMenu), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleLaunchAtLoginFromMenu() {
        loginItem.setEnabled(!loginItem.isEnabled)
    }

    @objc private func openDashboardFromMenu() {
        openDashboard()
    }

    @objc private func showSettingsFromMenu() {
        showSettings()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        // No fixed contentSize: the hosting controller reports its fitting
        // size, so the quit buttons can never be clipped by a stale height.
        popover.contentViewController = NSHostingController(
            rootView: MenuPopoverView(
                store: store,
                loginItem: loginItem,
                onOpenCategory: { [weak self] category in
                    self?.openCategoryDashboard(category)
                },
                onOpenDashboard: { [weak self] in self?.openDashboard() },
                onOpenSettings: { [weak self] in self?.showSettings() },
                onQuit: { NSApp.terminate(nil) }
            )
        )
    }

    /// Opens (or focuses) the dashboard and lands directly on the tapped
    /// category's detail page.
    private func openCategoryDashboard(_ category: MetricCategory) {
        openDashboard()
        store.navigationPath = [category]
    }

    private func observeSnapshots() {
        snapshotObserver = store.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.refreshStatusBar(with: snapshot)
            }
    }

    private func refreshStatusBar(with snapshot: MetricsSnapshot?) {
        guard let button = statusItem.button else { return }
        switch settings.menuBarDisplay {
        case .text:
            button.image = nil
            button.title = snapshot.map {
                "CPU \(MetricsFormatter.cpuPercent($0.cpuPercent))"
            } ?? "CPU —"
        case .graph:
            button.title = ""
            button.image = Self.menuBarGraph(from: store.recentCPUPercents())
        }
    }

    /// Renders recent CPU percentages as a template image so the menu bar
    /// graph adapts to light/dark and highlighted states automatically.
    private static func menuBarGraph(from values: [Double?]) -> NSImage? {
        let present = values.compactMap { value -> Double? in
            guard let value, value.isFinite else { return nil }
            return min(max(value, 0), 100) / 100
        }
        guard present.count >= 2 else { return nil }
        let tail = present.suffix(30)

        let points = CGFloat(30)
        let height = CGFloat(14)
        let image = NSImage(size: NSSize(width: points, height: height))
        image.lockFocus()
        NSColor.black.setStroke()
        NSColor.black.setFill()
        let step = points / CGFloat(tail.count - 1)
        let baseline = height - 1
        let usable = height - 2
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: NSPoint(x: 0, y: baseline - CGFloat(tail.first ?? 0) * usable))
        for (index, value) in tail.enumerated().dropFirst() {
            let x = CGFloat(index) * step
            let y = baseline - CGFloat(value) * usable
            path.line(to: NSPoint(x: x, y: y))
        }
        path.stroke()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func observeSettings() {
        settingsObservers = [
            settings.$updateInterval.dropFirst().sink { [weak self] interval in
                self?.store.setUpdateInterval(interval)
            },
            settings.$menuBarDisplay.dropFirst().sink { [weak self] _ in
                guard let self else { return }
                self.refreshStatusBar(with: self.store.snapshot)
            },
            settings.$appearance.dropFirst().sink { appearance in
                NSApp.appearance = appearance.nsAppearance
            }
        ]
    }

    private func showSettings() {
        popover.performClose(nil)
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(
            rootView: SettingsView(settings: settings, loginItem: loginItem)
        ))
        window.title = "MacPulse 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func openDashboard() {
        popover.performClose(nil)
        if let dashboardWindow {
            dashboardWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: DashboardView(store: store))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MacPulse · 系统性能"
        window.setContentSize(NSSize(width: 800, height: 700))
        window.minSize = NSSize(width: 780, height: 680)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        dashboardWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AppDelegate: NSWindowDelegate {
    // The dashboard window instance is kept alive so the selected range
    // survives reopen. Closing it must also stop detail sampling and pop
    // back to the overview: the retained NSHostingView keeps its SwiftUI
    // hierarchy mounted, so onDisappear/onAppear never fire for this window.
    func windowWillClose(_ notification: Notification) {
        store.endLiveDetail()
        store.navigationPath = []
    }
}

#if !MACPULSE_INTEGRATION
@main
struct MacPulseApplication {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
#endif
