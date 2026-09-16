import SwiftUI
import UIKit
import VisionKit

// VisionKit's document scanner: finds page edges, crops, and straightens. It hands pages back only
// when the user taps Save, in the order they were captured.
struct DocumentCameraView: UIViewControllerRepresentable {
    let onFinish: ([Data]) -> Void
    let onCancel: () -> Void

    static var isSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([Data]) -> Void
        let onCancel: () -> Void

        init(onFinish: @escaping ([Data]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            // Encoded one page at a time so only one full-size bitmap is alive at once.
            var pages: [Data] = []
            for index in 0..<scan.pageCount {
                autoreleasepool {
                    if let data = scan.imageOfPage(at: index).jpegData(compressionQuality: 0.9) {
                        pages.append(data)
                    }
                }
            }
            onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
            onCancel()
        }
    }
}
