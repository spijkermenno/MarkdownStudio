import SwiftUI

struct StatusBarView: View {
    let session: DocumentSession

    var body: some View {
        HStack(spacing: 14) {
            let stats = session.statistics
            Text("\(stats.words.formatted()) \(stats.words == 1 ? "word" : "words")")
            Text("\(stats.characters.formatted()) characters")
            Text(stats.readingMinutes == 0 ? "No reading time" : "\(stats.readingMinutes) min read")
            Spacer()
            if session.zoom != 1 {
                Button("\(Int((session.zoom * 100).rounded()))%", action: session.resetZoom)
                    .buttonStyle(.plain)
                    .help("Reset zoom (⌘0)")
            }
            if session.selectionLength > 0 {
                Text("\(session.selectionLength.formatted()) selected")
            }
            Button("Ln \(session.cursorLine + 1), Col \(session.cursorColumn + 1)") {
                session.isShowingGoToLine = true
            }
            .buttonStyle(.plain)
            .help("Go to Line… (⌘L)")
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }
}
