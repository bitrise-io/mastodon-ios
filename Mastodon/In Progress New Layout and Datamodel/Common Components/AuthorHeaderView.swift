// Copyright © 2025 Mastodon gGmbH. All rights reserved.
import SwiftUI

struct AuthorHeaderView: View {
    
    @ScaledMetric var avatarSize = AvatarSize.large
    
    let author: MastodonAccount
    
    var body: some View {
        HStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 10)
                .fill(.secondary)
                .frame(width: avatarSize, height: avatarSize)
            VStack(alignment: .leading) {
                textComponent("\(author.displayInfo.displayName)", fontWeight: .semibold)
                    .alignmentGuide(.gutterAlign) { d in
                        return d[HorizontalAlignment.leading]
                    }
                textComponent("@\(author.displayInfo.handle)", fontWeight: .light)
            }
        }
    }
}
