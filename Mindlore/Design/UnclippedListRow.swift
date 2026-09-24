import SwiftUI
import UIKit

// Lets one List row draw past its cell's edges, for a horizontal strip that should run to the
// screen's edges inside a grouped list (Journal's area chips). SwiftUI gives no way to reach the
// cell, so this walks up from its own view to the collection view cell and turns off clipping on
// each view on the way; nothing above the cell is touched.
struct UnclippedListRow: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: Probe, context: Context) {
        view.unclip()
    }

    final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            unclip()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            unclip()
        }

        func unclip() {
            var current = superview
            while let view = current {
                view.clipsToBounds = false
                if view is UICollectionViewCell { break }
                current = view.superview
            }
        }
    }
}

extension View {
    func unclippedListRow() -> some View {
        background(UnclippedListRow().allowsHitTesting(false))
    }
}
