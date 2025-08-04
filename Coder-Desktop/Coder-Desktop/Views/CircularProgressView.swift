import SwiftUI

struct CircularProgressView: View {
    let value: Float?

    var strokeWidth: CGFloat
    var diameter: CGFloat
    var primaryColor: Color = .secondary
    var backgroundColor: Color = .secondary.opacity(0.3)

    private var autoComplete: (threshold: Float, duration: TimeInterval)?
    private var autoStart: (until: Float, duration: TimeInterval)?

    @State private var currentProgress: Float = 0

    init(value: Float? = nil,
         strokeWidth: CGFloat = 4,
         diameter: CGFloat = 22)
    {
        self.value = value
        self.strokeWidth = strokeWidth
        self.diameter = diameter
    }

    var body: some View {
        ZStack {
            if let value {
                ZStack {
                    Circle()
                        .stroke(backgroundColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))

                    Circle()
                        .trim(from: 0, to: CGFloat(displayValue(for: currentProgress)))
                        .stroke(primaryColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: diameter, height: diameter)
                .onAppear {
                    if let autoStart, value == 0 {
                        withAnimation(.easeOut(duration: autoStart.duration)) {
                            currentProgress = autoStart.until
                        }
                    }
                }
                .onChange(of: value) {
                    withAnimation(currentAnimation(for: value)) {
                        currentProgress = value
                    }
                }
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
        if let threshold = autoComplete?.threshold,
           value >= threshold, value < 1.0
        {
            return 1.0
        }
        return value
    }

    private func currentAnimation(for value: Float) -> Animation {
        guard let autoComplete,
              value >= autoComplete.threshold, value < 1.0
        else {
            // Use the auto-start animation if it's running, otherwise default.
            if let autoStart {
                return .easeOut(duration: autoStart.duration)
            }
            return .default
        }

        return .easeOut(duration: autoComplete.duration)
    }
}

extension CircularProgressView {
    func autoComplete(threshold: Float, duration: TimeInterval) -> CircularProgressView {
        var view = self
        view.autoComplete = (threshold: threshold, duration: duration)
        return view
    }

    func autoStart(until value: Float, duration: TimeInterval) -> CircularProgressView {
        var view = self
        view.autoStart = (until: value, duration: duration)
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
