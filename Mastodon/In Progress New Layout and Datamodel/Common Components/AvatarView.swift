// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import SwiftUI

private let avatarShape = RoundedRectangle(cornerRadius: 8)

struct AvatarView: View {
    @ScaledMetric var sizeLarge = AvatarSize.large
    @ScaledMetric var sizeSmall = AvatarSize.small
    
    @State var isNavigating: Bool = false
    
    enum Size {
        case large
        case small
    }
    
    let size: Size
    let author: AccountInfo
    let goToProfile: ((AccountInfo) async throws -> ())?
    
    private var viewDimension: CGFloat {
        switch size {
        case .large: sizeLarge
        case .small: sizeSmall
        }
    }
    
    var body: some View {
        ZStack {
            AsyncImage(
                url: author.avatarURL,
                content: { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(avatarShape)
                        .overlay {
                            avatarShape.stroke(.separator)
                        }
                },
                placeholder: {
                    avatarShape
                        .foregroundStyle(
                            Color(UIColor.secondarySystemFill))
                }
            )
            
            if isNavigating {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(width: 30)
            }
        }
        .frame(width: viewDimension, height: viewDimension)
        .onTapGesture {
            if let goToProfile, !isNavigating {
                Task {
                    do {
                        isNavigating = true
                        try await goToProfile(author)
                    } catch {
                    }
                    isNavigating = false
                }
            }
        }
    }
}
