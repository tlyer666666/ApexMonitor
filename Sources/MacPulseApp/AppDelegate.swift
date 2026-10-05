import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store: MonitorStore

    init(historyFile: HistoryFileStore = .defaultStore()) {
        store = MonitorStore(historyFile: historyFile)
        super.init()
    }
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var dashboardWindow: NSWindow?
    private var snapshotObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        observeSnapshots()
        store.start()
        // Launching the app is an explicit user action: show the dashboard
        // instead of sitting hidden in the menu bar.
        openDashboard()
    }

    /// Double-clicking the Desktop shortcut (or `open`) on an already-running
    /// instance must also surface the dashboard, even when the window was
    /// closed earlier. `hasVisibleWindows` is unreliable here because the
    /// status item's own window is always on screen, so unconditionally call
    /// the idempotent open: it focuses the retained window or recreates it.
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
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 MacPulse", action: #selector(quitFromMenu), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openDashboardFromMenu() {
        openDashboard()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 330, height: 390)
        popover.contentViewController = NSHostingController(
            rootView: MenuPopoverView(
                store: store,
                onOpenCategory: { [weak self] category in
                    self?.openCategoryDashboard(category)
                },
                onOpenDashboard: { [weak self] in self?.openDashboard() },
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
                self.statusItem.button?.title = snapshot?.cpuPercent.map {
                    "CPU \(MetricsFormatter.cpuPercent($0))"
                } ?? "CPU —"
            }
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
        window.minSize = NSSize(width: 760, height: 640)
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
