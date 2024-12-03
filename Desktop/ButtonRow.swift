import SwiftUI

struct ButtonRowView<Label: View>: View {
    @State private var isSelected: Bool = false
    @ViewBuilder var label: () -> Label

    var body: some View {
        HStack(spacing: 0) {
            label()
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(isSelected ? Color.white : .primary)
        .background(isSelected ? Color.accentColor.opacity(0.8) : .clear)
        .clipShape(.rect(cornerRadius: 4))
        .onHover { hovering in isSelected = hovering }
    }
}
