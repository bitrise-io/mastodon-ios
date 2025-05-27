// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import MastodonSDK
import MastodonMeta
import MetaTextKit
import SwiftUI

public enum TextViewWithCustomEmoji {
    public typealias Emojis = [Mastodon.Entity.Emoji]
    
    case timelinePost(html: String, emojis: Emojis, didSelect: (Meta)->())
    case authorHeader(html: String, emojis: Emojis)
    case socialContextHeader(html: String, emojis: Emojis, isPrivate: Bool)
    case linkPreviewCardAuthorButton(html: String, emojis: Emojis)
    case pollOption(html: String, emojis: Emojis)
}

extension TextViewWithCustomEmoji: View {
    public var body: some View {
        switch self {
        case .timelinePost(let html, let emojis, let didSelect):
            MetaTextViewSwiftUI(html: html, emojis: emojis, format: .fullPost, didSelectMeta: didSelect)
        case .authorHeader(let html, let emojis):
            MetaTextViewSwiftUI(html: html, emojis: emojis, format: .authorHeader)
        case .socialContextHeader(let html, let emojis, let isPrivate):
            MetaTextViewSwiftUI(html: html, emojis: emojis, format: isPrivate ? .socialContextHeaderPrivate : .socialContextHeader)
        case .linkPreviewCardAuthorButton(let html, let emojis):
            MetaTextViewSwiftUI(html: html, emojis: emojis, format: .linkPreviewCardAuthor)
        case .pollOption(let html, let emojis):
            MetaTextViewSwiftUI(html: html, emojis: emojis, format: .pollOption)
        }
    }
}

func mapEmojiShortcodeToEmojis(_ emojis: TextViewWithCustomEmoji.Emojis) -> [MastodonContent.Shortcode: String] {
    return emojis.reduce(into: [:]) { partialResult, emoji in
        partialResult[emoji.shortcode] = UserDefaults.standard.preferredStaticAvatar ? emoji.staticURL : emoji.url
    }
}

struct MetaTextViewSwiftUI: UIViewRepresentable {
    
    let html: String
    let emojis: [Mastodon.Entity.Emoji]
    let format: MastodonHtmlFormat
    let metaText: MetaText
    let metaTapHandler: MetaTapHandler?
    
    init(html: String, emojis: [Mastodon.Entity.Emoji], format: MastodonHtmlFormat, didSelectMeta: ((Meta)->())? = nil) {
        self.html = html
        self.emojis = emojis
        self.format = format
        self.metaText = format.metaText
        if let didSelectMeta {
            self.metaTapHandler = MetaTapHandler(onTap: didSelectMeta)
        } else {
            self.metaTapHandler = nil
        }
    }
    
    public func makeUIView(context: Context) -> MetaTextView {
        let metaText = format.metaText
        metaText.textView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        metaText.textView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        metaText.textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        
        // Remove padding so that layout plays reasonably nicely with SwiftUI
        metaText.textView.textContainerInset = .zero
        metaText.textView.textContainer.lineFragmentPadding = 0
        
        // Disable scrolling and editing
        metaText.textView.isEditable = false
        metaText.textView.isScrollEnabled = false
        
        metaText.textView.linkDelegate = metaTapHandler
        
        return metaText.textView
    }
    
    func updateUIView(_ uiView: MetaTextView, context: Context) {
        let content = MastodonContent(content: html, emojis:  mapEmojiShortcodeToEmojis(emojis))
        if let metaContent = try? MastodonMetaContent.convert(document: content) {
            metaText.configure(content: metaContent)
            uiView.attributedText = metaText.textView.attributedText
            uiView.backgroundColor = .clear
        }
    }
    
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MetaTextView, context: Context) -> CGSize? {
        uiView.sizeThatFits(.init(width: proposal.width ?? .infinity, height: proposal.height ?? .infinity))
    }
}

class MetaTapHandler: MetaTextViewDelegate {
    let onTap: (Meta)->()
    
    init(onTap: @escaping (Meta) -> Void) {
        self.onTap = onTap
    }
    
    func metaTextView(_ metaTextView: MetaTextKit.MetaTextView, didSelectMeta meta: Meta) {
        onTap(meta)
    }
}
