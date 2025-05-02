// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import Foundation
import MastodonMeta
import MetaTextKit
import MastodonCore
import UIKit

struct HtmlFormattingOptions {
    typealias AttributeDictionary = [NSAttributedString.Key: Any]
    
    enum Format: CaseIterable {
        case inlinePostPreview
        case fullPost
        case socialContextHeader
    }
    
    let format: Format
    
    var baseFontSize: CGFloat {
        switch format {
        case .inlinePostPreview:
            10
        case .fullPost:
            17
        case .socialContextHeader:
            13
        }
    }
    
    var textAttributes: AttributeDictionary {
        switch format {
        case .inlinePostPreview:
            [:]
        case .fullPost:
            [
                .font: UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: baseFontSize, weight: .regular)),
                .foregroundColor: UIColor.label,
            ]
        case .socialContextHeader:
            [
                .font: UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: baseFontSize, weight: .bold)),
                .foregroundColor: UIColor.secondaryLabel,
            ]
        }
    }
    
    var linkAttributes: AttributeDictionary {
        switch format {
        case .inlinePostPreview:
            [:]
        case .fullPost:
            [
                .font: UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: baseFontSize, weight: .semibold)),
                .foregroundColor: UIColor.link,
            ]
        case .socialContextHeader:
            [:]
        }
    }
    
    
    static var nilOptions: AttributeDictionary {
        return [:]
    }
}

fileprivate func metaTextForHtmlToAttributedStringConversion(options: HtmlFormattingOptions) -> MetaText {
    let meta = MetaText()
    meta.textAttributes = options.textAttributes
    meta.linkAttributes = options.linkAttributes
    return meta
}

fileprivate let metaTextsForConversion: [ HtmlFormattingOptions.Format : MetaText ] = {
    var dict = [ HtmlFormattingOptions.Format : MetaText ]()
    return HtmlFormattingOptions.Format.allCases.reduce(into: dict) { partialResult, format in
        partialResult[format] = metaTextForHtmlToAttributedStringConversion(options: HtmlFormattingOptions(format: format))
    }
}()

func attributedString(
    fromHtml html: String, emojis: [MastodonContent.Shortcode: String], withFormat format: HtmlFormattingOptions.Format? = .inlinePostPreview
) -> AttributedString {
    let content = MastodonContent(content: html, emojis: emojis)
    let metaText = metaTextsForConversion[format!]!
    metaText.reset()
    do {
        let metaContent = try MastodonMetaContent.convert(document: content)
        metaText.configure(
            content: metaContent)
        guard
            let nsAttributedString = metaText
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
