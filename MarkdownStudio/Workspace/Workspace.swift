import AppKit
import Observation

nonisolated struct FileNode: Identifiable, Hashable, Sendable {
    var url: URL
    var name: String
    var isDirectory: Bool
    /// nil for files, so `List(children:)` shows no disclosure triangle.
    var children: [FileNode]?
    var id: URL { url }
}

nonisolated struct SearchResult: Identifiable, Hashable, Sendable {
    var url: URL
    var line: Int
    var text: String
    var id: String { "\(url.path):\(line)" }
}

/// The folder opened with File → Open Folder…: its Markdown files for the
/// sidebar, Quick Open and Find in Folder. Shared by all windows.
@Observable
final class Workspace {
    static let shared = Workspace()

    private(set) var rootURL: URL?
    private(set) var tree: [FileNode] = []
    /// Every Markdown file, for Quick Open.
    private(set) var files: [URL] = []
    private(set) var isLoading = false

    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var openStartingFileWhenLoaded = false
    private static let rootKey = "workspaceFolder"
    nonisolated static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "txt"]
    nonisolated private static let skippedFolders: Set<String> = ["node_modules", ".git", "build", "DerivedData", "Pods", ".build", "dist"]

    private init() {
        if let path = UserDefaults.standard.string(forKey: Self.rootKey) {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                open(URL(filePath: path, directoryHint: .isDirectory))
            }
        }
    }

    // MARK: - Opening

    /// Opens a folder. With `showingAFile`, a window with a file from the
    /// folder (and the folder tree in its sidebar) appears once it's scanned.
    func open(_ url: URL, showingAFile: Bool = false) {
        openStartingFileWhenLoaded = showingAFile
        rootURL = url.standardizedFileURL
        UserDefaults.standard.set(url.path, forKey: Self.rootKey)
        watcher = FolderWatcher(url: url) { [weak self] in self?.scheduleReload() }
        reload()
    }

    func close() {
        rootURL = nil
        tree = []
        files = []
        watcher = nil
        UserDefaults.standard.removeObject(forKey: Self.rootKey)
    }

    /// Shows an open panel for choosing a folder. Returns true when one was chosen.
    @discardableResult
    func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        panel.message = "Choose a folder of Markdown files"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        open(url, showingAFile: true)
        return true
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    func reload() {
        guard let root = rootURL else { return }
        isLoading = true
        Task {
            let (tree, files) = await Task.detached(priority: .userInitiated) { Self.scan(root) }.value
            guard self.rootURL == root else { return }
            if self.tree != tree { self.tree = tree }
            if self.files != files { self.files = files }
            self.isLoading = false
            if self.openStartingFileWhenLoaded {
                self.openStartingFileWhenLoaded = false
                self.showFolderWindow()
            }
        }
    }

    /// Whether a file lives inside the open folder.
    func contains(_ url: URL?) -> Bool {
        guard let url, let rootURL else { return false }
        return Self.isPath(url, inside: rootURL)
    }

    /// Compares real paths, so folders reached through a symlink still match.
    /// The parent folder is resolved separately because resolving only works
    /// for paths that exist (a file may not be saved yet).
    nonisolated static func isPath(_ url: URL, inside folder: URL) -> Bool {
        let root = folder.resolvingSymlinksInPath().path
        let resolved = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).path
        return resolved.hasPrefix(root + "/")
    }

    /// Brings forward a window that shows a file from this folder, or opens one:
    /// README.md or index.md at the top level, otherwise the first file. An
    /// empty folder gets a new untitled document.
    func showFolderWindow() {
        if let session = WorkspaceNavigator.openSessions.first(where: { contains($0.fileURL) }) {
            session.showSidebar(.files)
            session.window?.makeKeyAndOrderFront(nil)
            return
        }
        guard let root = rootURL else { return }
        let topLevel = files.filter { $0.deletingLastPathComponent().standardizedFileURL.path == root.path }
        let preferred = topLevel.first { ["readme.md", "index.md"].contains($0.lastPathComponent.lowercased()) }
            ?? topLevel.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }.first
            ?? files.first
        if let preferred {
            WorkspaceNavigator.open(preferred)
        } else {
            WorkspaceNavigator.newUntitledInWorkspace()
        }
    }

    /// Folders (that contain Markdown somewhere) and Markdown files, sorted like Finder.
    nonisolated static func scan(_ root: URL, limit: Int = 5000) -> ([FileNode], [URL]) {
        var files: [URL] = []
        func children(of folder: URL, depth: Int) -> [FileNode] {
            guard depth < 12, files.count < limit else { return [] }
            let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
            let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants])) ?? []
            var nodes: [FileNode] = []
            for url in urls {
                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true, values?.isPackage != true {
                    guard !skippedFolders.contains(url.lastPathComponent) else { continue }
                    let sub = children(of: url, depth: depth + 1)
                    if !sub.isEmpty {
                        nodes.append(FileNode(url: url, name: url.lastPathComponent, isDirectory: true, children: sub))
                    }
                } else if markdownExtensions.contains(url.pathExtension.lowercased()), files.count < limit {
                    files.append(url)
                    nodes.append(FileNode(url: url, name: url.lastPathComponent, isDirectory: false, children: nil))
                }
            }
            return nodes.sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
        let tree = children(of: root, depth: 0)
        return (tree, files)
    }

    func relativePath(of url: URL) -> String {
        guard let root = rootURL?.resolvingSymlinksInPath().path else { return url.lastPathComponent }
        let path = url.resolvingSymlinksInPath().path
        guard path.hasPrefix(root + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(root.count + 1))
    }

    // MARK: - Search

    nonisolated static func search(_ query: String, in files: [URL], limit: Int = 300) -> [SearchResult] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2 else { return [] }
        var results: [SearchResult] = []
        for url in files {
            guard let data = try? Data(contentsOf: url), let text = try? MarkdownDocument.decode(data) else { continue }
            var perFile = 0
            for (index, line) in text.components(separatedBy: "\n").enumerated() {
                guard line.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { continue }
                results.append(SearchResult(url: url, line: index, text: line.trimmingCharacters(in: .whitespaces)))
                perFile += 1
                if perFile >= 20 || results.count >= limit { break }
            }
            if results.count >= limit { break }
        }
        return results
    }

    // MARK: - File operations

    /// Creates "Untitled.md" (or "Untitled 2.md", …) in `folder` and opens it.
    func createFile(in folder: URL) {
        var url = folder.appendingPathComponent("Untitled.md")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("Untitled \(n).md")
            n += 1
        }
        do {
            try Data("# \(url.deletingPathExtension().lastPathComponent)\n\n".utf8).write(to: url)
            reload()
            WorkspaceNavigator.open(url)
        } catch {
            NSApp.presentError(error)
        }
    }

    func createFolder(in folder: URL) {
        var url = folder.appendingPathComponent("New Folder", isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("New Folder \(n)", isDirectory: true)
            n += 1
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            // Empty folders are hidden from the tree, so give it a first note.
            try Data("# Notes\n\n".utf8).write(to: url.appendingPathComponent("Notes.md"))
            reload()
        } catch {
            NSApp.presentError(error)
        }
    }

    /// Moves or renames through NSFileCoordinator, so open documents follow the file.
    /// Folders `item` can be moved into from the "Move To" menu: the open folder and
    /// every folder in it, except the item's current folder, the item itself and
    /// (for folders) anything inside it. Sorted by relative path.
    nonisolated static func moveTargets(for item: URL, root: URL, tree: [FileNode]) -> [URL] {
        var folders = [root]
        func collect(_ nodes: [FileNode]) {
            for node in nodes where node.isDirectory {
                folders.append(node.url)
                collect(node.children ?? [])
            }
        }
        collect(tree)
        let itemPath = item.standardizedFileURL.path
        let parentPath = item.deletingLastPathComponent().standardizedFileURL.path
        return folders.filter { folder in
            let path = folder.standardizedFileURL.path
            return path != parentPath && path != itemPath && !path.hasPrefix(itemPath + "/")
        }
    }

    func move(_ source: URL, to destination: URL) {
        guard source.standardizedFileURL != destination.standardizedFileURL else { return }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            let alert = NSAlert()
            alert.messageText = "“\(destination.lastPathComponent)” already exists"
            alert.informativeText = "Choose a different name or folder."
            alert.runModal()
            return
        }
        var coordinationError: NSError?
        var moveError: Error?
        // The coordinator that performs the write must also announce the move,
        // or open documents (file presenters) don't learn their new URL.
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: source, options: .forMoving,
                               writingItemAt: destination, options: .forReplacing,
                               error: &coordinationError) { from, to in
            coordinator.item(at: from, willMoveTo: to)
            do {
                try FileManager.default.moveItem(at: from, to: to)
                coordinator.item(at: from, didMoveTo: to)
            } catch {
                moveError = error
            }
        }
        if let error = coordinationError ?? moveError { NSApp.presentError(error) }
        reload()
    }

    func rename(_ url: URL, to name: String) {
        var newName = name.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, !newName.contains("/") else { return }
        if !url.hasDirectoryPath, (newName as NSString).pathExtension.isEmpty { newName += "." + url.pathExtension }
        move(url, to: url.deletingLastPathComponent().appendingPathComponent(newName))
    }

    func trash(_ url: URL) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            reload()
        } catch {
            NSApp.presentError(error)
        }
    }
}

/// Opens files from the sidebar, Quick Open and search, optionally at a line.
enum WorkspaceNavigator {
    /// Line jumps and heading anchors waiting for a document window to appear.
    static var pendingLines: [String: Int] = [:]
    static var pendingAnchors: [String: String] = [:]
    /// Sessions of open documents, by file path.
    private static var sessions: [String: WeakSession] = [:]

    private struct WeakSession { weak var session: DocumentSession? }

    /// Set before creating an untitled document that belongs to the open folder.
    static var nextUntitledBelongsToWorkspace = false

    static var openSessions: [DocumentSession] {
        sessions.values.compactMap(\.session)
    }

    static func newUntitledInWorkspace() {
        nextUntitledBelongsToWorkspace = true
        NSDocumentController.shared.newDocument(nil)
    }

    static func register(_ session: DocumentSession, for url: URL?) {
        sessions = sessions.filter { $0.value.session != nil && $0.value.session !== session }
        guard let url else {
            sessions["untitled:\(ObjectIdentifier(session).hashValue)"] = WeakSession(session: session)
            return
        }
        let key = url.standardizedFileURL.path
        sessions[key] = WeakSession(session: session)
        if let line = pendingLines.removeValue(forKey: key) {
            DispatchQueue.main.async { session.goToLine(line + 1) }
        }
        if let anchor = pendingAnchors.removeValue(forKey: key) {
            DispatchQueue.main.async { reveal(anchor, in: session) }
        }
    }

    /// Scrolls to the heading whose ID is `anchor`.
    private static func reveal(_ anchor: String, in session: DocumentSession) {
        if let heading = OutlineParser.parse(session.text).first(where: { $0.anchor == anchor }) {
            session.jump(toLine: heading.line)
        }
    }

    static func open(_ url: URL, line: Int? = nil, anchor: String? = nil) {
        let key = url.standardizedFileURL.path
        if let session = sessions[key]?.session {
            session.window?.makeKeyAndOrderFront(nil)
            if let line { session.goToLine(line + 1) }
            if let anchor { reveal(anchor, in: session) }
            return
        }
        if let line { pendingLines[key] = line }
        if let anchor { pendingAnchors[key] = anchor }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }
}
