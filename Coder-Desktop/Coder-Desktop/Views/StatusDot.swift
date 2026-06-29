import SwiftUI

struct StatusDot: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 12, height: 12)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
    }
}
