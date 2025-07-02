// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import MastodonSDK
import MastodonMeta
import SwiftUI
import MastoParse

public enum TextViewWithCustomEmoji {
    public typealias Emojis = [Mastodon.Entity.Emoji]
    
    case timelinePost(heightCacheID: String, html: String, emojis: Emojis)
    case authorHeader(html: String, emojis: Emojis)
    case socialContextHeader(html: String, emojis: Emojis, isPrivate: Bool)
    case linkPreviewCardAuthorButton(html: String, emojis: Emojis)
    case pollOption(html: String, emojis: Emojis)
}

extension TextViewWithCustomEmoji: View {
    public var body: some View {
            switch self {
            case .timelinePost(let id, let html, let emojis):
                if let blocks = try? getParseBlocks(from: html) {
                    TimelinePostContentView(contentBlocks: blocks)
                }
            case .authorHeader(let html, let emojis):
                if let blocks = try? getParseBlocks(from: html) {
                    TimelinePostContentView(contentBlocks: blocks)
                }
            case .socialContextHeader(let html, let emojis, let isPrivate):
                    if let blocks = try? getParseBlocks(from: html) {
                        TimelinePostContentView(contentBlocks: blocks)
                    }
            case .linkPreviewCardAuthorButton(let html, let emojis):
                    if let blocks = try? getParseBlocks(from: html) {
                        TimelinePostContentView(contentBlocks: blocks)
                    }
            case .pollOption(let html, let emojis):
                    if let blocks = try? getParseBlocks(from: html) {
                        TimelinePostContentView(contentBlocks: blocks)
                    }
            }
    }
}

func mapEmojiShortcodeToEmojis(_ emojis: TextViewWithCustomEmoji.Emojis) -> [MastodonContent.Shortcode: String] {
    return emojis.reduce(into: [:]) { partialResult, emoji in
        partialResult[emoji.shortcode] = UserDefaults.standard.preferredStaticAvatar ? emoji.staticURL : emoji.url
    }
}

class CalculatedHeightCache {
    var cache = NSCache<NSString, NSNumber>()
    var lastProposedWidth: Int = 0 {
        didSet {
            cache.removeAllObjects()
        }
    }
    func cachedHeight(for id: String, withProposedWidth proposedWidth: CGFloat) -> CGFloat? {
        let intWidth = Int(proposedWidth)
        guard lastProposedWidth == intWidth else {
            lastProposedWidth = intWidth
            return nil
        }
        let key = NSString(string: id)
        if let object = cache.object(forKey: key) {
            return object.doubleValue
        } else {
            return nil
        }
    }
    func cache(height: CGFloat, forProposedWidth proposedWidth: CGFloat, forID id: String) {
        let intWidth = Int(proposedWidth)
        if lastProposedWidth != intWidth {
            lastProposedWidth = intWidth
        }
        cache.setObject(NSNumber(floatLiteral: height), forKey: NSString(string: id))
    }
}


struct TimelinePostContentView: View {
    let contentBlocks: [MastoParseContentBlock]
    
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(contentBlocks) { block in
                if let blockquote = block as? MastoParseBlockquote {
                    BlockquoteView(block: blockquote)
                } else if let row = block as? MastoParseContentRow {
                    RowView(row: row)
                } else {
                    Text("CASE NOT HANDLED")
                }
            }
        }
    }
}

let indent: CGFloat = 16
let nestedBlockQuoteIndicatorWidth: CGFloat = 2
let indicatorToBlockQuoteSpacing: CGFloat = 4

let blockquoteColor = Color.purple.opacity(0.5)
struct BlockquoteView: View {
    let block: MastoParseBlockquote
    
    var body: some View {
        HStack {
            VStack {
                Image(systemName: "quote.opening")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(blockquoteColor)
                
                Spacer()
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(block.contents.enumerated()), id: \.offset) { idx, element in
                    RowView(row: element)
                }
            }
        }
    }
}

enum TextElement {
    case image(Image)
    case text(LocalizedStringKey)
    case code(String)
}

struct RowView: View {
    static let font: Font.TextStyle = .body
    @ScaledMetric(relativeTo: font) private var imgBaseline: CGFloat = -5 // without this, the custom emoji sit too high amidst the surrounding text
    
    let row: MastoParseContentRow
    
    var body: some View {
        let totalFormattingSpaceRequired = row.nestedFormatting.reduce(into: CGFloat.zero) { partialResult, format in
            switch format {
            case .listLevel:
                partialResult += indent
            case .subordinateBlockquote:
                partialResult += nestedBlockQuoteIndicatorWidth + indicatorToBlockQuoteSpacing
            case .topLevelBlockquote:
                break
            }
        }
        
        combineElements(row.contents.map({ element in
            switch element.type {
            case .text:
                return .text(LocalizedStringKey(element.contents))
            case .code:
                return .code(element.contents)
            }
            
        }))
        .padding(EdgeInsets(top: 0, leading: totalFormattingSpaceRequired, bottom: 0, trailing: 0))
        .background() {
            // Putting the nested blockquote bar in a background correctly expands its height to match the contents of the row. Trying to include it in the same HStack as the content leaves the bar too short.
            HStack(spacing: 0) {
                ForEach(Array(row.nestedFormatting.enumerated()), id: \.offset) { idx, indicator in
                    switch indicator {
                    case .topLevelBlockquote:
                        EmptyView()
                    case .subordinateBlockquote:
                        blockquoteColor
                            .frame(width: nestedBlockQuoteIndicatorWidth)
                        Spacer()
                            .frame(maxWidth: indicatorToBlockQuoteSpacing)
                    case .listLevel:
                        Spacer()
                            .frame(width: indent)
                    }
                }
                Spacer()
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    @ViewBuilder func combineElements(_ elements: [TextElement]) -> some View {
        let pieces = elements.map { element in
            switch element {
            case .image(let image):
                return Text("\(image)").baselineOffset(imgBaseline)
            case .text(let text):
                return Text(text)
            case .code(let text):
                var attributed = AttributedString(text)
                attributed.backgroundColor = blockquoteColor
                attributed.font = .system(.body, design: .monospaced)
                return Text(attributed)
            }
        }
        pieces.reduce(Text(""), +)
            .fixedSize(horizontal: false, vertical: true)
    }
}
