// Copyright © 2025 Mastodon gGmbH. All rights reserved.

@MainActor
final class TimelineFeedLoader: MastodonFeedLoader<MastodonPost, CacheableTimeline> {
    
}

extension MastodonPost: Identifiable {
    
}

struct CacheableTimeline: CacheableFeed {
    
    let posts: [MastodonPost]
    
    var hasResults: Bool {
        return !posts.isEmpty
    }
}
