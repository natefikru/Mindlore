import SwiftUI

// Thumbnails of an entry's pages above its text, so the transcription can be checked against them.
struct PageStripView: View {
    let pages: [EntryPage]
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(pages.enumerated()), id: \.element.persistentModelID) { position, page in
                    Button {
                        onSelect(position)
                    } label: {
                        Group {
                            if let data = page.thumbnailData, let image = UIImage(data: data) {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                Color.secondary.opacity(0.2)
                            }
                        }
                        .frame(width: 60, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(alignment: .bottomTrailing) {
                            Text("\(position + 1)")
                                .font(.caption2.bold())
                                .padding(3)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                                .padding(3)
                        }
                    }
                    .accessibilityLabel("Page \(position + 1)")
                }
            }
            .padding(.horizontal)
        }
        .accessibilityIdentifier("pageStrip")
    }
}

// Full pages, swipeable and zoomable. Images are decoded at screen-friendly size off the main thread.
struct PageViewer: View {
    let pages: [EntryPage]
    @State var selection: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(Array(pages.enumerated()), id: \.element.persistentModelID) { position, page in
                    ZoomablePage(imageData: page.imageData)
                        .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .background(Color.black)
            .navigationTitle("Page \(selection + 1) of \(pages.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ZoomablePage: View {
    let imageData: Data?
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { scale = min(max(settledScale * $0.magnification, 1), 5) }
                            .onEnded { _ in settledScale = scale }
                    )
                    .onTapGesture(count: 2) {
                        scale = scale > 1 ? 1 : 2.5
                        settledScale = scale
                    }
            } else {
                ProgressView()
            }
        }
        .task {
            guard image == nil, let imageData else { return }
            image = await Self.decode(imageData)
        }
    }

    @concurrent
    nonisolated private static func decode(_ data: Data) async -> UIImage? {
        (try? PageImageProcessor.downsample(data, longEdge: 2_048)).map { UIImage(cgImage: $0) }
    }
}
