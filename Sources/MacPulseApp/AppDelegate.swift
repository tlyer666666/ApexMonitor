import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = MonitorStore()
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
        if ProcessInfo.processInfo.arguments.contains("--dashboard") {
            openDashboard()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.title = "CPU —"
        button.imagePosition = .noImage
        button.toolTip = "MacPulse 系统性能"
        button.target = self
        button.action = #selector(togglePopover(_:))
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 330, height: 390)
        popover.contentViewController = NSHostingController(
            rootView: MenuPopoverView(
                store: store,
                onOpenDashboard: { [weak self] in self?.openDashboard() },
                onQuit: { NSApp.terminate(nil) }
            )
        )
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
    // The dashboard window instance is kept alive when closed so its SwiftUI
    // state (selected time range) survives reopen; reopening just re-orders it.
    func windowWillClose(_ notification: Notification) {}
}

@main
struct MacPulseApplication {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
