import AppKit
import CoderSDK
import SwiftUI

/// Shared ISO-8601 formatter — formatters are costly to build and thread-safe to format with.
/// File-level (not a static on the generic view, which Swift disallows).
private nonisolated(unsafe) let analyticsISO8601 = ISO8601DateFormatter()

/// Personal usage analytics: AI cost summary over a selectable date range.
/// Reached from the sidebar usage widget's "View usage". All amounts are micro-dollars.
struct AnalyticsView<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents

    @State private var rangeDays = 30
    @State private var cost: ChatCostSummary?
    @State private var loading = false

    private let ranges = [7, 14, 30, 90]
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("AI usage").font(.title2.bold())
                    Spacer()
                    Picker("Range", selection: $rangeDays) {
                        ForEach(ranges, id: \.self) { Text("\($0)d").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Date range")
                }

                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                }

                costSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: rangeDays) { await load() }
    }

    private var costSection: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            statCard("Total cost", Money.dollars(cost?.total_cost_micros ?? 0))
            statCard("Input tokens", (cost?.total_input_tokens ?? 0).formatted())
            statCard("Output tokens", (cost?.total_output_tokens ?? 0).formatted())
            statCard("Cache read", (cost?.total_cache_read_tokens ?? 0).formatted())
            statCard("Cache write", (cost?.total_cache_creation_tokens ?? 0).formatted())
            statCard("Messages", (cost?.priced_message_count ?? 0).formatted())
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
        // VoiceOver otherwise reads the bare value first ("$1.23, Total cost").
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }

    private func load() async {
        loading = true
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -rangeDays, to: now) ?? now
        let startStr = analyticsISO8601.string(from: start)
        let endStr = analyticsISO8601.string(from: now)
        cost = await agents.costSummary(start: startStr, end: endStr)
        loading = false
    }
}
