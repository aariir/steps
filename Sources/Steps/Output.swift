import AppKit
import CoreGraphics
import StepsCore
import UniformTypeIdentifiers

enum Annotator {
    /// Draws a red ring at a normalized (top-left origin) point.
    static func ring(on image: CGImage, at n: CGPoint?) -> CGImage {
        guard let n else { return image }
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let r = CGFloat(max(w, h)) * 0.018
        let c = CGPoint(x: n.x * CGFloat(w), y: (1 - n.y) * CGFloat(h))
        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.setFillColor(CGColor(red: 1, green: 0.15, blue: 0.15, alpha: 0.18))
        ctx.fillEllipse(in: rect)
        ctx.setStrokeColor(CGColor(red: 1, green: 0.15, blue: 0.15, alpha: 1))
        ctx.setLineWidth(max(3, r * 0.22))
        ctx.strokeEllipse(in: rect)
        return ctx.makeImage() ?? image
    }

    static func savePNG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}

enum PDFExporter {
    struct ExportError: Error {}

    static func export(title: String, steps: [Step], sessionDir: URL, to url: URL) throws {
        let pageW: CGFloat = 595, pageH: CGFloat = 842, margin: CGFloat = 48
        let contentW = pageW - margin * 2
        var box = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { throw ExportError() }
        let gc = NSGraphicsContext(cgContext: ctx, flipped: false)

        var y: CGFloat = 0
        var pageOpen = false

        func newPage() {
            if pageOpen { NSGraphicsContext.restoreGraphicsState(); ctx.endPDFPage() }
            ctx.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = gc
            pageOpen = true
            y = pageH - margin
        }

        func draw(_ text: String, font: NSFont, color: NSColor = .black) -> CGFloat {
            let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
            let bounds = attr.boundingRect(with: CGSize(width: contentW, height: .greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin])
            let h = ceil(bounds.height)
            attr.draw(with: CGRect(x: margin, y: y - h, width: contentW, height: h), options: [.usesLineFragmentOrigin])
            return h
        }

        func measure(_ text: String, font: NSFont) -> CGFloat {
            let attr = NSAttributedString(string: text, attributes: [.font: font])
            return ceil(attr.boundingRect(with: CGSize(width: contentW, height: .greatestFiniteMagnitude),
                                          options: [.usesLineFragmentOrigin]).height)
        }

        newPage()
        y -= draw(title, font: .boldSystemFont(ofSize: 26)) + 8
        y -= draw(Date().formatted(date: .long, time: .omitted), font: .systemFont(ofSize: 11), color: .gray) + 20

        let captionFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let maxImageH: CGFloat = 330

        for (i, step) in steps.enumerated() {
            var imageSize = CGSize.zero
            var cg: CGImage?
            if let file = step.imageFile,
               let src = CGImageSourceCreateWithURL(sessionDir.appendingPathComponent(file) as CFURL, nil),
               let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                let scale = min(contentW / CGFloat(img.width), maxImageH / CGFloat(img.height), 1)
                imageSize = CGSize(width: CGFloat(img.width) * scale, height: CGFloat(img.height) * scale)
                cg = img
            }
            let text = "\(i + 1). \(step.caption)"
            let needed = measure(text, font: captionFont) + 8 + (cg == nil ? 0 : imageSize.height + 8) + 16
            if y - needed < margin { newPage() }

            y -= draw(text, font: captionFont) + 8
            if let cg {
                let rect = CGRect(x: margin, y: y - imageSize.height, width: imageSize.width, height: imageSize.height)
                ctx.draw(cg, in: rect)
                ctx.setStrokeColor(CGColor(gray: 0.75, alpha: 1))
                ctx.setLineWidth(0.5)
                ctx.stroke(rect)
                y -= imageSize.height + 8
            }
            y -= 16
        }

        if pageOpen { NSGraphicsContext.restoreGraphicsState(); ctx.endPDFPage() }
        ctx.closePDF()
    }
}
