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
        .frame(width: 14, height: 14)
        .accessibilityLabel("Context \(Int(clamped * 100)) percent used")
        .help("Context \(Int(clamped * 100))% used")
    }
}
