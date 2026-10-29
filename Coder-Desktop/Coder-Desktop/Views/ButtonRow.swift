import SwiftUI

struct ButtonRowView<Label: View>: View {
    init(highlightColor: Color = .accentColor, isSelected: Bool = false, @ViewBuilder label: () -> Label) {
        self.highlightColor = highlightColor
        _isSelected = State(initialValue: isSelected)
        self.label = label()
    }

    let highlightColor: Color
    @State private var isSelected: Bool
    let label: Label

    var body: some View {
        HStack(spacing: 0) {
            label
            Spacer()
        }
        .padding(.horizontal, Theme.Size.trayPadding)
        .frame(minHeight: 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(isSelected ? .white : .primary)
        .background(isSelected ? highlightColor.opacity(0.8) : .clear)
        .clipShape(.rect(cornerRadius: Theme.Size.rectCornerRadius))
        .onHover { hovering in isSelected = hovering }
    }
}
