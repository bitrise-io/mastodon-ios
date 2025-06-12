// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import Foundation
import MastodonSDK

extension GenericMastodonPost {
    static func fromStatus(_ status: Mastodon.Entity.Status) -> GenericMastodonPost {
        if let reblog = status.reblog {
            return MastodonBoostPost(id: status.id, metaData: PostMetadata.fromStatus(status), boostedPost: GenericMastodonPost.fromStatus(reblog) as! MastodonContentPost, _legacyEntity: status)
        }
//        else if let quote = status.quote {
//        }
        else {
            return MastodonBasicPost(id: status.id, metaData: PostMetadata.fromStatus(status), content: PostContent.fromStatus(status), inReplyTo: InReplyToDetails.fromStatus(status), attachment: PostAttachment.fromStatus(status), _legacyEntity: status)
        }
    }
    
}

extension GenericMastodonPost {
    func byReplacingActionablePost(with updatedPost: GenericMastodonPost) throws -> GenericMastodonPost {
        if let basicPost = self as? MastodonBasicPost {
            guard basicPost.id == updatedPost.id else {
                throw PostActionFailure.postIdMismatch }
            return updatedPost
        } else if let boostPost = self as? MastodonBoostPost {
            guard boostPost.boostedPost.id == updatedPost.id, let updatedPost = updatedPost as? MastodonContentPost else {
                throw PostActionFailure.postIdMismatch }
            return MastodonBoostPost(id: boostPost.id, metaData: boostPost.metaData, boostedPost: updatedPost, _legacyEntity: updatedPost._legacyEntity)
        } else {
            assertionFailure("not implemented")
            return self
        }
    }
}

class MastodonContentPost: GenericMastodonPost {
    let content: GenericMastodonPost.PostContent
    
    init(id: Mastodon.Entity.Status.ID, metaData: GenericMastodonPost.PostMetadata, content: GenericMastodonPost.PostContent, _legacyEntity: Mastodon.Entity.Status) {
        self.content = content
        super.init(id: id, metaData: metaData, _legacyEntity: _legacyEntity)
    }
    
    enum CodingKeys: String, CodingKey {
        case content
    }
    
    required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let content = try container.decode(GenericMastodonPost.PostContent.self, forKey: .content)
        self.content = content
        try super.init(from: decoder)
    }
}

class MastodonBasicPost: MastodonContentPost {
    let inReplyTo: GenericMastodonPost.InReplyToDetails?
    let attachment: GenericMastodonPost.PostAttachment?
    
    init(id: Mastodon.Entity.Status.ID, metaData: GenericMastodonPost.PostMetadata, content: GenericMastodonPost.PostContent, inReplyTo: GenericMastodonPost.InReplyToDetails?, attachment: GenericMastodonPost.PostAttachment?, _legacyEntity: Mastodon.Entity.Status) {
        self.inReplyTo = inReplyTo
        self.attachment = attachment
        super.init(id: id, metaData: metaData, content: content, _legacyEntity: _legacyEntity)
    }
    
    enum CodingKeys: String, CodingKey {
        case inReplyTo
        case attachment
    }
    
    required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let inReplyTo = try container.decode(GenericMastodonPost.InReplyToDetails.self, forKey: .inReplyTo)
        let attachment = try container.decode(GenericMastodonPost.PostAttachment.self, forKey: .attachment)
        self.inReplyTo = inReplyTo
        self.attachment = attachment
        try super.init(from: decoder)
    }
}

class MastodonBoostPost: GenericMastodonPost {
    let boostedPost: MastodonContentPost
    
    init(id: Mastodon.Entity.Status.ID, metaData: GenericMastodonPost.PostMetadata, boostedPost: MastodonContentPost, _legacyEntity: Mastodon.Entity.Status) {
        self.boostedPost = boostedPost
        super.init(id: id, metaData: metaData, _legacyEntity: _legacyEntity)
    }
    
    enum CodingKeys: String, CodingKey {
        case boostedPost
    }
    
    required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let boostedPost = try container.decode(MastodonContentPost.self, forKey: .boostedPost)
        self.boostedPost = boostedPost
        try super.init(from: decoder)
    }
}

class MastodonQuotePost: MastodonContentPost {
    let quotedPost: MastodonBasicPost
    
    init(id: Mastodon.Entity.Status.ID, content: GenericMastodonPost.PostContent, metaData: GenericMastodonPost.PostMetadata, quotedPost: MastodonBasicPost, _legacyEntity: Mastodon.Entity.Status) {
        self.quotedPost = quotedPost
        super.init(id: id, metaData: metaData, content: content, _legacyEntity: _legacyEntity)
    }

    enum CodingKeys: String, CodingKey {
        case quotedPost
    }
    
    required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let quotedPost = try container.decode(MastodonBasicPost.self, forKey: .quotedPost)
        self.quotedPost = quotedPost
        try super.init(from: decoder)
    }
}
