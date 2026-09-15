import Foundation
import ImageIO
import UniformTypeIdentifiers

// Turns a captured or imported photo into the stored page, its thumbnail, and later the upload copy.
// ImageIO decodes straight to the target size with orientation applied, so a full-resolution
// bitmap never sits in memory.
nonisolated enum PageImageProcessor {
    static let storageLongEdge = 2_400
    static let thumbnailLongEdge = 400
    static let uploadLongEdge = 2_048
    static let jpegQuality = 0.8

    struct ProcessedPage: Sendable {
        let imageData: Data
        let thumbnailData: Data
        let pixelWidth: Int
        let pixelHeight: Int
    }

    enum ProcessingError: Error {
        case unreadableImage
        case encodingFailed
    }

    static func process(_ source: Data) throws -> ProcessedPage {
        let stored = try downsample(source, longEdge: storageLongEdge)
        let storedData = try jpeg(stored)
        let thumbnail = try jpeg(try downsample(storedData, longEdge: thumbnailLongEdge))
        return ProcessedPage(imageData: storedData, thumbnailData: thumbnail, pixelWidth: stored.width, pixelHeight: stored.height)
    }

    static func uploadJPEG(from stored: Data) throws -> Data {
        try jpeg(try downsample(stored, longEdge: uploadLongEdge))
    }

    static func downsample(_ data: Data, longEdge: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ProcessingError.unreadableImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longEdge,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ProcessingError.unreadableImage
        }
        return image
    }

    static func jpeg(_ image: CGImage) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ProcessingError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ProcessingError.encodingFailed }
        return output as Data
    }
}
