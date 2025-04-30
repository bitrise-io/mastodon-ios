// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import Foundation
import MastodonSDK

extension GenericMastodonPost {
    static func fromStatus(_ status: Mastodon.Entity.Status) -> GenericMastodonPost {
        if let reblog = status.reblog {
            return MastodonBoostPost(id: status.id, metaData: PostMetadata.fromStatus(status), boostedPost: GenericMastodonPost.fromStatus(reblog) as! MastodonContentPost)
        }
//        else if let quote = status.quote {
//        }
        else {
            return MastodonBasicPost(id: status.id, metaData: PostMetadata.fromStatus(status), content: PostContent.fromStatus(status), inReplyTo: InReplyToDetails.fromStatus(status), attachment: PostAttachment.fromStatus(status))
        }
    }
    
}

class MastodonContentPost: GenericMastodonPost {
    let content: GenericMastodonPost.PostContent
    
    init(id: Mastodon.Entity.Status.ID, metaData: GenericMastodonPost.PostMetadata, content: GenericMastodonPost.PostContent) {
        self.content = content
        super.init(id: id, metaData: metaData)
    }
}

class MastodonBasicPost: MastodonContentPost {
    let inReplyTo: GenericMastodonPost.InReplyToDetails?
    let attachment: GenericMastodonPost.PostAttachment?
    
    init(id: Mastodon.Entity.Status.ID, metaData: GenericMastodonPost.PostMetadata, content: GenericMastodonPost.PostContent, inReplyTo: GenericMastodonPost.InReplyToDetails?, attachment: GenericMastodonPost.PostAttachment?) {
        self.inReplyTo = inReplyTo
        self.attachment = attachment
        super.init(id: id, metaData: metaData, content: content)
    }
}

class MastodonBoostPost: GenericMastodonPost {
    let boostedPost: MastodonContentPost
    
    init(id: Mastodon.Entity.Status.ID, metaData: GenericMastodonPost.PostMetadata, boostedPost: MastodonContentPost) {
        self.boostedPost = boostedPost
        super.init(id: id, metaData: metaData)
    }
}

class MastodonQuotePost: MastodonContentPost {
    let quotedPost: MastodonBasicPost
    
    init(id: Mastodon.Entity.Status.ID, content: GenericMastodonPost.PostContent, metaData: GenericMastodonPost.PostMetadata, quotedPost: MastodonBasicPost) {
        self.quotedPost = quotedPost
        super.init(id: id, metaData: metaData, content: content)
    }
}
