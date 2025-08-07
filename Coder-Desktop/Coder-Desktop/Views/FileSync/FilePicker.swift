import CoderSDK
import Foundation
import SwiftUI

struct FilePicker: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var model: FilePickerModel
    @State private var selection: FilePickerEntryModel?

    @Binding var outputAbsPath: String

    let inspection = Inspection<Self>()

    init(
        host: String,
        outputAbsPath: Binding<String>
    ) {
        _model = StateObject(wrappedValue: FilePickerModel(host: host))
        _outputAbsPath = outputAbsPath
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.rootIsLoading {
                Spacer()
                CircularProgressView(value: nil)
                Spacer()
            } else if let loadError = model.error {
                Text("\(loadError.description)")
                    .font(.headline)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                List(selection: $selection) {
                    ForEach(model.rootEntries) { entry in
                        FilePickerEntry(entry: entry).tag(entry)
                    }
                }.contextMenu(
                    forSelectionType: FilePickerEntryModel.self,
                    menu: { _ in },
                    primaryAction: { selections in
                        // Per the type of `selection`, this will only ever be a set of
                        // one entry.
                        selections.forEach { entry in withAnimation { entry.isExpanded.toggle() } }
                    }
                ).listStyle(.sidebar)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: { dismiss() }).keyboardShortcut(.cancelAction)
                Button("Select", action: submit).keyboardShortcut(.defaultAction).disabled(selection == nil)
            }.padding(20)
        }
        .onAppear {
            model.loadRoot()
        }
        .onReceive(inspection.notice) { inspection.visit(self, $0) } // ViewInspector
    }

    private func submit() {
        guard let selection else { return }
        outputAbsPath = selection.absolute_path
        dismiss()
    }
}

@MainActor
class FilePickerModel: ObservableObject {
    @Published private(set) var rootEntries: [FilePickerEntryModel] = []
    @Published private(set) var rootIsLoading: Bool = false
    @Published private(set) var error: SDKError?

    // It's important that `AgentClient` is a reference type (class)
    // as we were having performance issues with a struct (unless it was a binding).
    let client: AgentClient

    init(host: String) {
        client = AgentClient(agentHost: host)
    }

    func loadRoot() {
        error = nil
        rootIsLoading = true
        Task {
            defer { rootIsLoading = false }
            do throws(SDKError) {
                rootEntries = try await client
                    .listAgentDirectory(.init(path: [], relativity: .root))
                    .toModels(client: client)
            } catch {
                self.error = error
            }
        }
    }
}

struct FilePickerEntry: View {
    @ObservedObject var entry: FilePickerEntryModel

    var body: some View {
        Group {
            if entry.dir {
                directory
            } else {
                Label(entry.name, systemImage: "doc")
                    .help(entry.absolute_path)
                    .selectionDisabled()
                    .foregroundColor(.secondary)
            }
        }
    }

    private var directory: some View {
        DisclosureGroup(isExpanded: $entry.isExpanded) {
            if let entries = entry.entries {
                ForEach(entries) { entry in
                    FilePickerEntry(entry: entry).tag(entry)
                }
            }
        } label: {
            Label {
                Text(entry.name)
                    // The NSView within the CircularProgressView breaks
                    // the chevron alignment within the DisclosureGroup view.
                    // So, we overlay the progressview with a manual offset
                    .padding(.trailing, 20)
                    .overlay(alignment: .trailing) {
                        ZStack {
                            CircularProgressView(value: nil, strokeWidth: 2, diameter: 10)
                                .opacity(entry.isLoading && entry.error == nil ? 1 : 0)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .opacity(entry.error != nil ? 1 : 0)
                        }
                    }
            } icon: {
                Image(systemName: "folder")
            }.help(entry.error != nil ? entry.error!.description : entry.absolute_path)
        }
    }
}

@MainActor
class FilePickerEntryModel: Identifiable, Hashable, ObservableObject {
    nonisolated let id: [String]
    let name: String
    // Components of the path as an array
    let path: [String]
    let absolute_path: String
    let dir: Bool

    let client: AgentClient

    @Published private(set) var entries: [FilePickerEntryModel]?
    @Published private(set) var isLoading = false
    @Published private(set) var error: SDKError?
    @Published private var innerIsExpanded = false
    var isExpanded: Bool {
        get { innerIsExpanded }
        set {
            if !newValue {
                withAnimation { self.innerIsExpanded = false }
            } else {
                Task {
                    self.loadEntries()
                }
            }
        }
    }

    init(
        name: String,
        client: AgentClient,
        absolute_path: String,
        path: [String],
        dir: Bool = false,
        entries: [FilePickerEntryModel]? = nil
    ) {
        self.name = name
        self.client = client
        self.path = path
        self.dir = dir
        self.absolute_path = absolute_path
        self.entries = entries

        // Swift Arrays are copy on write
        id = path
    }

    func loadEntries() {
        self.error = nil
        withAnimation { isLoading = true }
        Task {
            defer {
                withAnimation {
                    isLoading = false
                    innerIsExpanded = true
                }
            }
            do throws(SDKError) {
                entries = try await client
                    .listAgentDirectory(.init(path: path, relativity: .root))
                    .toModels(client: client)
            } catch {
                self.error = error
            }
        }
    }

    nonisolated static func == (lhs: FilePickerEntryModel, rhs: FilePickerEntryModel) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension LSResponse {
    @MainActor
    func toModels(client: AgentClient) -> [FilePickerEntryModel] {
        contents.compactMap { entry in
            // Filter dotfiles from the picker
            guard !entry.name.hasPrefix(".") else { return nil }

            return FilePickerEntryModel(
                name: entry.name,
                client: client,
                absolute_path: entry.absolute_path_string,
                path: self.absolute_path + [entry.name],
                dir: entry.is_dir,
                entries: nil
            )
        }
    }
}
