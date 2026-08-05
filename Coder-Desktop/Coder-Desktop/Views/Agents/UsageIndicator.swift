import CoderSDK
import SwiftUI

/// The sidebar-footer usage widget: a dual ring (AI spend + workspace quota) that opens a
/// popover with the budget-period and workspace-quota breakdowns. Mirrors the web's
/// UsageIndicator.
///
/// Spend comes from AI Gateway budgets. Either ring is hidden when its data is absent —
/// deployments without AI Gateway, or without a budget or workspace quota configured, simply
/// fail or return no limit, which stands in for the web's `aibridge` feature check.
struct UsageIndicator<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents

    @State private var spend: UserAISpendStatus?
    @State private var quota: WorkspaceQuota?
    @State private var show = false

    /// Nil when no budget applies (unlimited), which hides the ring.
    private var spendFraction: Double? {
        guard let used = spend?.current_spend_micros,
              let budget = spend?.effective_budget?.spend_limit_micros else { return nil }
        return Budget.fraction(used: used, budget: budget)
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
            spend = await agents.aiSpend()
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
        guard let used = spend?.current_spend_micros,
              let budget = spend?.effective_budget?.spend_limit_micros else { return "AI usage" }
        return "AI spend: \(Money.dollars(used)) of \(Money.dollars(budget))"
    }

    private var quotaHelp: String {
        guard let used = quota?.credits_consumed, let budget = quota?.budget else { return "Workspace quota" }
        return "Workspace quota: \(used) of \(budget) credits"
    }

    private var combinedHelp: String {
        let parts = [spendFraction != nil ? spendHelp : nil, quotaFraction != nil ? quotaHelp : nil].compactMap(\.self)
        return parts.isEmpty ? "Usage" : parts.joined(separator: " · ")
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
                Text("No AI budget or workspace quota configured.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }

    private func spendSection(_ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("AI spend").font(.callout.weight(.semibold))
                Spacer()
                Text("\(Int((fraction * 100).rounded()))%").foregroundStyle(.secondary)
            }
            ProgressView(value: fraction).tint(severity(fraction))
            if let used = spend?.current_spend_micros,
               let budget = spend?.effective_budget?.spend_limit_micros
            {
                Text("\(Money.dollars(used)) of \(Money.dollars(budget)) used")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let period = periodLabel {
                Text(period).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

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

    /// The budget window, e.g. "June 1 - July 1, 2026". `period_end` is exclusive and rendered
    /// as-is, matching the web's `formatSpendPeriodLabel`.
    private var periodLabel: String? {
        guard let start = spend?.period_start, let end = spend?.period_end else { return nil }
        return "\(start.formatted(.dateTime.month(.wide).day())) - "
            + "\(end.formatted(.dateTime.month(.wide).day().year()))"
    }
}

/// Formats micro-dollar amounts (USD × 1e6) as "$X.XX".
enum Money {
    static func dollars(_ micros: Int) -> String {
        String(format: "$%.2f", Double(micros) / 1_000_000)
    }
}

/// Budget severity/progress rules, matching the web's `utils/budget.ts`.
enum Budget {
    /// Usage as a 0...1 fraction. A budget of 0 counts as fully used once anything is spent.
    static func fraction(used: Int, budget: Int) -> Double? {
        guard budget >= 0 else { return nil }
        if budget == 0 { return used > 0 ? 1 : 0 }
        return min(1, Double(used) / Double(budget))
    }
}
