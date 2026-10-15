import SwiftUI

/// Sidebar table of contents built from the document's headings.
struct OutlineView: View {
    let session: DocumentSession
    /// Called after jumping to a heading (closes the outline sheet on iPhone).
    var onJump: (() -> Void)?

    private var currentLine: Int? {
        session.outline.last(where: { $0.line <= session.cursorLine })?.line
    }

    var body: some View {
        List {
            Section("Outline") {
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
                    .listRowBackground(
                        currentLine == item.line
                            ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15)).padding(.horizontal, 8)
                            : nil
                    )
                }
            }
        }
        .listStyle(.sidebar)
    }
}
