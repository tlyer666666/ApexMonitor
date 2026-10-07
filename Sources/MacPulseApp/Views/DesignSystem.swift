import SwiftUI

/// Shared design tokens for the MacPulse UI. Single source of truth for
/// category colors, card styling and spacing so all surfaces stay consistent.
enum DesignSystem {
    enum Spacing {
        static let page: CGFloat = 20
        static let card: CGFloat = 16
        static let row: CGFloat = 8
        static let section: CGFloat = 16
    }

    enum CornerRadius {
        static let card: CGFloat = 16
        static let inner: CGFloat = 8
    }

    enum Chart {
        static let height: CGFloat = 110
        static let sparkline: CGFloat = 20
    }
}

extension MetricCategory {
    /// Headline shown on dashboard cards; the trailing detail line carries
    /// the secondary direction (write/send).
    var headline: String {
        switch self {
        case .cpu: return "总使用率"
        case .memory: return "当前占用"
        case .disk: return "读取"
        case .network: return "接收"
        }
    }

    var secondaryHeadline: String? {
        switch self {
        case .disk: return "写入"
        case .network: return "发送"
        default: return nil
        }
    }

    var currentValue: ((MetricsSnapshot?) -> String) {
        switch self {
        case .cpu:
            return { MetricsFormatter.cpuPercent($0?.cpuPercent) }
        case .memory:
            return { MetricsFormatter.percent($0?.memoryPercent) }
        case .disk:
            return { MetricsFormatter.bytesPerSecond($0?.diskReadBytesPerSecond) }
        case .network:
            return { MetricsFormatter.bytesPerSecond($0?.networkReceiveBytesPerSecond) }
        }
    }

    var secondaryValue: ((MetricsSnapshot?) -> String?)? {
        switch self {
        case .disk:
            return { MetricsFormatter.bytesPerSecond($0?.diskWriteBytesPerSecond) }
        case .network:
            return { MetricsFormatter.bytesPerSecond($0?.networkSendBytesPerSecond) }
        default:
            return nil
        }
    }
}

/// Hover-highlighted, clickable card used for dashboard category navigation
/// and any row that acts as a button.
struct HoverableCard<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: Content
    @State private var hovering = false
    @State private var pressing = false

    var body: some View {
        content
            .background(
                (hovering ? tint.opacity(0.10) : Color.clear),
                in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.card)
            )
            .opacity(pressing ? 0.85 : 1)
            .scaleEffect(pressing ? 0.99 : 1)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) { self.hovering = hovering }
            }
    }
}

/// Standard empty state for charts and lists that are still collecting data.
struct CollectingPlaceholder: View {
    var text: String = L10n.Charts.establishingBaseline

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
