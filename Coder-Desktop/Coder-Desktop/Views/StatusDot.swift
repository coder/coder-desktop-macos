import SwiftUI

struct StatusDot: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.4))
                .frame(width: 12, height: 12)
            Circle()
                .fill(color.opacity(1.0))
                .frame(width: 7, height: 7)
        }
    }
}
