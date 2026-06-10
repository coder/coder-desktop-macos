import SwiftUI

/// Character-budget smooth-reveal engine (port of the web's SmoothText). Reveals a growing
/// target string at an adaptive rate so streamed text appears at a steady, readable pace
/// rather than in chunky bursts. Frame-rate invariant: it accrues a fractional character
/// budget over time and reveals whole characters as the budget allows.
@MainActor
final class SmoothTextEngine {
    private(set) var visibleCount = 0
    private var fullCount = 0
    private var budget = 0.0
    private var lastDate: Date?

    private static let baseCPS = 72.0
    private static let minCPS = 24.0
    private static let maxCPS = 420.0
    private static let catchupBacklog = 180.0
    private static let maxVisualLag = 120
    private static let maxFrameChars = 48

    /// Advances the reveal to `date` and returns the number of leading characters to show.
    func advance(to date: Date, fullCount: Int, isStreaming: Bool) -> Int {
        // Content shrank (edit/rewind) → snap back; not streaming → show everything.
        if fullCount < visibleCount { visibleCount = fullCount; budget = 0 }
        self.fullCount = fullCount
        guard isStreaming else {
            visibleCount = fullCount
            lastDate = nil
            return visibleCount
        }
        // A big burst shouldn't leave a long hidden tail to dribble out.
        if visibleCount < fullCount - Self.maxVisualLag { visibleCount = fullCount - Self.maxVisualLag }

        let dt = lastDate.map { date.timeIntervalSince($0) } ?? 0
        lastDate = date
        guard visibleCount < fullCount, dt > 0 else { return visibleCount }

        let backlog = Double(fullCount - visibleCount)
        let pressure = min(1, max(0, backlog / Self.catchupBacklog))
        let rate = min(Self.maxCPS, max(Self.minCPS, Self.baseCPS + pressure * (Self.maxCPS - Self.baseCPS)))
        budget += rate * min(0.1, dt)
        let whole = Int(budget.rounded(.down))
        guard whole >= 1 else { return visibleCount }
        let reveal = min(whole, Self.maxFrameChars)
        visibleCount = min(fullCount, visibleCount + reveal)
        budget -= Double(reveal)
        return visibleCount
    }

    func isCaughtUp(_ fullCount: Int) -> Bool { visibleCount >= fullCount }
}

/// Renders streaming markdown text with a smooth character reveal; once `isStreaming` is
/// false it shows the full text immediately. The reveal is confined to this leaf view (below
/// `MessageView`'s `.equatable()` boundary), so it keeps ticking even when the parent is
/// equatable-skipped between stream events.
struct SmoothMarkdownText: View {
    let text: String
    var isStreaming = false

    @State private var engine = SmoothTextEngine()
    // Drives `paused:` via real state: the schedule only re-reads `paused` on a body re-eval,
    // which never happens during an in-turn stall (tool calls) — without this the timeline
    // kept ticking at 30fps doing O(text) prefix copies for nothing.
    @State private var caughtUp = false

    var body: some View {
        if isStreaming {
            // Count/slice the String directly rather than materialising an [Character] every token
            // (that allocation was O(n) per token → O(n²) over a long streamed message).
            let fullCount = text.count
            // 30fps is indistinguishable for a typewriter reveal and halves the per-frame
            // prefix/diff work on long messages (display refresh would tick at up to 120Hz).
            TimelineView(.animation(minimumInterval: 1 / 30, paused: caughtUp)) { context in
                let count = engine.advance(to: context.date, fullCount: fullCount, isStreaming: true)
                let reachedEnd = count >= fullCount
                let _ = scheduleCatchUpPauseIfNeeded(reachedEnd) // swiftlint:disable:this redundant_discardable_let
                // Plain text for the WHOLE stream. Swapping to MarkdownText at each catch-up
                // re-parsed the full message (and re-highlighted its code blocks, always a cache
                // miss on the growing text) several times a second — a repeated main-thread
                // hitch plus a styled/plain flicker. Styling snaps in once the turn commits.
                Text(reachedEnd ? text : String(text.prefix(count)))
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.updatesFrequently)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: text) { caughtUp = false } // next token resumes the reveal
        } else {
            MarkdownText(text: text)
        }
    }

    /// Flips `caughtUp` (pausing the timeline) outside the current view update — state can't
    /// be mutated from inside the TimelineView content closure.
    private func scheduleCatchUpPauseIfNeeded(_ reachedEnd: Bool) {
        guard reachedEnd, !caughtUp else { return }
        DispatchQueue.main.async { caughtUp = true }
    }
}
