import SwiftUI

enum MetricCategory: String, CaseIterable, Hashable {
    case cpu
    case memory
    case disk
    case network

    var title: String {
        switch self {
        case .cpu: return L10n.tr("处理器", "CPU")
        case .memory: return L10n.tr("内存", "Memory")
        case .disk: return L10n.tr("磁盘", "Disk")
        case .network: return L10n.tr("网络", "Network")
        }
    }

    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "network"
        }
    }

    var tint: Color {
        switch self {
        case .cpu: return .blue
        case .memory: return .purple
        case .disk: return .orange
        case .network: return .green
        }
    }

    /// Headline metric on a MetricPoint, used for sparklines and quick stats.
    var pointKeyPath: KeyPath<MetricPoint, Double?> {
        switch self {
        case .cpu: return \.cpu
        case .memory: return \.memory
        case .disk: return \.diskRead
        case .network: return \.networkReceive
        }
    }
}
