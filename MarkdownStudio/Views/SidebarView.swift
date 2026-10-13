import SwiftUI

enum SidebarTab: String, CaseIterable, Identifiable {
    case outline, files, search
    var id: Self { self }
    var title: String {
        switch self {
        case .outline: "Outline"
        case .files: "Files"
        case .search: "Search"
        }
    }
    var systemImage: String {
        switch self {
        case .outline: "list.bullet.indent"
        case .files: "folder"
        case .search: "magnifyingglass"
        }
    }
}

struct SidebarView: View {
    @Bindable var session: DocumentSession

    var body: some View {
        if session.isInWorkspace {
            VStack(spacing: 0) {
                Picker("Sidebar", selection: $session.sidebarTab) {
                    ForEach(SidebarTab.allCases) { tab in
                        Image(systemName: tab.systemImage).help(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                switch session.sidebarTab {
                case .outline: OutlineView(session: session)
                case .files: FilesView(session: session)
                case .search: FolderSearchView(session: session)
                }
            }
        } else {
            // A single file: just its outline, no folder tree.
            OutlineView(session: session)
        }
    }
}

// MARK: - Files

struct FilesView: View {
    let session: DocumentSession
    private var workspace: Workspace { Workspace.shared }
    @State private var renaming: FileNode?
    @State private var newName = ""

    var body: some View {
        if let root = workspace.rootURL {
            List {
                Section {
                    if workspace.tree.isEmpty && !workspace.isLoading {
                        Text("No Markdown files in this folder").foregroundStyle(.secondary)
                    }
                    OutlineGroup(workspace.tree, children: \.children) { node in
                        row(node)
                    }
                } header: {
                    HStack {
                        Text(root.lastPathComponent).lineLimit(1)
                        Spacer()
                        folderMenu(root)
                    }
                }
            }
            .listStyle(.sidebar)
            .dropDestination(for: URL.self) { urls, _ in
                urls.forEach { workspace.move($0, to: root.appendingPathComponent($0.lastPathComponent)) }
                return true
            }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Rename") {
                    if let node = renaming { workspace.rename(node.url, to: newName) }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            } message: {
                Text("Enter a new name for “\(renaming?.name ?? "")”.")
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "folder").font(.largeTitle).foregroundStyle(.secondary)
                Text("Open a folder to browse its Markdown files here.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Open Folder…") { workspace.chooseFolder() }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(_ node: FileNode) -> some View {
        let isCurrent = session.fileURL?.standardizedFileURL == node.url.standardizedFileURL
        return Label {
            Text(node.isDirectory ? node.name : (node.name as NSString).deletingPathExtension)
                .fontWeight(isCurrent ? .semibold : .regular)
                .lineLimit(1)
        } icon: {
            Image(systemName: node.isDirectory ? "folder" : "doc.text")
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { if !node.isDirectory { WorkspaceNavigator.open(node.url) } }
        .help(workspace.relativePath(of: node.url))
        .draggable(node.url)
        .dropDestination(for: URL.self) { urls, _ in
            let folder = node.isDirectory ? node.url : node.url.deletingLastPathComponent()
            urls.forEach { workspace.move($0, to: folder.appendingPathComponent($0.lastPathComponent)) }
            return true
        }
        .contextMenu {
            let folder = node.isDirectory ? node.url : node.url.deletingLastPathComponent()
            Button("New File") { workspace.createFile(in: folder) }
            Button("New Folder") { workspace.createFolder(in: folder) }
            Divider()
            Button("Rename…") {
                newName = node.isDirectory ? node.name : (node.name as NSString).deletingPathExtension
                renaming = node
            }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
            Divider()
            Button("Move to Trash", role: .destructive) { workspace.trash(node.url) }
        }
    }

    private func folderMenu(_ root: URL) -> some View {
        Menu {
            Button("New File") { workspace.createFile(in: root) }
            Button("New Folder") { workspace.createFolder(in: root) }
            Divider()
            Button("Open Different Folder…") { workspace.chooseFolder() }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([root]) }
            Button("Close Folder") { workspace.close() }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Search

struct FolderSearchView: View {
    let session: DocumentSession
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @FocusState private var fieldFocused: Bool
    private var workspace: Workspace { Workspace.shared }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Find in Folder", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
                .disabled(workspace.rootURL == nil)
            if workspace.rootURL == nil {
                VStack(spacing: 12) {
                    Text("Open a folder to search all of its Markdown files.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Open Folder…") { workspace.chooseFolder() }
                }
                .padding()
                .frame(maxHeight: .infinity)
            } else if results.isEmpty {
                Text(query.count < 2 ? "Type at least two characters" : (isSearching ? "Searching…" : "No results"))
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(grouped, id: \.0) { url, matches in
                        Section(workspace.relativePath(of: url)) {
                            ForEach(matches) { result in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("\(result.line + 1)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(minWidth: 22, alignment: .trailing)
                                    Text(highlighted(result.text)).lineLimit(2)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { WorkspaceNavigator.open(result.url, line: result.line) }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .task(id: query) {
            guard query.count >= 2 else { results = []; return }
            isSearching = true
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let files = workspace.files
            let needle = query
            let found = await Task.detached(priority: .userInitiated) { Workspace.search(needle, in: files) }.value
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
        .onChange(of: session.searchFocusRequest, initial: true) { _, _ in
            DispatchQueue.main.async { fieldFocused = true }
        }
    }

    private var grouped: [(URL, [SearchResult])] {
        var order: [URL] = []
        var groups: [URL: [SearchResult]] = [:]
        for result in results {
            if groups[result.url] == nil { order.append(result.url) }
            groups[result.url, default: []].append(result)
        }
        return order.map { ($0, groups[$0]!) }
    }

    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        if let range = attributed.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed[range].font = .body.bold()
            attributed[range].backgroundColor = .yellow.opacity(0.35)
        }
        return attributed
    }
}
