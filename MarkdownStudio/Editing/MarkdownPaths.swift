import Foundation

enum MarkdownPaths {
    /// A Markdown-ready (percent-encoded) path to `url`, relative to `directory` when possible.
    nonisolated static func relativePath(to url: URL, from directory: URL?) -> String {
        guard let directory else { return url.absoluteString }
        let target = url.standardizedFileURL.pathComponents
        let base = directory.standardizedFileURL.pathComponents
        var common = 0
        while common < min(target.count, base.count), target[common] == base[common] { common += 1 }
        // Only the root in common: an absolute path is clearer.
        guard common > 1 else { return url.absoluteString }
        let ups = Array(repeating: "..", count: base.count - common)
        let path = (ups + target[common...]).joined(separator: "/")
        return path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    }
}
