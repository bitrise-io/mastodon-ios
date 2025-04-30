// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import Combine
import Foundation
import MastodonSDK

enum TimelineItem: Identifiable {
    case post(GenericMastodonPost)
    case missingPosts(newerThan: (Mastodon.Entity.Status.ID, Date), olderThan: (Mastodon.Entity.Status.ID, Date))
    
    var id: String {
        switch self {
        case .post(let post):
            return post.id
        case .missingPosts(let newerThan, let olderThan):
            return "\(newerThan)-\(olderThan)"
        }
    }
}

@MainActor
final class TimelineFeedLoader: MastodonFeedLoader<TimelineItem, CacheableTimeline> {
    
    var currentCache: CacheableTimeline?
    
    override func fetchResults(for request: MastodonFeedLoaderRequest) async throws -> CacheableTimeline {
        let olderThan: String?
        let newerThan: String?
        switch request {
        case .newer:
            olderThan = nil
            newerThan = records.allRecords.first?.id
        case .older:
            olderThan = records.allRecords.last?.id
            newerThan = nil
        case .reload:
            olderThan = nil
            newerThan = nil
        }
        
        assertionFailure("not implemented")
        return CacheableTimeline(previous: [], statuses: [])
    }
    
    override func filteredResults(fromCachedType cached: CacheableTimeline) -> [TimelineItem] {
        cached.filteredPosts
    }
}

struct CacheableTimeline: CacheableFeed {
    
    let items: [TimelineItem]
    
    var filteredPosts: [TimelineItem] {
    // TODO: if the content is filtered to hide, then nothing that points to it should be included in the filtered results.
        return items
    }
    
    var hasResults: Bool {
        return !items.isEmpty
    }
 
    init(previous: [TimelineItem], statuses: [Mastodon.Entity.Status]) {
        assertionFailure("not implemented")
        items = []
    }
}

@MainActor
class TimelineCacheManager: MastodonFeedCacheManager {
    typealias CachedType = CacheableTimeline
    
    func currentResults() -> CacheableTimeline? {
        fatalError("not implemented")
    }
    
    var mostRecentlyFetchedResults: CacheableTimeline?
    
    func updateByInserting(newlyFetched: CacheableTimeline, at insertionPoint: MastodonFeedLoaderRequest.InsertLocation) {
        fatalError("not implemented")
    }
    
    var currentLastReadMarker: LastReadMarkers.MarkerPosition?
    
    func didFetchMarkers(_ updatedMarkers: MastodonSDK.Mastodon.Entity.Marker) {
        fatalError("not implemented")
    }
    
    func updateToNewerMarker(_ newMarker: LastReadMarkers.MarkerPosition, enforceForwardProgress: Bool) {
        fatalError("not implemented")
    }
    
    func commitToCache() async {
        fatalError("not implemented")
    }
    
    
}

@MainActor
class MastodonPostViewModel: ObservableObject {
    let post: GenericMastodonPost
    
    @Published var favorited: AsyncBool = .unknown
    @Published var boosted: AsyncBool = .unknown
    @Published var muted: AsyncBool = .unknown
    @Published var bookmarked: AsyncBool = .unknown
    @Published var pinned: AsyncBool = .unknown
    
    init(post: GenericMastodonPost) {
        self.post = post
        let actionablePost: MastodonContentPost?
        if let contentPost = post as? MastodonContentPost {
            actionablePost = contentPost
        } else if let boost = post as? MastodonBoostPost {
            actionablePost = boost.boostedPost
        } else {
            actionablePost = nil
        }
        
        guard let actionablePost else {
            assertionFailure("unexpected post type")
            favorited = .unknown
            boosted = .unknown
            muted = .unknown
            bookmarked = .unknown
            pinned = .unknown
            return
        }
        
        let myActions = actionablePost.content.myActions
        favorited = AsyncBool.fromBool(myActions.favorited)
        boosted = AsyncBool.fromBool(myActions.boosted)
        muted = AsyncBool.fromBool(myActions.muted)
        bookmarked = AsyncBool.fromBool(myActions.bookmarked)
        pinned = AsyncBool.fromBool(myActions.pinned)
    }
}

enum AsyncBool {
    case unknown
    case fetching
    case isTrue
    case settingToTrue
    case isFalse
    case settingToFalse
    
    static func fromBool(_ value: Bool?) -> AsyncBool {
        guard let value else { return .unknown }
        if value {
            return .isTrue
        } else {
            return .isFalse
        }
    }
}
