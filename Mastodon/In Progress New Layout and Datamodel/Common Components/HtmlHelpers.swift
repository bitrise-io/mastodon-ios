// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import Foundation
import MastodonMeta
import MetaTextKit
import MastodonCore

let metaTextForHtmlToAttributedStringConversion = {
    let meta = MetaText()
    meta.textAttributes = [:]
    meta.linkAttributes = [:]
    return meta
}()

func attributedString(
    fromHtml html: String, emojis: [MastodonContent.Shortcode: String]
) -> AttributedString {
    let content = MastodonContent(content: html, emojis: emojis)
    metaTextForHtmlToAttributedStringConversion.reset()
    do {
        let metaContent = try MastodonMetaContent.convert(document: content)
        metaTextForHtmlToAttributedStringConversion.configure(
            content: metaContent)
        guard
            let nsAttributedString = metaTextForHtmlToAttributedStringConversion
                .textView.attributedText
        else {
            throw AppError.unexpected(
                "could not get attributed string from html")
        }
        return AttributedString(nsAttributedString)
    } catch {
        return AttributedString(html)
    }
}
