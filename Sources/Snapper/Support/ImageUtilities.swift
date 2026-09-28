import AppKit
import CoreGraphics
import UniformTypeIdentifiers

enum ImageUtilities {
    /// Crops using `CGImage`'s top-left origin coordinate space.
    static func cropped(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clipped = rect.integral.intersection(bounds)
        guard clipped.width >= 1, clipped.height >= 1 else { return nil }
        return image.cropping(to: clipped)
    }

    static func pngData(from image: CGImage) throws -> Data {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw ScreenCaptureError.imageEncodingFailed
        }
        return data
    }

    static func copyToClipboard(_ image: CGImage) {
        let representation = NSBitmapImageRep(cgImage: image)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let png = representation.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = representation.representation(using: .tiff, properties: [:]) {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    /// The bundle's declared UTI for PNG files, used by save panels.
    static let pngContentType: UTType = .png
}
