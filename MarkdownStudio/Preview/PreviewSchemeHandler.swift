import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves the preview over `mdstudio://`:
/// - `mdstudio://app/…`  bundled web resources (scripts, themes, fonts)
/// - `mdstudio://doc/…`  files relative to the document's folder (images)
/// - `mdstudio://file/…` absolute file paths
final class PreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mdstudio"
    static let pageURL = URL(string: "mdstudio://app/preview.html")!

    static var webRoot: URL {
        Bundle.main.url(forResource: "Web", withExtension: nil)!
    }

    var documentDirectory: URL?

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let fileURL = resolve(url) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                "Content-Type": mime.hasPrefix("text/") || mime.contains("javascript") ? "\(mime); charset=utf-8" : mime,
                "Content-Length": String(data.count),
                "Cache-Control": "no-cache",
            ])!
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
        } catch {
            task.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    func resolve(_ url: URL) -> URL? {
        let path = url.path(percentEncoded: false)
        switch url.host() {
        case "app":
            let root = Self.webRoot.standardizedFileURL
            let file = root.appending(path: String(path.drop(while: { $0 == "/" }))).standardizedFileURL
            return file.path.hasPrefix(root.path + "/") ? file : nil
        case "doc":
            guard let documentDirectory else { return nil }
            let relative = Self.relativePath(in: url) ?? String(path.drop(while: { $0 == "/" }))
            return documentDirectory.appending(path: relative).standardizedFileURL
        case "file":
            return URL(filePath: path).standardizedFileURL
        default:
            return nil
        }
    }

    /// The document-relative path of an `mdstudio://doc/?p=…` URL, without its
    /// `#fragment` or `?query`, percent-decoded.
    static func relativePath(in url: URL) -> String? {
        guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "p" })?.value
        else { return nil }
        let pathPart = value.components(separatedBy: CharacterSet(charactersIn: "#?")).first ?? value
        return pathPart.removingPercentEncoding ?? pathPart
    }

    /// The `#fragment` of a link, for jumping to a heading in another document.
    static func fragment(in url: URL) -> String? {
        if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "p" })?.value,
           let hash = value.firstIndex(of: "#") {
            let fragment = String(value[value.index(after: hash)...])
            return fragment.isEmpty ? nil : (fragment.removingPercentEncoding ?? fragment)
        }
        return url.fragment(percentEncoded: false)
    }

    /// Maps a preview URL back to a real file URL (used when following links).
    func fileURL(for url: URL) -> URL? {
        guard url.scheme == Self.scheme, url.host() != "app" else { return nil }
        return resolve(url)
    }
}
