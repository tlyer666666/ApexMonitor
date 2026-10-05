import AppKit
import Foundation

@main
struct GUIHarness {
    @MainActor static func main() {
        guard CommandLine.arguments.count > 1 else {
            fputs("usage: MacPulseUITest <history-directory>\n", stderr)
            exit(2)
        }
        let application = NSApplication.shared
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let delegate = AppDelegate(historyFile: HistoryFileStore(directory: directory))
        application.delegate = delegate
        application.run()
    }
}
