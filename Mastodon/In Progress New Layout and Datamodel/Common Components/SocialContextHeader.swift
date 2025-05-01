// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import SwiftUI
import MastodonAsset
import MastodonLocalization

enum SocialContextHeader {
    case mention(isPrivate: Bool)
    case reply(to: String, isPrivate: Bool, isNotification: Bool)
    case boosted(by: String)
    //case pinned
    
    var iconName: String {
        switch self {
        case .mention:
            return "at"
        case .reply:
            return "arrow.turn.up.left"
        case .boosted:
            return "arrow.2.squarepath"
        }
    }
    
    var text: String {
        switch self {
        case .mention(let isPrivate):
            return isPrivate ? L10n.Common.Controls.Status.privateMention : L10n.Common.Controls.Status.mention
        case .reply(let originalPoster, let isPrivate, let isNotification):
            switch (isPrivate, isNotification) {
            case (true, _):
                return L10n.Common.Controls.Status.privateReply
            case (false, true):
                return L10n.Common.Controls.Status.reply
            case (false, false):
                return L10n.Common.Controls.Status.userRepliedTo(originalPoster)
            }
        case .boosted(let booster):
            return L10n.Common.Controls.Status.userReblogged(booster)
        }
    }
    
    var color: Color {
        switch self {
        case .mention(true), .reply(_, true, _):  // isPrivate
            return Asset.Colors.accent.swiftUIColor
        default:
            return .secondary
        }
    }
}

let socialContextHeaderHeight: CGFloat = 20

extension SocialContextHeader: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: spacingBetweenGutterAndContent) {
            Image(systemName: iconName)
                .font(.subheadline)
                .bold()
                .foregroundStyle(color)
                .frame(height: socialContextHeaderHeight)
            
            Text(text)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(color)
                .frame(height: socialContextHeaderHeight)
                .alignmentGuide(.gutterAlign) { d in
                    return d[HorizontalAlignment.leading]
                }
        }
    }
}

