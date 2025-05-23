// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import MastodonSDK
import MastodonMeta
import SwiftUI

enum TextViewWithCustomEmoji {
    typealias Emojis = [Mastodon.Entity.Emoji]
    
    case timelinePost(html: String, emojis: Emojis)
    case authorHeader(html: String, emojis: Emojis)
    case socialContextHeader(html: String, emojis: Emojis, isPrivate: Bool)
    case linkPreviewCardAuthorButton(html: String, emojis: Emojis)
    case pollOption(html: String, emojis: Emojis)
}

extension TextViewWithCustomEmoji: View {
    var body: some View {
        switch self {
        case .timelinePost(let html, let emojis):
            Text(attributedString(fromHtml: html, emojis: mapEmojiShortcodeToEmojis(emojis), withFormat: .fullPost))
        case .authorHeader(let html, let emojis):
            Text(attributedString(fromHtml: html, emojis: mapEmojiShortcodeToEmojis(emojis), withFormat: .authorHeader))
        case .socialContextHeader(let html, let emojis, let isPrivate):
            Text(attributedString(fromHtml: html, emojis: mapEmojiShortcodeToEmojis(emojis), withFormat: isPrivate ? .socialContextHeaderPrivate : .socialContextHeader))
        case .linkPreviewCardAuthorButton(let html, let emojis):
            Text(attributedString(fromHtml: html, emojis: mapEmojiShortcodeToEmojis(emojis), withFormat: .linkPreviewCardAuthor))
        case .pollOption(let html, let emojis):
            Text(attributedString(fromHtml: html, emojis: mapEmojiShortcodeToEmojis(emojis), withFormat: .pollOption))
        }
    }
}

func mapEmojiShortcodeToEmojis(_ emojis: TextViewWithCustomEmoji.Emojis) -> [MastodonContent.Shortcode: String] {
    return emojis.reduce(into: [:]) { partialResult, emoji in
        partialResult[emoji.shortcode] = UserDefaults.standard.preferredStaticAvatar ? emoji.staticURL : emoji.url
    }
}
