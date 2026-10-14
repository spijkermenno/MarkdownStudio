import SwiftUI

struct StatusBarView: View {
    let session: DocumentSession
    @State private var isEditingGoal = false
    @AppStorage(SettingsKey.showProblems) private var showProblems = false
    @AppStorage(SettingsKey.checkDocument) private var checkDocument = true

    var body: some View {
        HStack(spacing: 14) {
            let stats = session.statistics
            Button {
                isEditingGoal = true
            } label: {
                if let goal = session.goal {
                    HStack(spacing: 6) {
                        GoalRing(progress: Double(stats.words) / Double(max(goal, 1)))
                        Text("\(stats.words.formatted()) / \(goal.formatted()) words")
                    }
                } else {
                    Text("\(stats.words.formatted()) \(stats.words == 1 ? "word" : "words")")
                }
            }
            .buttonStyle(.plain)
            .help(session.goal == nil ? "Set a writing goal" : "Change the writing goal")
            .popover(isPresented: $isEditingGoal, arrowEdge: .top) {
                GoalPopover(session: session)
            }
            if session.wordsToday != 0 {
                Text("\(session.wordsToday > 0 ? "+" : "")\(session.wordsToday.formatted()) today")
            }
            // Less important details give way first when the window is narrow.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    Text("\(stats.characters.formatted()) characters")
                    Text(stats.readingMinutes == 0 ? "No reading time" : "\(stats.readingMinutes) min read")
                }
                Text(stats.readingMinutes == 0 ? "" : "\(stats.readingMinutes) min read")
                Color.clear.frame(width: 0, height: 0)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            if checkDocument {
                Button {
                    showProblems.toggle()
                } label: {
                    let warnings = session.problems.filter { $0.severity == .warning }.count
                    let notes = session.problems.count - warnings
                    HStack(spacing: 8) {
                        Label("\(warnings)", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(warnings > 0 ? Color.orange : .secondary)
                        Label("\(notes)", systemImage: "info.circle")
                    }
                    .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .help(showProblems ? "Hide Problems (⇧⌘M)" : "Show Problems (⇧⌘M)")
                .accessibilityLabel(Self.problemSummary(warnings: session.problems.filter { $0.severity == .warning }.count,
                                                        notes: session.problems.filter { $0.severity != .warning }.count))
                .accessibilityHint(showProblems ? "Hides the problems list" : "Shows the problems list")
            }
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
            .fixedSize()
            .layoutPriority(1)
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

/// A small progress ring; turns green with a checkmark once the goal is met.
struct GoalRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(progress >= 1 ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if progress >= 1 {
                Image(systemName: "checkmark").font(.system(size: 6, weight: .heavy)).foregroundStyle(.green)
            }
        }
        .frame(width: 12, height: 12)
        .animation(.easeOut(duration: 0.3), value: progress)
        .accessibilityLabel("\(Int(min(progress, 1) * 100)) percent of goal")
    }
}

private struct GoalPopover: View {
    let session: DocumentSession
    @Environment(\.dismiss) private var dismiss
    @State private var words = 1000

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Writing Goal").font(.headline)
            HStack {
                TextField("Words", value: $words, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .onSubmit(save)
                Text("words")
            }
            HStack(spacing: 6) {
                ForEach([500, 1000, 1500, 2500], id: \.self) { preset in
                    Button(preset.formatted()) { words = preset }
                        .controlSize(.small)
                }
            }
            Text(session.goalIsInFrontMatter
                 ? "Saved in this document's front matter (goal:)."
                 : "Saved for this file on this Mac. Add goal: to the front matter to keep it in the file.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if session.goal != nil {
                    Button("Remove Goal", role: .destructive) {
                        session.setGoal(nil)
                        dismiss()
                    }
                }
                Spacer()
                Button("Set Goal", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(words <= 0)
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear { words = session.goal ?? 1000 }
    }

    private func save() {
        guard words > 0 else { return }
        session.setGoal(words)
        dismiss()
    }
}

extension StatusBarView {
    /// "3 warnings, 1 note" for VoiceOver, instead of the bare numbers on screen.
    nonisolated static func problemSummary(warnings: Int, notes: Int) -> String {
        "\(warnings) \(warnings == 1 ? "warning" : "warnings"), \(notes) \(notes == 1 ? "note" : "notes")"
    }
}
