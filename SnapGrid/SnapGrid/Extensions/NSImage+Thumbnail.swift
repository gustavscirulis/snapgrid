import AppKit

extension NSImage {
    /// Resize image to fit within maxWidth preserving aspect ratio, export as JPEG data
    func thumbnailData(maxWidth: CGFloat = 800, quality: CGFloat = 0.9) -> Data? {
        guard let rep = self.bestRepresentation(for: NSRect(origin: .zero, size: self.size), context: nil, hints: nil) else {
            return nil
        }

        let originalWidth = CGFloat(rep.pixelsWide)
        let originalHeight = CGFloat(rep.pixelsHigh)

        guard originalWidth > 0, originalHeight > 0 else { return nil }

        let scale: CGFloat
        if originalWidth > maxWidth {
            scale = maxWidth / originalWidth
        } else {
            scale = 1.0
        }

        let newWidth = originalWidth * scale
        let newHeight = originalHeight * scale
        let newSize = NSSize(width: newWidth, height: newHeight)

        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        self.draw(in: NSRect(origin: .zero, size: newSize),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy,
                  fraction: 1.0)
        resizedImage.unlockFocus()

        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// Get pixel dimensions
    var pixelSize: NSSize? {
        guard let rep = self.representations.first else { return nil }
        return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }
}
