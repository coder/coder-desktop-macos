import SwiftUI

struct ResponsiveLink: View {
    let title: String
    let destination: URL

    @State private var isHovered = false
    @State private var isPressed = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Text(title)
            .font(.subheadline)
            .foregroundColor(isPressed ? .red : .blue)
            .underline(isHovered, color: isPressed ? .red : .blue)
            .onHoverWithPointingHand { hovering in
                isHovered = hovering
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPressed = true
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPressed = false
                        }
                        openURL(destination)
                    }
            )
    }
}
