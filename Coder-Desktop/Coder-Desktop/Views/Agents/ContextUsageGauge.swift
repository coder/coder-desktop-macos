import SwiftUI

/// A small circular gauge showing how much of the model's context window is used,
/// mirroring the context-usage indicator next to the web composer's model picker.
struct ContextUsageGauge: View {
    let fraction: Double

    private var clamped: Double {
        min(1, max(0, fraction))
    }

    private var color: Color {
        switch clamped {
        case 0.9...: .red
        case 0.7...: .orange
        default: .secondary
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.001, clamped))
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 18, height: 18)
        // Rich details live in the hover popover the composer attaches; keep the gauge itself
        // free of a competing tooltip.
        .contentShape(Rectangle())
        .accessibilityLabel("Context \(Int((clamped * 100).rounded())) percent used")
    }
}

/// The hover popover for the context gauge, mirroring the web: a usage header, the compaction
/// threshold, and the context files / skills currently loaded into the conversation.
struct ContextUsagePopover: View {
    let percent: Int
    let usedTokens: Int?
    let contextLimit: Int?
    let compactsAtPercent: Int?
    let contextFiles: [String]
    let skills: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(header).font(.callout.weight(.semibold))
                if let compactsAtPercent {
                    Text("Compacts at \(compactsAtPercent)%").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !contextFiles.isEmpty {
                section("Context files", items: contextFiles, icon: "doc")
            }
            if !skills.isEmpty {
                section("Skills", items: skills, icon: "bolt")
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }

    private var header: String {
        if let usedTokens, let contextLimit, contextLimit > 0 {
            return "\(percent)% – \(Self.compact(usedTokens)) / \(Self.compact(contextLimit)) context used"
        }
        return "\(percent)% context used"
    }

    @ViewBuilder
    private func section(_ title: String, items: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold))
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: icon)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// Compact token count like the web: 19.7K, 200K (not 19,700).
    static func compact(_ n: Int) -> String {
        guard n >= 1000 else { return "\(n)" }
        let k = Double(n) / 1000
        return k >= 100 ? "\(Int(k.rounded()))K" : String(format: "%.1fK", k)
    }
}
