import AppKit
import CoderSDK
import SwiftUI

/// Personal usage analytics: AI cost summary and pull-request insights over a selectable date
/// range. Reached from the sidebar usage widget's "View usage". All amounts are micro-dollars.
struct AnalyticsView<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents

    @State private var rangeDays = 30
    @State private var cost: ChatCostSummary?
    @State private var insights: PRInsightsResponse?
    @State private var loading = false

    private let ranges = [7, 14, 30, 90]
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Cost & PR Insights").font(.title2.bold())
                    Spacer()
                    Picker("Range", selection: $rangeDays) {
                        ForEach(ranges, id: \.self) { Text("\($0)d").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                }

                costSection
                prSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: rangeDays) { await load() }
    }

    private var costSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI usage").font(.headline)
            LazyVGrid(columns: columns, spacing: 12) {
                statCard("Total cost", Money.dollars(cost?.total_cost_micros ?? 0))
                statCard("Input tokens", (cost?.total_input_tokens ?? 0).formatted())
                statCard("Output tokens", (cost?.total_output_tokens ?? 0).formatted())
                statCard("Messages", (cost?.priced_message_count ?? 0).formatted())
            }
        }
    }

    @ViewBuilder
    private var prSection: some View {
        let summary = insights?.summary
        VStack(alignment: .leading, spacing: 8) {
            Text("Pull requests").font(.headline)
            if (summary?.total_prs_created ?? 0) == 0 {
                Text("No pull requests in this period.").font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    statCard("Created", "\(summary?.total_prs_created ?? 0)")
                    statCard("Merged", "\(summary?.total_prs_merged ?? 0)")
                    statCard("Merge rate", "\(Int(((summary?.merge_rate ?? 0) * 100).rounded()))%")
                    statCard("Cost / merged PR", Money.dollars(summary?.cost_per_merged_pr_micros ?? 0))
                }
                ForEach(insights?.recent_prs ?? []) { prRow($0) }
            }
        }
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius * 2))
    }

    @ViewBuilder
    private func prRow(_ pr: PRInsightsResponse.PullRequest) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch").font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(pr.pr_title ?? "Pull request").lineLimit(1)
                HStack(spacing: 6) {
                    if let state = pr.state { Text(state.capitalized) }
                    if let adds = pr.additions, adds > 0 { Text("+\(adds)").foregroundStyle(.green) }
                    if let dels = pr.deletions, dels > 0 { Text("−\(dels)").foregroundStyle(.red) }
                    if let model = pr.model_display_name { Text("· \(model)") }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if let cost = pr.cost_micros { Text(Money.dollars(cost)).font(.caption).foregroundStyle(.secondary) }
            if let url = pr.pr_url.flatMap(URL.init) {
                Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        loading = true
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -rangeDays, to: now) ?? now
        let formatter = ISO8601DateFormatter()
        let startStr = formatter.string(from: start)
        let endStr = formatter.string(from: now)
        cost = await agents.costSummary(start: startStr, end: endStr)
        insights = await agents.prInsights(start: startStr, end: endStr)
        loading = false
    }
}
