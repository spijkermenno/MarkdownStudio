import SwiftUI

struct GoToLineView: View {
    let session: DocumentSession
    @Environment(\.dismiss) private var dismiss
    @State private var line = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Go to Line").font(.headline)
            TextField("Line number (1–\(session.editor.lineIndex.lineCount))", text: $line)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(go)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Go", action: go)
                    .keyboardShortcut(.defaultAction)
                    .disabled(Int(line) == nil)
            }
        }
        .padding(20)
        .frame(width: 300)
        .onAppear { focused = true }
    }

    private func go() {
        guard let number = Int(line.trimmingCharacters(in: .whitespaces)) else { return }
        dismiss()
        DispatchQueue.main.async { session.goToLine(number) }
    }
}
