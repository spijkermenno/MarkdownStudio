import SwiftUI

/// The document check's findings, below the editor.
struct ProblemsPanel: View {
    let session: DocumentSession

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Problems").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("\(session.problems.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            if session.problems.isEmpty {
                Label("No problems found", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(session.problems) { problem in
                            ProblemRow(problem: problem, select: { session.select(problem) }, fix: { session.fix(problem) })
                        }
                    }
                }
                .frame(height: min(CGFloat(session.problems.count) * 30 + 4, 150))
            }
        }
        .background(.bar)
    }
}

private struct ProblemRow: View {
    let problem: DocumentProblem
    let select: () -> Void
    let fix: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: problem.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(problem.severity == .warning ? Color.orange : Color.blue)
            Text(problem.message).lineLimit(1).truncationMode(.tail)
            Spacer()
            if let fix = problem.fix {
                Button(fix.title, action: self.fix)
                    .controlSize(.small)
            }
            Text("Line \(problem.line + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: select)
        .help(problem.message)
    }
}

struct ToastView: View {
    let toast: DocumentSession.Toast
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.systemImage).foregroundStyle(.secondary)
            Text(toast.message)
            if let title = toast.actionTitle, let action = toast.action {
                Button(title) {
                    action()
                    dismiss()
                }
                .buttonStyle(.link)
            }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
}
