import SwiftUI

struct LiteralHeadersSection<VPN: VPNService>: View {
    @EnvironmentObject var vpn: VPN
    @EnvironmentObject var state: AppState

    @State private var selectedHeader: LiteralHeader.ID?
    @State private var editingHeader: LiteralHeader?
    @State private var addingNewHeader = false

    let inspection = Inspection<Self>()

    var body: some View {
        Section {
            Toggle(isOn: $state.useLiteralHeaders) {
                Text("HTTP Headers")
                Text("When enabled, these headers will be included on all outgoing HTTP requests.")
                if vpn.state != .disabled { Text("Cannot be modified while Coder VPN is enabled.") }
            }
            .controlSize(.large)

            Table(state.literalHeaders, selection: $selectedHeader) {
                TableColumn("Header", value: \.header)
                TableColumn("Value", value: \.value)
            }.opacity(state.useLiteralHeaders ? 1 : 0.5)
                .frame(minWidth: 400, minHeight: 200)
                .padding(.bottom, 25)
                .overlay(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Divider()
                        HStack(spacing: 0) {
                            Button {
                                addingNewHeader = true
                            } label: {
                                Image(systemName: "plus")
                                    .frame(width: 24, height: 24)
                            }
                            Divider()
                            Button {
                                state.literalHeaders.removeAll { $0.id == selectedHeader }
                                selectedHeader = nil
                            } label: {
                                Image(systemName: "minus")
                                    .frame(width: 24, height: 24)
                            }.disabled(selectedHeader == nil)
                        }
                        .buttonStyle(.borderless)
                    }
                    .background(.primary.opacity(0.04))
                    .fixedSize(horizontal: false, vertical: true)
                }
                .background(.primary.opacity(0.04))
                .contextMenu(forSelectionType: LiteralHeader.ID.self, menu: { _ in },
                             primaryAction: { selectedHeaders in
                                 if let firstHeader = selectedHeaders.first {
                                     editingHeader = state.literalHeaders.first(where: { $0.id == firstHeader })
                                 }
                             })
                .disabled(!state.useLiteralHeaders)
        }
        .sheet(isPresented: $addingNewHeader) {
            LiteralHeaderModal()
        }
        .sheet(item: $editingHeader) { header in
            LiteralHeaderModal(existingHeader: header)
        }.onTapGesture {
            selectedHeader = nil
        }.disabled(vpn.state != .disabled)
        .onReceive(inspection.notice) { inspection.visit(self, $0) } // ViewInspector
    }
}
