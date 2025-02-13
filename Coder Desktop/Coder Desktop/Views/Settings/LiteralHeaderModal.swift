import SwiftUI

struct LiteralHeaderModal: View {
    var existingHeader: LiteralHeader?

    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var header: String = ""
    @State private var value: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Header", text: $header)
                    TextField("Value", text: $value)
                }
            }.formStyle(.grouped).scrollDisabled(true).padding(.horizontal)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: { dismiss() }).keyboardShortcut(.cancelAction)
                Button(existingHeader == nil ? "Add" : "Save", action: submit)
                    .keyboardShortcut(.defaultAction)
            }.padding(20)
        }.onAppear {
            if let existingHeader {
                header = existingHeader.header
                value = existingHeader.value
            }
        }
    }

    func submit() {
        defer { dismiss() }
        if let existingHeader {
            state.literalHeaders.removeAll { $0 == existingHeader }
        }
        let newHeader = LiteralHeader(header: header, value: value)
        if !state.literalHeaders.contains(newHeader) {
            state.literalHeaders.append(newHeader)
        }
    }
}
