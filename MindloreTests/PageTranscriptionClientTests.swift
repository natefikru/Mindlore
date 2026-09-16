import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Mindlore

struct PageTranscriberTests {
    private final class RecordingGenerator: TextGenerator, @unchecked Sendable {
        var requests: [TextRequest] = []
        let responseText: String

        init(_ responseText: String) {
            self.responseText = responseText
        }

        func generate(_ request: TextRequest) async throws -> TextResult {
            requests.append(request)
            return TextResult(text: responseText, model: "vision", inputTokens: 900, outputTokens: 120)
        }
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func sendsTheImageVerbatimPromptAndPreviousTail() async throws {
        let generator = RecordingGenerator(#"{"text":"Dear diary,\nit rained.","writtenDate":"2025-03-03"}"#)
        let transcriber = OpenAICompatiblePageTranscriber(generator: generator, model: "gpt-5.6-terra", calendar: utc)

        let result = try await transcriber.transcribe(PageRequest(imageJPEG: Data([9, 9]), pageNumber: 2, pageCount: 3, previousPageTail: "and then we"))

        let request = try #require(generator.requests.first)
        #expect(request.model == "gpt-5.6-terra")
        #expect(request.images == [TextImage(jpegData: Data([9, 9]), detail: .high)])
        #expect(request.system.contains("[illegible]"))
        #expect(request.user.contains("Page 2 of 3."))
        #expect(request.user.contains("and then we"))
        #expect(request.schema == OpenAICompatiblePageTranscriber.schema)
        #expect(result.text == "Dear diary,\nit rained.")
        #expect(result.writtenDate.map { utc.dateComponents([.year, .month, .day, .hour], from: $0) } == DateComponents(year: 2025, month: 3, day: 3, hour: 12))
        #expect(result.inputTokens == 900)
    }

    @Test func firstPageHasNoTail() async throws {
        let generator = RecordingGenerator(#"{"text":"x","writtenDate":null}"#)
        _ = try await OpenAICompatiblePageTranscriber(generator: generator, model: "m").transcribe(PageRequest(imageJPEG: Data(), pageNumber: 1, pageCount: 1, previousPageTail: nil))
        #expect(generator.requests.first?.user == "Page 1 of 1.")
    }

    @Test func partialDatesAreDroppedAndBlankPagesAreEmpty() async throws {
        let generator = RecordingGenerator(#"{"text":"   ","writtenDate":"2025-03"}"#)
        let result = try await OpenAICompatiblePageTranscriber(generator: generator, model: "m").transcribe(PageRequest(imageJPEG: Data(), pageNumber: 1, pageCount: 1, previousPageTail: nil))
        #expect(result.text == "")
        #expect(result.writtenDate == nil)
    }

    @Test func tailIsTheEndOfThePreviousPage() {
        let text = String(repeating: "a", count: 500) + "THE END"
        let tail = OpenAICompatiblePageTranscriber.tail(of: text)
        #expect(tail.count == OpenAICompatiblePageTranscriber.tailLength)
        #expect(tail.hasSuffix("THE END"))
    }
}

struct PageImageProcessorTests {
    // A solid image with an EXIF orientation, encoded the way a camera or photo library would.
    private func encodedImage(width: Int, height: Int, type: UTType = .jpeg, orientation: Int = 1) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.9, green: 0.85, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func size(of data: Data) throws -> (Int, Int, Int) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (properties[kCGImagePropertyPixelWidth] as? Int ?? 0, properties[kCGImagePropertyPixelHeight] as? Int ?? 0, properties[kCGImagePropertyOrientation] as? Int ?? 1)
    }

    @Test func largePagesAreDownsampledWithThumbnails() throws {
        let processed = try PageImageProcessor.process(try encodedImage(width: 4_000, height: 3_000))

        #expect(processed.pixelWidth == 2_400)
        #expect(processed.pixelHeight == 1_800)
        let (width, height, _) = try size(of: processed.imageData)
        #expect((width, height) == (2_400, 1_800))
        let (thumbWidth, thumbHeight, _) = try size(of: processed.thumbnailData)
        #expect(max(thumbWidth, thumbHeight) == 400)
        let upload = try size(of: try PageImageProcessor.uploadJPEG(from: processed.imageData))
        #expect(max(upload.0, upload.1) == 2_048)
    }

    @Test func orientationIsAppliedToThePixels() throws {
        // Orientation 6 means the stored pixels must be rotated 90 degrees to display upright.
        let processed = try PageImageProcessor.process(try encodedImage(width: 3_000, height: 2_000, orientation: 6))

        #expect(processed.pixelWidth == 1_600)
        #expect(processed.pixelHeight == 2_400)
        let (_, _, orientation) = try size(of: processed.imageData)
        #expect(orientation == 1)
    }

    @Test func heicFromThePhotoLibraryIsReadable() throws {
        guard let heic = try? encodedImage(width: 1_200, height: 900, type: .heic) else { return }
        let processed = try PageImageProcessor.process(heic)
        #expect(processed.pixelWidth == 1_200)
        #expect(processed.pixelHeight == 900)
    }

    @Test func unreadableDataThrows() {
        #expect(throws: PageImageProcessor.ProcessingError.self) { try PageImageProcessor.process(Data("not an image".utf8)) }
    }
}
