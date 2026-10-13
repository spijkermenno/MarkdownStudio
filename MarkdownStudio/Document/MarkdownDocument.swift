import Combine
import SwiftUI
import UniformTypeIdentifiers

nonisolated extension UTType {
    static let markdownDocument = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// A reference document so the editor's NSTextView owns undo: edits register
/// with the document's undo manager (which also marks it dirty) and SwiftUI
/// doesn't add its own per-keystroke undo steps on top.
///
/// `@unchecked Sendable`: `text` is only touched on the main thread (by the
/// editor and by SwiftUI's `snapshot(contentType:)`); writing to disk uses
/// the immutable snapshot.
nonisolated final class MarkdownDocument: ReferenceFileDocument, @unchecked Sendable {
    static let readableContentTypes: [UTType] = [.markdownDocument, .plainText]
    static let writableContentTypes: [UTType] = [.markdownDocument, .plainText]

    /// Kept in sync by the editor; deliberately not @Published so typing
    /// doesn't re-render the window.
    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = try Self.decode(data)
    }

    func snapshot(contentType: UTType) throws -> String {
        text
    }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }

    /// UTF-8 first (with or without BOM), then the encodings older Markdown files tend to use.
    static func decode(_ data: Data) throws -> String {
        if let text = String(data: data, encoding: .utf8) {
            return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        }
        // UTF-16 decoding "succeeds" on almost any even-length data, so require a BOM.
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16) {
            return text
        }
        for encoding in [String.Encoding.windowsCP1252, .macOSRoman] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}
