import Foundation
import UniformTypeIdentifiers

nonisolated struct CompletionItem: Hashable, Sendable {
    enum Icon: Hashable, Sendable { case emoji(String), symbol(String) }
    var title: String
    var detail: String?
    var icon: Icon
    var insertion: String
    /// Folders keep the list open so you can continue into them.
    var keepsOpen = false
}

nonisolated struct CompletionContext: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case emoji, path(imagesOnly: Bool, directory: String), anchor, footnote }
    var kind: Kind
    /// The text that a chosen item replaces.
    var replaceRange: NSRange
    var query: String
    /// Inserted after the item when the next character isn't already this.
    var closer: String?
}

/// Decides when to suggest something and what: emoji after `:`, files after
/// `](`, headings after `](#` and footnotes after `[^`.
nonisolated enum CompletionEngine {
    private static let footnote = try! NSRegularExpression(pattern: #"\[\^([^\]\s]*)$"#)
    private static let destination = try! NSRegularExpression(pattern: #"(!?)\[(?:[^\[\]]|\[[^\]]*\])*\]\(([^)\s]*)$"#)
    private static let emoji = try! NSRegularExpression(pattern: #"(?:^|[\s(\[*_])(:([a-z0-9_+\-]{2,}))$"#)

    static func context(in text: String, caret: Int) -> CompletionContext? {
        let ns = text as NSString
        guard caret <= ns.length else { return nil }
        let lineStart = ns.lineRange(for: NSRange(location: caret, length: 0)).location
        let prefix = ns.substring(with: NSRange(location: lineStart, length: caret - lineStart))
        let range = NSRange(location: 0, length: prefix.utf16Length)
        func absolute(_ r: NSRange) -> NSRange { NSRange(location: lineStart + r.location, length: r.length) }

        if MarkdownHighlighter.fencedCodeRanges(in: text).contains(where: { NSLocationInRange(caret, $0) && caret != NSMaxRange($0) }) {
            return nil
        }
        if let m = footnote.firstMatch(in: prefix, range: range) {
            return CompletionContext(kind: .footnote, replaceRange: absolute(m.range(at: 1)),
                                     query: (prefix as NSString).substring(with: m.range(at: 1)), closer: "]")
        }
        if let m = destination.firstMatch(in: prefix, range: range) {
            let isImage = m.range(at: 1).length > 0
            let target = (prefix as NSString).substring(with: m.range(at: 2))
            let targetRange = absolute(m.range(at: 2))
            if target.hasPrefix("#") {
                return CompletionContext(kind: .anchor, replaceRange: NSRange(location: targetRange.location + 1, length: targetRange.length - 1),
                                         query: String(target.dropFirst()), closer: nil)
            }
            if target.contains(":") { return nil }  // a URL, not a path
            let slash = (target as NSString).range(of: "/", options: .backwards)
            let directory = slash.location == NSNotFound ? "" : (target as NSString).substring(to: NSMaxRange(slash))
            let name = slash.location == NSNotFound ? target : (target as NSString).substring(from: NSMaxRange(slash))
            return CompletionContext(kind: .path(imagesOnly: isImage, directory: directory),
                                     replaceRange: NSRange(location: NSMaxRange(targetRange) - name.utf16Length, length: name.utf16Length),
                                     query: name, closer: nil)
        }
        if let m = emoji.firstMatch(in: prefix, range: range) {
            return CompletionContext(kind: .emoji, replaceRange: absolute(m.range(at: 1)),
                                     query: (prefix as NSString).substring(with: m.range(at: 2)), closer: nil)
        }
        return nil
    }

    static func items(for context: CompletionContext, text: String, documentDirectory: URL?,
                      emoji: [(name: String, character: String)] = EmojiData.all,
                      listDirectory: (URL) -> [(name: String, isDirectory: Bool)] = CompletionEngine.listDirectory,
                      limit: Int = 8) -> [CompletionItem] {
        let query = context.query.lowercased()
        func rank(_ candidate: String) -> Int? {
            let lower = candidate.lowercased()
            if query.isEmpty { return 1 }
            if lower.hasPrefix(query) { return 0 }
            if lower.contains(query) { return 1 }
            return nil
        }
        func ranked<T>(_ values: [T], key: (T) -> String) -> [T] {
            values.compactMap { value in rank(key(value)).map { (value, $0) } }
                .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : key($0.0).count < key($1.0).count }
                .prefix(limit).map(\.0)
        }

        switch context.kind {
        case .emoji:
            return ranked(emoji, key: \.name).map {
                CompletionItem(title: ":\($0.name):", icon: .emoji($0.character), insertion: ":\($0.name):")
            }
        case .anchor:
            let headings = OutlineParser.parse(text)
            return ranked(headings, key: { "\($0.anchor) \($0.title)" }).map {
                CompletionItem(title: $0.title, detail: "#\($0.anchor)", icon: .symbol("number"), insertion: $0.anchor)
            }
        case .footnote:
            let ids = footnoteIDs(in: text)
            return ranked(ids, key: { $0 }).map {
                CompletionItem(title: "[^\($0)]", icon: .symbol("text.append"), insertion: $0)
            }
        case .path(let imagesOnly, let directory):
            guard let documentDirectory else { return [] }
            let folder = documentDirectory.appending(path: directory.removingPercentEncoding ?? directory)
            let entries = listDirectory(folder).filter { entry in
                guard !entry.name.hasPrefix(".") else { return false }
                if entry.isDirectory { return true }
                let type = UTType(filenameExtension: (entry.name as NSString).pathExtension)
                return !imagesOnly || (type?.conforms(to: .image) ?? false)
            }
            return ranked(entries, key: \.name).map { entry in
                let encoded = entry.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entry.name
                let symbol = entry.isDirectory ? "folder" : (imagesOnly ? "photo" : "doc.text")
                return CompletionItem(title: entry.name + (entry.isDirectory ? "/" : ""), icon: .symbol(symbol),
                                      insertion: encoded + (entry.isDirectory ? "/" : ""), keepsOpen: entry.isDirectory)
            }
        }
    }

    static func footnoteIDs(in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"\[\^([^\]\s]+)\]"#)
        var ids: [String] = []
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: text.utf16Length)) { m, _, _ in
            if let m {
                let id = (text as NSString).substring(with: m.range(at: 1))
                if !ids.contains(id) { ids.append(id) }
            }
        }
        return ids
    }

    static func listDirectory(_ url: URL) -> [(name: String, isDirectory: Bool)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return urls.map { ($0.lastPathComponent, (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) }
    }
}

nonisolated enum EmojiData {
    /// Shortcode → emoji, the same list the preview renders (markdown-it-emoji).
    static let all: [(name: String, character: String)] = {
        guard let url = Bundle.main.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [] }
        return map.map { (name: $0.key, character: $0.value) }.sorted { $0.name < $1.name }
    }()
}
