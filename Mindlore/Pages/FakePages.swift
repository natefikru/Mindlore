import UIKit

// With -uiTestingFakePages the camera and photo picker are replaced by generated pages, so UI tests
// can run the page flow in the simulator, which has no camera.
nonisolated enum FakePages {
    static let launchArgument = "-uiTestingFakePages"

    static var isEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains(StoreLocation.uiTestingArgument) && arguments.contains(launchArgument)
    }

    // Each page has a distinct width so tests can tell pages apart by their row identifiers.
    static func make(count: Int, startingWidth: Int) -> [Data] {
        (0..<count).map { offset in
            let size = CGSize(width: startingWidth + offset * 10, height: 1_400)
            return UIGraphicsImageRenderer(size: size, format: { let format = UIGraphicsImageRendererFormat(); format.scale = 1; return format }()).jpegData(withCompressionQuality: 0.8) { context in
                UIColor(white: 0.97, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                ("Fixture page \(offset + 1)" as NSString).draw(at: CGPoint(x: 60, y: 120), withAttributes: [.font: UIFont.systemFont(ofSize: 64)])
            }
        }
    }
}
