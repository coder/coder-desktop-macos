import SwiftUI

struct CircularProgressView: View {
    let value: Float?

    var strokeWidth: CGFloat = 4
    var diameter: CGFloat = 22
    var primaryColor: Color = .secondary
    var backgroundColor: Color = .secondary.opacity(0.3)

    @State private var rotation = 0.0
    @State private var trimAmount: CGFloat = 0.15

    var autoCompleteThreshold: Float?
    var autoCompleteDuration: TimeInterval?

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(backgroundColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .frame(width: diameter, height: diameter)
            Group {
                if let value {
                    // Determinate gauge
                    Circle()
                        .trim(from: 0, to: CGFloat(displayValue(for: value)))
                        .stroke(primaryColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                        .frame(width: diameter, height: diameter)
                        .rotationEffect(.degrees(-90))
                        .animation(autoCompleteAnimation(for: value), value: value)
                } else {
                    // Indeterminate gauge
                    Circle()
                        .trim(from: 0, to: trimAmount)
                        .stroke(primaryColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                        .frame(width: diameter, height: diameter)
                        .rotationEffect(.degrees(rotation))
                }
            }
        }
        .frame(width: diameter + strokeWidth * 2, height: diameter + strokeWidth * 2)
        .onAppear {
            if value == nil {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
        }
    }

    private func displayValue(for value: Float) -> Float {
        if let threshold = autoCompleteThreshold,
           value >= threshold, value < 1.0
        {
            return 1.0
        }
        return value
    }

    private func autoCompleteAnimation(for value: Float) -> Animation? {
        guard let threshold = autoCompleteThreshold,
              let duration = autoCompleteDuration,
              value >= threshold, value < 1.0
        else {
            return .default
        }

        return .easeOut(duration: duration)
    }
}

extension CircularProgressView {
    func autoComplete(threshold: Float, duration: TimeInterval) -> CircularProgressView {
        var view = self
        view.autoCompleteThreshold = threshold
        view.autoCompleteDuration = duration
        return view
    }
}
