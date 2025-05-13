// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import MastodonSDK
import SwiftUI

struct AuthorHeaderView: View {
    let author: MastodonAccount
    
    var body: some View {
        VStack(alignment: .leading) {
            textComponent("\(author.displayInfo.displayName)", fontWeight: .semibold)
                .alignmentGuide(.gutterAlign) { d in
                    return d[HorizontalAlignment.leading]
                }
            textComponent("@\(author.displayInfo.handle)", fontWeight: .light)
        }
    }
}

extension MastodonAccount: AccountInfo {
    var handle: String {
        return displayInfo.handle
    }
    
    var avatarURL: URL? {
        return displayInfo.avatarUrl
    }
    
    var locked: Bool {
        return metadata.manuallyApprovesNewFollows
    }
    
    var fullAccount: Mastodon.Entity.Account? {
        return nil
    }
}
