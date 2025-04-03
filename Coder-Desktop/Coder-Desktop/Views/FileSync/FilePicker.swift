import CoderSDK
import Foundation
import SwiftUI

struct FilePicker: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var model: FilePickerModel
    @State private var selection: FilePickerItemModel.ID?

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
            if model.isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.large)
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
                    ForEach(model.rootFiles) { rootItem in
                        FilePickerItem(item: rootItem)
                    }
                }.contextMenu(
                    forSelectionType: FilePickerItemModel.ID.self,
                    menu: { _ in },
                    primaryAction: { selections in
                        // Per the type of `selection`, this will only ever be a set of
                        // one item.
                        let files = model.findFilesByIds(ids: selections)
                        files.forEach { file in withAnimation { file.isExpanded.toggle() } }
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
        let files = model.findFilesByIds(ids: [selection])
        if let file = files.first {
            outputAbsPath = file.absolute_path
        }
        dismiss()
    }
}

@MainActor
class FilePickerModel: ObservableObject {
    @Published var rootFiles: [FilePickerItemModel] = []
    @Published var isLoading: Bool = false
    @Published var error: ClientError?

    let client: Client

    init(host: String) {
        client = Client(url: URL(string: "http://\(host):4")!)
    }

    func loadRoot() {
        error = nil
        isLoading = true
        Task {
            defer { isLoading = false }
            do throws(ClientError) {
                rootFiles = try await client
                    .listAgentDirectory(.init(path: [], relativity: .root))
                    .toModels(client: Binding(get: { self.client }, set: { _ in }), path: [])
            } catch {
                self.error = error
            }
        }
    }

    func findFilesByIds(ids: Set<FilePickerItemModel.ID>) -> [FilePickerItemModel] {
        var result: [FilePickerItemModel] = []

        for id in ids {
            if let file = findFileByPath(path: id, in: rootFiles) {
                result.append(file)
            }
        }

        return result
    }

    private func findFileByPath(path: [String], in files: [FilePickerItemModel]?) -> FilePickerItemModel? {
        guard let files, !path.isEmpty else { return nil }

        if let file = files.first(where: { $0.name == path[0] }) {
            if path.count == 1 {
                return file
            }
            // Array slices are just views, so this isn't expensive
            return findFileByPath(path: Array(path[1...]), in: file.contents)
        }

        return nil
    }
}

struct FilePickerItem: View {
    @ObservedObject var item: FilePickerItemModel

    var body: some View {
        Group {
            if item.dir {
                directory
            } else {
                Label(item.name, systemImage: "doc")
                    .help(item.absolute_path)
                    .selectionDisabled()
                    .foregroundColor(.secondary)
            }
        }
    }

    private var directory: some View {
        DisclosureGroup(isExpanded: $item.isExpanded) {
            if let contents = item.contents {
                ForEach(contents) { item in
                    FilePickerItem(item: item)
                }
            }
        } label: {
            Label {
                Text(item.name)
                ZStack {
                    ProgressView().controlSize(.small).opacity(item.isLoading && item.error == nil ? 1 : 0)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .opacity(item.error != nil ? 1 : 0)
                }
            } icon: {
                Image(systemName: "folder")
            }.help(item.error != nil ? item.error!.description : item.absolute_path)
        }
    }
}

@MainActor
class FilePickerItemModel: Identifiable, ObservableObject {
    nonisolated let id: [String]
    let name: String
    // Components of the path as an array
    let path: [String]
    let absolute_path: String
    let dir: Bool

    // This being a binding is pretty important performance-wise, as it's a struct
    // that would otherwise be recreated every time the the item row is rendered.
    // Removing the binding results in very noticeable lag when scrolling a file tree.
    @Binding var client: Client

    @Published var contents: [FilePickerItemModel]?
    @Published var isLoading = false
    @Published var error: ClientError?
    @Published private var innerIsExpanded = false
    var isExpanded: Bool {
        get { innerIsExpanded }
        set {
            if !newValue {
                withAnimation { self.innerIsExpanded = false }
            } else {
                Task {
                    self.loadContents()
                }
            }
        }
    }

    init(
        name: String,
        client: Binding<Client>,
        absolute_path: String,
        path: [String],
        dir: Bool = false,
        contents: [FilePickerItemModel]? = nil
    ) {
        self.name = name
        _client = client
        self.path = path
        self.dir = dir
        self.absolute_path = absolute_path
        self.contents = contents

        // Swift Arrays are COW
        id = path
    }

    func loadContents() {
        self.error = nil
        withAnimation { isLoading = true }
        Task {
            defer {
                withAnimation {
                    isLoading = false
                    innerIsExpanded = true
                }
            }
            do throws(ClientError) {
                contents = try await client
                    .listAgentDirectory(.init(path: path, relativity: .root))
                    .toModels(client: $client, path: path)
            } catch {
                self.error = error
            }
        }
    }
}

extension LSResponse {
    @MainActor
    func toModels(client: Binding<Client>, path: [String]) -> [FilePickerItemModel] {
        contents.compactMap { file in
            // Filter dotfiles from the picker
            guard !file.name.hasPrefix(".") else { return nil }

            return FilePickerItemModel(
                name: file.name,
                client: client,
                absolute_path: file.absolute_path_string,
                path: path + [file.name],
                dir: file.is_dir,
                contents: nil
            )
        }
    }
}
