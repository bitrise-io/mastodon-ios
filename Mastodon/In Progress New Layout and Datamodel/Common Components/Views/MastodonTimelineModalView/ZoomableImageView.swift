// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import SwiftUI

struct ZoomableBlurhashImageView: View {
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    let image: MastodonImageAttachment
    let viewModel: ImageGalleryViewModel
    let frameSize: CGSize
    
    var body: some View {
        let originalSize = image.imageDetails.originalSize ?? frameSize
        let aspectRatio = CGFloat(originalSize.height) > 0 ? CGFloat(originalSize.width) / CGFloat(originalSize.height) : 1
        let baseSize = sizeThatFits(aspectRatio: aspectRatio, in: frameSize)
        let zoomedSize = CGSize(width: baseSize.width * scale, height: baseSize.height * scale)
        
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                BlurhashImageView(imageAttachment: image, viewModel: viewModel)
                    .frame(
                        width: zoomedSize.width,
                        height: zoomedSize.height
                    )
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let newScale = lastScale * value
                                scale = max(newScale, 1.0)
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                    )
            }
            .ignoresSafeArea()
        }
    
    private func sizeThatFits(aspectRatio: CGFloat, in container: CGSize) -> CGSize {
        // Fit the image proportionally within the container
        let containerAR = container.width / container.height
        
        if aspectRatio > containerAR {
            // image is wider relative to container — constrain width
            let width = container.width
            let height = width / aspectRatio
            return CGSize(width: width, height: height)
        } else {
            // image is taller — constrain height
            let height = container.height
            let width = height * aspectRatio
            return CGSize(width: width, height: height)
        }
    }
}
