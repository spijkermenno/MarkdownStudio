import QuickLookThumbnailing
import UIKit

/// Draws Markdown files in the document browser and the Files app as a page
/// with their first lines, a "MARKDOWN" corner ribbon and a badge with the
/// file extension, so they stand out from the other text files the app can open.
final class ThumbnailProvider: QLThumbnailProvider {
    /// Matches the arrow in the app icon.
    private static let accentColor = UIColor(red: 0.18, green: 0.55, blue: 0.95, alpha: 1)

    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let lines = Self.leadingLines(of: request.fileURL)
        let fileExtension = "." + request.fileURL.pathExtension.lowercased()
        let size = Self.pageSize(fitting: request.maximumSize)
        handler(QLThumbnailReply(contextSize: size) {
            Self.drawPage(lines: lines, fileExtension: fileExtension, size: size)
            return true
        }, nil)
    }

    /// A portrait page, as large as the request allows.
    private static func pageSize(fitting maximum: CGSize) -> CGSize {
        let ratio: CGFloat = 0.78
        let height = min(maximum.height, maximum.width / ratio)
        return CGSize(width: (height * ratio).rounded(), height: height.rounded())
    }

    /// The first non-empty lines after any front matter; only the start of the file is read.
    private static func leadingLines(of url: URL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 4096)) ?? Data()
        var lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            lines.removeSubrange(...end)
        }
        return lines.filter { !$0.isEmpty && $0 != "---" }.prefix(24).map { $0 }
    }

    private static func drawPage(lines: [String], fileExtension: String, size: CGSize) {
        let page = CGRect(origin: .zero, size: size)
        UIColor.white.setFill()
        UIRectFill(page)

        let badge = badgeLayout(text: fileExtension, in: page)
        let margin = size.width * 0.1
        let bodySize = max(size.width / 16, 2)
        var y = margin
        for line in lines {
            let isHeading = line.hasPrefix("#")
            let content = isHeading ? line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) : line
            let font = isHeading ? UIFont.boldSystemFont(ofSize: bodySize * 1.4) : UIFont.systemFont(ofSize: bodySize)
            let lineHeight = font.lineHeight * 1.1
            // Stop above the badge rather than running underneath it.
            guard y + lineHeight < badge.frame.minY - margin / 2 else { break }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            NSAttributedString(string: content, attributes: [
                .font: font,
                .foregroundColor: isHeading ? UIColor.black : UIColor.darkGray,
                .paragraphStyle: paragraph,
            ]).draw(in: CGRect(x: margin, y: y, width: size.width - margin * 2, height: lineHeight))
            y += lineHeight
        }

        drawRibbon(in: page)

        accentColor.setFill()
        UIBezierPath(roundedRect: badge.frame, cornerRadius: badge.frame.height * 0.25).fill()
        badge.label.draw(at: badge.labelOrigin)
    }

    /// A "MARKDOWN" band across the top-right corner.
    private static func drawRibbon(in page: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let thickness = page.width * 0.2
        // Distance from the corner to the band's centre line, measured along the diagonal.
        let offset = page.width * 0.34
        context.saveGState()
        context.clip(to: page)
        context.translateBy(x: page.maxX - offset / sqrt(2), y: offset / sqrt(2))
        context.rotate(by: .pi / 4)
        context.setShadow(offset: CGSize(width: 0, height: thickness * 0.08), blur: thickness * 0.25,
                          color: UIColor.black.withAlphaComponent(0.3).cgColor)
        accentColor.setFill()
        context.fill(CGRect(x: -page.width, y: -thickness / 2, width: page.width * 2, height: thickness))
        context.setShadow(offset: .zero, blur: 0)

        // The band's visible length is twice the offset; keep the text inside it.
        let label = fittedLabel("MARKDOWN", size: thickness * 0.55, maxWidth: offset * 2 - thickness, weight: .heavy)
        let textSize = label.size()
        label.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2))
        context.restoreGState()
    }

    /// White text, shrunk if needed to fit `maxWidth`.
    private static func fittedLabel(_ text: String, size: CGFloat, maxWidth: CGFloat, weight: UIFont.Weight) -> NSAttributedString {
        func label(_ size: CGFloat) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [
                .font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: UIColor.white,
            ])
        }
        let width = label(size).size().width
        return width > maxWidth ? label(size * maxWidth / width) : label(size)
    }

    /// The file extension on a rounded rectangle in the bottom-right corner.
    private static func badgeLayout(text: String, in page: CGRect) -> (frame: CGRect, label: NSAttributedString, labelOrigin: CGPoint) {
        let inset = page.width * 0.07
        // Long extensions (".markdown") shrink rather than run off the page.
        let label = fittedLabel(text, size: max(page.width * 0.14, 5), maxWidth: page.width * 0.7, weight: .bold)
        let textSize = label.size()
        let padding = CGSize(width: textSize.height * 0.35, height: textSize.height * 0.12)
        let badgeSize = CGSize(width: textSize.width + padding.width * 2, height: textSize.height + padding.height * 2)
        let frame = CGRect(x: page.maxX - badgeSize.width - inset, y: page.maxY - badgeSize.height - inset,
                           width: badgeSize.width, height: badgeSize.height)
        return (frame, label, CGPoint(x: frame.minX + padding.width, y: frame.minY + padding.height))
    }
}
