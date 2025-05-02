// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import MastodonSDK
import MastodonMeta
import SwiftUI

enum TextViewWithCustomEmoji {
    typealias Emojis = [Mastodon.Entity.Emoji]
    
    case timelinePost(html: String, emojis: Emojis)
    case socialContextHeader(html: String, emojis: Emojis)
}

extension TextViewWithCustomEmoji: View {
    var body: some View {
        switch self {
        case .timelinePost(let html, let emojis):
            Text(attributedString(fromHtml: html, emojis: mapEmojiShortcodeToEmojis(emojis), withFormat: .fullPost))
        case .socialContextHeader(let html, let emojis):
            Text(attributedString(fromHtml: html, emojis: mapEmojiShortcodeToEmojis(emojis), withFormat: .socialContextHeader))
        }
    }
}

func mapEmojiShortcodeToEmojis(_ emojis: TextViewWithCustomEmoji.Emojis) -> [MastodonContent.Shortcode: String] {
    return emojis.reduce(into: [:]) { partialResult, emoji in
        partialResult[emoji.shortcode] = UserDefaults.standard.preferredStaticAvatar ? emoji.staticURL : emoji.url
    }
}
