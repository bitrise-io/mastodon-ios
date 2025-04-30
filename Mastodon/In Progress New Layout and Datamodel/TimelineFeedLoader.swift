// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import Combine
import Foundation
import MastodonCore
import MastodonSDK

enum TimelineItem: Identifiable {
    case post(GenericMastodonPost)
    case missingPosts(newerThan: Mastodon.Entity.Status.ID, olderThan: Mastodon.Entity.Status.ID, timeGapDescription: String)
    
    var id: String {
        switch self {
        case .post(let post):
            return post.id
        case .missingPosts(let newerThan, let olderThan, let gapDescription):
            return "\(newerThan)-\(olderThan) (\(gapDescription))"
        }
    }
    
    static func gapBetween(_ olderItem: TimelineItem?, newerItem: TimelineItem?) -> TimelineItem? {
        switch (olderItem, newerItem) {
        case (.post(let olderPost), .post(let newerPost)):
            return .missingPosts(newerThan: olderPost.id, olderThan: newerPost.id, timeGapDescription: olderPost.metaData.createdAt.localizedExtremelyAbbreviatedTimeElapsedUntil(now: newerPost.metaData.createdAt))
        default:
            return nil
        }
    }
}

extension TimelineItem: Equatable {
    static func == (lhs: TimelineItem, rhs: TimelineItem) -> Bool {
        return lhs.id == rhs.id
    }
}

extension TimelineItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@MainActor
final class TimelineFeedLoader: MastodonFeedLoader<TimelineItem, CacheableTimeline> {
    private let authenticatedUser: MastodonAuthenticationBox
    
    private var currentCache: CacheableTimeline?
    
    init(currentUser: MastodonAuthenticationBox) {
        authenticatedUser = currentUser
        super.init(nil)
    }
    
    override func fetchResults(for request: MastodonFeedLoaderRequest) async throws -> CacheableTimeline {
        let olderThan: String?
        let newerThan: String?
        switch request {
        case .newer:
            olderThan = nil
            newerThan = {
                switch records.allRecords.count {
                case 0, 1:
                    return records.allRecords.first?.id
                default:
                    return records.allRecords[1].id  // we want to allow the possibility of an overlap in order to detect gaps
                }
            }()
        case .older:
            olderThan = records.allRecords.last?.id
            newerThan = nil
        case .reload:
            olderThan = nil
            newerThan = nil
        }
        
        await AuthenticationServiceProvider.shared.fetchAccounts(onlyIfItHasBeenAwhile: true) // TODO: legacy comments indicated this may not be the best place for this call

        let response = try await APIService.shared.homeTimeline(sinceID: newerThan, maxID: olderThan, authenticationBox: authenticatedUser)
        let newCache = CacheableTimeline(older: currentCache?.items ?? [], statuses: response.value)
        currentCache = newCache
        return newCache
    }
    
    override func filteredResults(fromCachedType cached: CacheableTimeline) -> [TimelineItem] {
        cached.filteredPosts
    }
}

struct CacheableTimeline: CacheableFeed {
    
    let items: [TimelineItem]
    
    var filteredPosts: [TimelineItem] {
        return items.filter { item in
            switch item {
            case .missingPosts:
                return true
            case .post(let post):
                if let contentPost = post as? MastodonContentPost {
                    return !contentPost.content.shouldBeRemovedFromFeed
                } else if let boost = post as? MastodonBoostPost {
                    return !boost.boostedPost.content.shouldBeRemovedFromFeed
                } else {
                    assertionFailure("unexpected post type")
                    return true
                }
            }
        }
    }
    
    var hasResults: Bool {
        return !items.isEmpty
    }
 
    init(older: [TimelineItem], statuses: [Mastodon.Entity.Status]) {
        let newBatch = statuses.map { status in
            let post = GenericMastodonPost.fromStatus(status)
            return TimelineItem.post(post)
        }
        
        var combined: [TimelineItem]
        
        let oldestIdInNewBatch = newBatch.last(where: { item in
            switch item {
            case .missingPosts: return false
            case .post: return true
            }
        })?.id
        
        if let oldestIdInNewBatch {
            let overlapIndex = older.firstIndex(where: { item in
                switch item {
                case .post:
                    return item.id == oldestIdInNewBatch
                case .missingPosts:
                    return false
                }
            })
            if let overlapIndex {
                let firstOlderIndexToRetain = overlapIndex + 1
                if firstOlderIndexToRetain < older.count {
                    let olderTail = older.suffix(from: firstOlderIndexToRetain)
                    combined = newBatch + olderTail
                } else {
                    combined = newBatch
                }
            } else if let gapItem = TimelineItem.gapBetween(older.first, newerItem: newBatch.last) {
                combined = newBatch + [gapItem] + older
            } else {
                assert(older.isEmpty, "How else did we get here?")
                combined = newBatch + older
            }
        } else {
            assert(newBatch.isEmpty, "How else did we get here?")
            combined = older
        }
        
        items = combined
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

extension GenericMastodonPost.PostContent {
    var shouldBeRemovedFromFeed: Bool {
        guard let filterResults = filtered else { return false }
        for result in filterResults {
            if result.filter.filterAction == .hide {
                return true
            }
        }
        return false
    }
}
