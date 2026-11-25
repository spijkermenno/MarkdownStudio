import SwiftUI

/// Sidebar table of contents built from the document's headings.
struct OutlineView: View {
    let session: DocumentSession
    /// Called after jumping to a heading (closes the outline sheet on iPhone).
    var onJump: (() -> Void)?
    /// Shows a Done button when the outline is presented as a sheet.
    var onDone: (() -> Void)?

    private var currentLine: Int? {
        session.outline.last(where: { $0.line <= session.cursorLine })?.line
    }

    var body: some View {
        #if os(macOS)
        List {
            Section("Outline") { rows }
        }
        .listStyle(.sidebar)
        #else
        // On iPhone this is a sheet and on iPad an inspector column: give it a
        // proper title bar instead of the Mac's collapsible sidebar section.
        NavigationStack {
            List { rows }
                .listStyle(.insetGrouped)
                .navigationTitle("Outline")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let onDone {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", action: onDone)
                        }
                    }
                }
        }
        #endif
    }

    @ViewBuilder
    private var rows: some View {
        if session.outline.isEmpty {
            Text("No headings yet")
                .foregroundStyle(.secondary)
        }
        ForEach(session.outline) { item in
            Button {
                session.jump(toLine: item.line)
                onJump?()
            } label: {
                Text(item.title)
                    .font(item.level == 1 ? .body.weight(.semibold) : .body)
                    .foregroundStyle(item.level > 3 ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, CGFloat(item.level - 1) * 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.title)
            .listRowBackground(currentLine == item.line ? currentRowBackground : nil)
        }
    }

    private var currentRowBackground: some View {
        #if os(macOS)
        RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15)).padding(.horizontal, 8)
        #else
        // Inset grouped rows already have their own shape; just tint the row.
        Color.accentColor.opacity(0.15)
        #endif
    }
}
