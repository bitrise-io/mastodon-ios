// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import MastodonSDK
import SwiftUI

struct AuthorHeaderView: View {
    let author: MastodonAccount
    let visibility: GenericMastodonPost.PrivacyLevel
    let postedDate: Date
    @ObservedObject var timestamper: TimestampUpdater
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack (alignment: .top) {
                TextViewWithCustomEmoji.authorHeader(html: author.displayInfo.displayName, emojis: author.displayInfo.emojis)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .alignmentGuide(.gutterAlign) { d in
                        return d[HorizontalAlignment.leading]
                    }
                VisibilityAndTimestamp(timestamper: timestamper, referenceDate: postedDate, visibility: visibility)
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

struct VisibilityAndTimestamp: View {
    @ObservedObject var timestamper: TimestampUpdater
    let referenceDate: Date
    let visibility: GenericMastodonPost.PrivacyLevel
    
    var body: some View {
        HStack(spacing: tinySpacing) {
            if shouldShowVisibilityIndicator {
                Image(systemName: visibility.iconName)
            }
            Text(referenceDate.localizedExtremelyAbbreviatedTimeElapsedUntil(now: timestamper.timestamp))
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.subheadline)
        .frame(height: actionSuperheaderHeight)
        .foregroundColor(.secondary)
        .accessibilityLabel(referenceDate.localizedAbbreviatedSlowedTimeAgoSinceNow)
    }
    
    var shouldShowVisibilityIndicator: Bool {
        switch visibility {
        case .loudPublic:
            return false
        default:
            return true
        }
    }
}

extension GenericMastodonPost.PrivacyLevel {
    var iconName: String {
        switch self {
        case .loudPublic:
            "globe.europe.africa"
        case .quietPublic:
            "moon"
        case .followersOnly:
            "lock"
        case .mentionedOnly:
            "at"
        }
    }
}
