import AppKit
import Foundation

struct PreparedFeedbackImage: Equatable {
    let data: Data
    let filename: String
    let contentType: String
    let thumbnail: NSImage

    static func == (lhs: PreparedFeedbackImage, rhs: PreparedFeedbackImage) -> Bool {
        lhs.data == rhs.data
            && lhs.filename == rhs.filename
            && lhs.contentType == rhs.contentType
    }
}

enum FeedbackImageProcessor {
    static let maxPixelDimension = 1600
    static let jpegCompression: CGFloat = 0.78

    static func prepare(url: URL) throws -> PreparedFeedbackImage {
        guard let sourceImage = NSImage(contentsOf: url),
              let sourceRep = bitmapRepresentation(for: sourceImage)
        else {
            throw FeedbackAPIError.networkError(L("feedback.error.invalidImage"))
        }

        guard let resizedRep = resizedBitmapRepresentation(
            for: sourceImage,
            pixelsWide: sourceRep.pixelsWide,
            pixelsHigh: sourceRep.pixelsHigh
        ),
            let data = resizedRep.representation(
                using: .jpeg,
                properties: [.compressionFactor: jpegCompression]
            )
        else {
            throw FeedbackAPIError.networkError(L("feedback.error.invalidImage"))
        }
        let thumbnail = NSImage(size: resizedRep.size)
        thumbnail.addRepresentation(resizedRep)

        return PreparedFeedbackImage(
            data: data,
            filename: jpegFilename(from: url),
            contentType: "image/jpeg",
            thumbnail: thumbnail
        )
    }

    private static func bitmapRepresentation(for image: NSImage) -> NSBitmapImageRep? {
        if let tiffData = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiffData) {
            return rep
        }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return NSBitmapImageRep(cgImage: cgImage)
    }

    private static func resizedBitmapRepresentation(
        for image: NSImage,
        pixelsWide: Int,
        pixelsHigh: Int
    ) -> NSBitmapImageRep? {
        let longestSide = max(pixelsWide, pixelsHigh)
        let scale = longestSide > maxPixelDimension
            ? CGFloat(maxPixelDimension) / CGFloat(longestSide)
            : 1
        let targetPixelsWide = max(1, Int((CGFloat(pixelsWide) * scale).rounded()))
        let targetPixelsHigh = max(1, Int((CGFloat(pixelsHigh) * scale).rounded()))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetPixelsWide,
            pixelsHigh: targetPixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        rep.size = NSSize(width: targetPixelsWide, height: targetPixelsHigh)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = context
        context?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: targetPixelsWide, height: targetPixelsHigh),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        return rep
    }

    private static func jpegFilename(from url: URL) -> String {
        let baseName = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(baseName.isEmpty ? "feedback-image" : baseName).jpg"
    }
}
