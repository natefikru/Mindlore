import Foundation
import SwiftData

enum PageOrigin: String, Codable {
    case camera
    case library
}

// One photographed or imported journal page. Follows the same CloudKit schema rules as Entry.
@Model
final class EntryPage {
    var entry: Entry?
    // 0-based position, kept contiguous after every change.
    var index: Int = 0
    @Attribute(.externalStorage) var imageData: Data?
    var thumbnailData: Data?
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var originRaw: String = PageOrigin.camera.rawValue
    var addedAt: Date = Date.now
    // nil means not transcribed yet; an empty string is a finished blank page.
    var transcribedText: String?
    var writtenDate: Date?

    var origin: PageOrigin {
        get { PageOrigin(rawValue: originRaw) ?? .camera }
        set { originRaw = newValue.rawValue }
    }

    init(index: Int, imageData: Data?, thumbnailData: Data?, pixelWidth: Int, pixelHeight: Int, origin: PageOrigin, addedAt: Date = .now) {
        self.index = index
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.originRaw = origin.rawValue
        self.addedAt = addedAt
    }
}
