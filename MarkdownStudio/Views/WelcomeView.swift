import SwiftUI

/// Shown at launch: create a document, open one, or pick a recent file.
struct WelcomeView: View {
    @Environment(\.newDocument) private var newDocument
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var recents: [URL] = []
    @State private var isDefaultApp = true
    @State private var defaultAppError: String?

    var body: some View {
        HStack(spacing: 0) {
            actions
                .frame(width: 320)
            Divider()
            recentFiles
                .frame(width: 300)
        }
        .frame(height: 400)
        .onAppear {
            WelcomeWindow.openWindow = openWindow
            refresh()
        }
    }

    // MARK: - Left: app and actions

    private var actions: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Markdown Studio")
                .font(.largeTitle.bold())
                .padding(.top, 8)
            Text("Write and preview Markdown side by side")
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            VStack(spacing: 8) {
                actionButton("New Document", systemImage: "doc.badge.plus", shortcut: "⌘N") {
                    newDocument { MarkdownDocument() }
                }
                actionButton("Open Existing File…", systemImage: "folder", shortcut: "⌘O") {
                    NSDocumentController.shared.openDocument(nil)
                }
            }
            .padding(.top, 28)
            .padding(.horizontal, 36)

            Spacer()

            if !isDefaultApp {
                VStack(spacing: 4) {
                    Button("Make Markdown Studio the default for .md files") {
                        makeDefault()
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                    if let defaultAppError {
                        Text(defaultAppError).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func actionButton(_ title: String, systemImage: String, shortcut: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .frame(width: 22)
                Text(title)
                Spacer()
                Text(shortcut).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Right: recent files

    private var recentFiles: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Files")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 8)
            if recents.isEmpty {
                Spacer()
                Text("No recent files")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(recents, id: \.self) { url in
                    RecentFileRow(url: url)
                        .contentShape(Rectangle())
                        .onTapGesture { open(url) }
                        .help(url.path)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxHeight: .infinity)
        .background(.background.secondary)
    }

    // MARK: - Actions

    private func refresh() {
        recents = Array(NSDocumentController.shared.recentDocumentURLs
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .prefix(5))
        isDefaultApp = DefaultAppHandler.isDefault
    }

    private func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    private func makeDefault() {
        Task {
            do {
                try await DefaultAppHandler.makeDefault()
                defaultAppError = nil
            } catch {
                defaultAppError = error.localizedDescription
            }
            isDefaultApp = DefaultAppHandler.isDefault
        }
    }
}

private struct RecentFileRow: View {
    let url: URL

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .lineLimit(1)
                Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 3)
    }
}
