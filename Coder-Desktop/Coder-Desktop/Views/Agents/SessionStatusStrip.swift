import CoderSDK
import SwiftUI

/// One live condition worth telling the user about. Four of these could previously be true
/// at once, each owning a full-width band above the transcript — two together pushed the
/// conversation off screen, and none said what to do next.
struct SessionNotice: Identifiable, Equatable {
    enum Kind: Int, Comparable {
        // Order IS severity: the strip shows the highest and counts the rest.
        case retrying, contextDirty, queued, failed
        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    let kind: Kind
    let message: String
    /// Label for the inline action, if this notice has one. A notice with no next step is a
    /// log line, not UI — the only exception is `retrying`, which resolves itself.
    var actionLabel: String?
    var id: Int { kind.rawValue }

    var systemImage: String {
        switch kind {
        case .failed, .queued: "exclamationmark.triangle.fill"
        case .contextDirty: "arrow.triangle.2.circlepath"
        case .retrying: "clock.arrow.circlepath"
        }
    }

    var tint: Color {
        switch kind {
        case .failed, .queued: .orange
        case .contextDirty, .retrying: .secondary
        }
    }
}

/// The single status row above the transcript. Shows the most severe live condition with its
/// action inline; the rest are counted and revealed on demand.
struct SessionStatusStrip: View {
    let notices: [SessionNotice]
    /// Runs the top notice's inline action.
    let onAction: (SessionNotice) -> Void
    @State private var expanded = false

    private var sorted: [SessionNotice] {
        notices.sorted { $0.kind > $1.kind }
    }

    var body: some View {
        if let top = sorted.first {
            VStack(alignment: .leading, spacing: 0) {
                row(top, isTop: true)
                if expanded {
                    ForEach(sorted.dropFirst()) { notice in
                        Divider()
                        row(notice, isTop: false)
                    }
                }
            }
            .background(top.tint.opacity(0.1))
        }
    }

    private func row(_ notice: SessionNotice, isTop: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: notice.systemImage)
                .foregroundStyle(notice.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(notice.message).font(.caption).lineLimit(2)
                if isTop, sorted.count > 1, !expanded {
                    Text("\(sorted.count - 1) more notice\(sorted.count == 2 ? "" : "s")")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let label = notice.actionLabel {
                Button(label) { onAction(notice) }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }
            if isTop, sorted.count > 1 {
                Button {
                    withAnimation(.easeOut(duration: Theme.Animation.collapsibleDuration)) {
                        expanded.toggle()
                    }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(expanded ? "Hide other notices" : "Show other notices")
            }
        }
        .padding(.horizontal, Theme.Size.trayInset)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
