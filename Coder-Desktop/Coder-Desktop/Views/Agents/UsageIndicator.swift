import CoderSDK
import SwiftUI

/// The sidebar-footer usage widget: a dual ring (AI spend + workspace quota) that opens a
/// popover with the weekly-usage and workspace-quota breakdowns plus a "View usage" link to
/// the full insights view. The quota ring only appears when a workspace quota is configured
/// (premium deployments). Mirrors the web's UsageIndicator.
struct UsageIndicator<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    var onViewUsage: () -> Void

    @State private var limit: ChatUsageLimitStatus?
    @State private var quota: WorkspaceQuota?
    @State private var show = false

    private var spendFraction: Double? {
        guard limit?.is_limited == true, let spend = limit?.current_spend,
              let max = limit?.spend_limit_micros, max > 0 else { return nil }
        return min(1, Double(spend) / Double(max))
    }

    private var quotaFraction: Double? {
        guard let budget = quota?.budget, budget > 0, let used = quota?.credits_consumed else { return nil }
        return min(1, Double(used) / Double(budget))
    }

    var body: some View {
        Button { show.toggle() } label: {
            HStack(spacing: 8) {
                if let spendFraction {
                    ring(spendFraction, color: severity(spendFraction), symbol: "dollarsign")
                        .accessibilityLabel(spendHelp)
                }
                if let quotaFraction {
                    ring(quotaFraction, color: .blue, symbol: "cpu")
                        .accessibilityLabel(quotaHelp)
                }
                if spendFraction == nil, quotaFraction == nil {
                    Image(systemName: "chart.bar").font(.body)
                }
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(combinedHelp)
        .popover(isPresented: $show, arrowEdge: .top) { popover }
        .task {
            limit = await agents.usageLimit()
            quota = await agents.workspaceQuota()
        }
    }

    /// A progress ring with a descriptive glyph at its center.
    private func ring(_ fraction: Double, color: Color, symbol: String) -> some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: symbol).font(.caption2.weight(.semibold)).foregroundStyle(color)
        }
        .frame(width: 22, height: 22)
    }

    private var spendHelp: String {
        guard let spend = limit?.current_spend, let max = limit?.spend_limit_micros else { return "AI usage" }
        return "AI spend: \(Money.dollars(spend)) of \(Money.dollars(max))"
    }

    private var quotaHelp: String {
        guard let used = quota?.credits_consumed, let budget = quota?.budget else { return "Workspace quota" }
        return "Workspace quota: \(used) of \(budget) credits"
    }

    private var combinedHelp: String {
        let parts = [spendFraction != nil ? spendHelp : nil, quotaFraction != nil ? quotaHelp : nil].compactMap { $0 }
        return parts.isEmpty ? "View usage" : parts.joined(separator: " · ")
    }

    private func severity(_ fraction: Double) -> Color {
        switch fraction {
        case 1...: .red
        case 0.85...: .orange
        default: .secondary
        }
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let spendFraction { spendSection(spendFraction) }
            if let quotaFraction {
                if spendFraction != nil { Divider() }
                quotaSection(quotaFraction)
            }
            if spendFraction == nil, quotaFraction == nil {
                Text("No usage limits configured.").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Button("View usage") { show = false; onViewUsage() }
                .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }

    @ViewBuilder
    private func spendSection(_ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(periodLabel).font(.callout.weight(.semibold))
                Spacer()
                Text("\(Int((fraction * 100).rounded()))%").foregroundStyle(.secondary)
            }
            ProgressView(value: fraction).tint(severity(fraction))
            if let spend = limit?.current_spend, let max = limit?.spend_limit_micros {
                Text("\(Money.dollars(spend)) of \(Money.dollars(max)) used")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let resets = limit?.period_end {
                Text("Resets \(resets.formatted(.dateTime.month().day().year()))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func quotaSection(_ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Workspace quota").font(.callout.weight(.semibold))
                Spacer()
                Text("\(Int((fraction * 100).rounded()))%").foregroundStyle(.secondary)
            }
            ProgressView(value: fraction).tint(.blue)
            if let used = quota?.credits_consumed, let budget = quota?.budget {
                Text("\(agents.workspaces.count) workspaces using \(used) of \(budget) credits")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var periodLabel: String {
        switch limit?.period {
        case "day": "Daily usage"
        case "month": "Monthly usage"
        default: "Weekly usage"
        }
    }
}

/// Formats micro-dollar amounts (USD × 1e6) as "$X.XX".
enum Money {
    static func dollars(_ micros: Int) -> String {
        String(format: "$%.2f", Double(micros) / 1_000_000)
    }
}
