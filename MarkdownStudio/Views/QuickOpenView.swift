import SwiftUI

/// ⌘P: type a few letters of any file in the open folder (or a recent file).
struct QuickOpenView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool
    private var workspace: Workspace { Workspace.shared }

    private struct Candidate: Identifiable {
        var url: URL
        var path: String
        var id: URL { url }
    }

    private var candidates: [Candidate] {
        var seen = Set<URL>()
        var all: [Candidate] = []
        for url in workspace.files + NSDocumentController.shared.recentDocumentURLs where !seen.contains(url.standardizedFileURL) {
            seen.insert(url.standardizedFileURL)
            let isInFolder = workspace.rootURL.map { url.path.hasPrefix($0.path + "/") } ?? false
            let path = isInFolder ? workspace.relativePath(of: url)
                : (url.path as NSString).abbreviatingWithTildeInPath
            all.append(Candidate(url: url, path: path))
        }
        return all
    }

    private var matches: [Candidate] {
        let all = candidates
        guard !query.isEmpty else { return Array(all.prefix(12)) }
        return all
            .compactMap { c in FuzzyMatcher.score(query, in: c.path, fileName: c.url.lastPathComponent).map { (c, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(12)
            .map(\.0)
    }

    var body: some View {
        let results = matches
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(workspace.rootURL == nil ? "Open a recent file" : "Open a file in \(workspace.rootURL!.lastPathComponent)",
                          text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { open(results) }
                    .onKeyPress(.downArrow) { selection = min(selection + 1, max(results.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
                    .onKeyPress(.escape) { dismissWindow(id: QuickOpen.id); return .handled }
            }
            .padding(14)
            Divider()
            if results.isEmpty {
                Text(workspace.rootURL == nil && query.isEmpty ? "No recent files. Use File → Open Folder… to search a folder." : "No matching files")
                    .foregroundStyle(.secondary)
                    .padding(20)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, candidate in
                            HStack(spacing: 10) {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(index == selection ? Color.white : .secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(candidate.url.lastPathComponent).lineLimit(1)
                                    Text(candidate.path)
                                        .font(.caption)
                                        .foregroundStyle(index == selection ? Color.white.opacity(0.8) : .secondary)
                                        .lineLimit(1)
                                        .truncationMode(.head)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(index == selection ? Color.white : .primary)
                            .background(index == selection ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                            .onTapGesture { selection = index; open(results) }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 360)
            }
        }
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: query) { selection = 0 }
        .onAppear {
            query = ""
            selection = 0
            focused = true
        }
        .background(WindowAccessor { window in
            QuickOpen.configure(window)
        })
    }

    private func open(_ results: [Candidate]) {
        guard results.indices.contains(selection) else { return }
        let url = results[selection].url
        dismissWindow(id: QuickOpen.id)
        WorkspaceNavigator.open(url)
    }
}

enum QuickOpen {
    static let id = "quickopen"
    private static var observer: NSObjectProtocol?
    private static weak var window: NSWindow?

    /// Closes the palette when it loses focus, like Spotlight.
    static func configure(_ window: NSWindow) {
        guard observer == nil else { return }
        window.isMovableByWindowBackground = true
        Self.window = window
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
                Self.window?.close()
                if let observer { NotificationCenter.default.removeObserver(observer) }
                observer = nil
            }
        }
    }
}
