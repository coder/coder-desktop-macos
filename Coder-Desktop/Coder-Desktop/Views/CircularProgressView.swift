import SwiftUI

struct CircularProgressView: View {
    let value: Float?

    var strokeWidth: CGFloat = 4
    var diameter: CGFloat = 22
    var primaryColor: Color = .secondary
    var backgroundColor: Color = .secondary.opacity(0.3)

    var autoCompleteThreshold: Float?
    var autoCompleteDuration: TimeInterval?

    var body: some View {
        ZStack {
            if let value {
                ZStack {
                    Circle()
                        .stroke(backgroundColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))

                    Circle()
                        .trim(from: 0, to: CGFloat(displayValue(for: value)))
                        .stroke(primaryColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(autoCompleteAnimation(for: value), value: value)
                }
                .frame(width: diameter, height: diameter)

            } else {
                IndeterminateSpinnerView(
                    diameter: diameter,
                    strokeWidth: strokeWidth,
                    primaryColor: NSColor(primaryColor),
                    backgroundColor: NSColor(backgroundColor)
                )
                .frame(width: diameter, height: diameter)
            }
        }
        .frame(width: diameter + strokeWidth * 2, height: diameter + strokeWidth * 2)
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

// We note a constant >10% CPU usage when using a SwiftUI rotation animation that
// repeats forever, while this implementation, using Core Animation, uses <1% CPU.
struct IndeterminateSpinnerView: NSViewRepresentable {
    var diameter: CGFloat
    var strokeWidth: CGFloat
    var primaryColor: NSColor
    var backgroundColor: NSColor

    func makeNSView(context _: Context) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        view.wantsLayer = true

        guard let viewLayer = view.layer else { return view }

        let fullPath = NSBezierPath(
            ovalIn: NSRect(x: 0, y: 0, width: diameter, height: diameter)
        ).cgPath

        let backgroundLayer = CAShapeLayer()
        backgroundLayer.path = fullPath
        backgroundLayer.strokeColor = backgroundColor.cgColor
        backgroundLayer.fillColor = NSColor.clear.cgColor
        backgroundLayer.lineWidth = strokeWidth
        viewLayer.addSublayer(backgroundLayer)

        let foregroundLayer = CAShapeLayer()

        foregroundLayer.frame = viewLayer.bounds
        foregroundLayer.path = fullPath
        foregroundLayer.strokeColor = primaryColor.cgColor
        foregroundLayer.fillColor = NSColor.clear.cgColor
        foregroundLayer.lineWidth = strokeWidth
        foregroundLayer.lineCap = .round
        foregroundLayer.strokeStart = 0
        foregroundLayer.strokeEnd = 0.15
        viewLayer.addSublayer(foregroundLayer)

        let rotationAnimation = CABasicAnimation(keyPath: "transform.rotation")
        rotationAnimation.fromValue = 0
        rotationAnimation.toValue = 2 * Double.pi
        rotationAnimation.duration = 1.0
        rotationAnimation.repeatCount = .infinity
        rotationAnimation.isRemovedOnCompletion = false

        foregroundLayer.add(rotationAnimation, forKey: "rotationAnimation")

        return view
    }

    func updateNSView(_: NSView, context _: Context) {}
}
