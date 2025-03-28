// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import Foundation
import MastodonSDK

enum AsyncBool {
    case unknown
    case fetching
    case isTrue
    case settingToTrue
    case isFalse
    case settingToFalse
}

class PostActionViewModel: ObservableObject {
    @Published var favorited: AsyncBool = .unknown
    @Published var boosted: AsyncBool = .unknown
    @Published var muted: AsyncBool = .unknown
    @Published var bookmarked: AsyncBool = .unknown
    @Published var pinned: AsyncBool = .unknown
}

struct MastodonPost {
    let id: Mastodon.Entity.Status.ID
    let metaData: PostMetadata
    let postType: MastodonPostType
}

extension MastodonPost {
    struct PostMetrics: Codable {
        let boostCount: Int
        let favoriteCount: Int
        let replyCount: Int
    }
}

extension MastodonPost {
    struct PostActions: Codable {
        var favorited: Bool
        var boosted: Bool
        var muted: Bool
        var bookmarked: Bool
        var pinned: Bool?
    }
}

extension MastodonPost {
    struct PostContent: Codable {
        let editedAt: Date?
        let language: String?
        let htmlWithEntities: HtmlWithEntities?
        let plainText: String?
        let contentWarned: ContentWarned
        let filtered: [Mastodon.Entity.ServerFilterResult]?
        let attachment: PostAttachment?
        let metrics: PostMetrics
        let myActions: PostActions

        struct HtmlWithEntities: Codable {
            let html: String?
            let mentions: [Mastodon.Entity.Mention]
            let tags: [Mastodon.Entity.Tag]
            let emojis: [Mastodon.Entity.Emoji]
        }

        enum PostAttachment: Codable {
            case media([Mastodon.Entity.Attachment])
            case poll(Mastodon.Entity.Poll)
            case linkPreviewCard(Mastodon.Entity.Card)
        }

        enum ContentWarned: Codable {
            case nothingToWarn
            case warnAll(reason: String)
            case warnMediaAttachmentOnly
        }
    }
}

enum MastodonPostType: Codable {
    case originalPost(
        content: MastodonPost.PostContent,
        inReplyTo: MastodonPost.InReplyToDetails?)
    case boost(boostedPostID: Mastodon.Entity.Status.ID)
    //    case quotePost(quotedPostID: Mastodon.Entity.Status.ID)
}

extension MastodonPost {
    struct PostMetadata: Codable {
        let author: Mastodon.Entity.Account
        let uriForFediverse: String
        let url: String?
        let privacyLevel: PrivacyLevel?
        let createdAt: Date
        let application: Mastodon.Entity.Application?
    }

    enum PrivacyLevel: Codable {
        case `public`
        case quietPublic
        case followersOnly
        case mentionedOnly
    }

    struct InReplyToDetails: Codable {
        let postID: Mastodon.Entity.Status.ID
        let accountID: Mastodon.Entity.Account.ID
    }
}

// MARK: -

protocol MastodonStatusDerived {
    static func fromStatus(_ status: Mastodon.Entity.Status) -> Self
}

protocol MastodonStatusDerivedOptional {
    static func fromStatus(_ status: Mastodon.Entity.Status) -> Self?
}

extension MastodonPost: MastodonStatusDerived {
    static func fromStatus(_ status: Mastodon.Entity.Status) -> Self {
        return Self(
            id: status.id,
            metaData: MastodonPost.PostMetadata.fromStatus(status),
            postType: MastodonPostType.fromStatus(status))
    }
}

extension MastodonPost.PostMetrics: MastodonStatusDerived {
    static func fromStatus(_ status: Mastodon.Entity.Status) -> Self {
        return Self(
            boostCount: status.reblogsCount,
            favoriteCount: status.favouritesCount,
            replyCount: status.repliesCount ?? 0)
    }
}

extension MastodonPost.PostActions: MastodonStatusDerived {
    static func fromStatus(_ status: Mastodon.Entity.Status) -> Self {
        return Self(
            favorited: status.favourited ?? false,
            boosted: status.reblogged ?? false, muted: status.muted ?? false,
            bookmarked: status.bookmarked ?? false, pinned: status.pinned)
    }
}

extension MastodonPost.PostContent: MastodonStatusDerived {
    static func fromStatus(_ status: Mastodon.Entity.Status) -> Self {
        return Self(
            editedAt: status.editedAt, language: status.language,
            htmlWithEntities: MastodonPost.PostContent.HtmlWithEntities
                .fromStatus(status), plainText: status.text,
            contentWarned: MastodonPost.PostContent.ContentWarned.fromStatus(
                status), filtered: status.filtered,
            attachment: MastodonPost.PostContent.PostAttachment.fromStatus(
                status), metrics: MastodonPost.PostMetrics.fromStatus(status),
            myActions: MastodonPost.PostActions.fromStatus(status))
    }
}

extension MastodonPost.PostContent.HtmlWithEntities: MastodonStatusDerived {
    static func fromStatus(_ status: Mastodon.Entity.Status) -> Self {
        return Self(
            html: status.content, mentions: status.mentions, tags: status.tags,
            emojis: status.emojis)
    }
}

extension MastodonPost.PostContent.PostAttachment: MastodonStatusDerivedOptional
{
    static func fromStatus(_ status: Mastodon.Entity.Status) -> Self? {
        if let attachedPoll = status.poll {
            return .poll(attachedPoll)
        } else if let card = status.card {
            return .linkPreviewCard(card)
        } else if let media = status.mediaAttachments, !media.isEmpty {
            return .media(media)
        } else {
            return nil
        }
    }
}

extension MastodonPost.PostContent.ContentWarned: MastodonStatusDerived {
    static func fromStatus(_ status: Mastodon.Entity.Status) -> Self {
        switch (status.sensitive, status.spoilerText) {
        case (true, nil):
            return .warnMediaAttachmentOnly
        case (true, _):
            return .warnAll(reason: status.spoilerText!)
        default:
            return .nothingToWarn
        }
    }
}

extension MastodonPost.PostMetadata: MastodonStatusDerived {
    static func fromStatus(_ status: Mastodon.Entity.Status) -> Self {
        return Self(
            author: status.account, uriForFediverse: status.uri,
            url: status.url,
            privacyLevel: MastodonPost.PrivacyLevel.fromStatus(status),
            createdAt: status.createdAt, application: status.application)
    }
}

extension MastodonPost.PrivacyLevel: MastodonStatusDerivedOptional {
    static func fromStatus(_ status: Mastodon.Entity.Status) -> Self? {
        switch status.visibility {
        case .public:
            return .public
        case .unlisted:
            return .quietPublic
        case .private:
            return .followersOnly
        case .direct:
            return .mentionedOnly
        case ._other(let string):
            assertionFailure("unexpected privacy level")
            return nil
        case .none:
            return nil
        }
    }
}

extension MastodonPost.InReplyToDetails: MastodonStatusDerivedOptional {
    static func fromStatus(_ status: Mastodon.Entity.Status) -> Self? {
        guard let post = status.inReplyToID,
            let account = status.inReplyToAccountID
        else { return nil }
        return MastodonPost.InReplyToDetails(postID: post, accountID: account)
    }
}

extension MastodonPostType: MastodonStatusDerived {
    static func fromStatus(_ status: Mastodon.Entity.Status) -> Self {
        // TODO: add quote post option here
        if let boost = status.reblog {
            return .boost(boostedPostID: boost.id)
        } else {
            return .originalPost(
                content: MastodonPost.PostContent.fromStatus(status),
                inReplyTo: MastodonPost.InReplyToDetails.fromStatus(status))
        }
    }
}
