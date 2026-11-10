import Foundation
import Network

struct NetworkPathStatus: Sendable, Equatable {
    let online: Bool
    let interfaceType: String
}

/// Event-driven path monitoring; no polling. Updates arrive on the monitor's
/// internal queue and must be republished by the caller.
final class NetworkPathMonitor {
    private let monitor = NWPathMonitor()
    private let onUpdate: @Sendable (NetworkPathStatus) -> Void

    init(onUpdate: @escaping @Sendable (NetworkPathStatus) -> Void) {
        self.onUpdate = onUpdate
        monitor.pathUpdateHandler = { path in
            onUpdate(NetworkPathStatus(
                online: path.status == .satisfied,
                interfaceType: Self.describe(path)
            ))
        }
        monitor.start(queue: DispatchQueue(label: "com.macpulse.path", qos: .utility))
    }

    private static func describe(_ path: NWPath) -> String {
        if path.usesInterfaceType(.wifi) { return "Wi-Fi" }
        if path.usesInterfaceType(.wiredEthernet) { return L10n.Details.wiredEthernet }
        if path.usesInterfaceType(.cellular) { return L10n.Details.cellular }
        if path.usesInterfaceType(.loopback) { return L10n.Details.loopback }
        return L10n.Details.otherInterface
    }

    func cancel() {
        monitor.pathUpdateHandler = nil
        monitor.cancel()
    }

    deinit {
        cancel()
    }
}
