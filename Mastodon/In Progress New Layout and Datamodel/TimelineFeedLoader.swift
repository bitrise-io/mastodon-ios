// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import Combine
import Foundation
import MastodonCore
import MastodonSDK

enum TimelineItem: Identifiable {
    case post(GenericMastodonPost)
    case missingPosts(newerThan: Mastodon.Entity.Status.ID, olderThan: Mastodon.Entity.Status.ID, timeGapDescription: String)
    case loadingIndicator
    
    var id: String {
        switch self {
        case .post(let post):
            return post.id
        case .missingPosts(let newerThan, let olderThan, let gapDescription):
            return "\(newerThan)-\(olderThan) (\(gapDescription))"
        case .loadingIndicator:
            return "loading..."
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

fileprivate let relationshipStaleThreshold: TimeInterval = 20 /*min*/ * 60 /*sec*/

@MainActor
final class TimelineFeedLoader: MastodonFeedLoader<TimelineItem, CacheableTimeline> {
    private let authenticatedUser: MastodonAuthenticationBox
    private let authenticatedUserID: Mastodon.Entity.Account.ID?
    private var cachedRelationships = [Mastodon.Entity.Account.ID : MastodonAccount.Relationship]()
    
    init(currentUser: MastodonAuthenticationBox) {
        authenticatedUser = currentUser
        authenticatedUserID = authenticatedUser.cachedAccount?.id
        if let authenticatedUserID {
            cachedRelationships[authenticatedUserID] = .isMe
        }
        super.init(TimelineCacheManager(currentUser: currentUser))
    }
    
    func myRelationship(to accountID: Mastodon.Entity.Account.ID) -> MastodonAccount.Relationship {
        if accountID == authenticatedUserID {
            return .isMe
        } else {
            return cachedRelationships[accountID] ?? .isNotMe(nil)
        }
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
        let newBatch = response.value.map { status in
            let post = GenericMastodonPost.fromStatus(status)
            return TimelineItem.post(post)
        }
        let newCache = CacheableTimeline(older: [], newer: newBatch)
        
        try await fetchRelationships(newCache)
        
        return newCache
    }
    
    override func filteredResults(fromCachedType cached: CacheableTimeline) -> [TimelineItem] {
        cached.filteredPosts
    }
    
    private func fetchRelationships(_ timeline: CacheableTimeline) async throws {
        let needToFetch: [Mastodon.Entity.Account.ID] = timeline.filteredPosts.compactMap { item -> Mastodon.Entity.Account.ID? in
            switch item {
            case .loadingIndicator, .missingPosts:
                return nil
            case .post(let post):
                if let actionableRelationshipAccountID = post.actionablePost?.metaData.author.id {
                    switch self.cachedRelationships[actionableRelationshipAccountID] {
                    case .isMe:
                        return nil
                    case .isNotMe(let info):
                        if let lastFetched = info?.fetchedAt {
                            return (lastFetched.timeIntervalSinceNow < relationshipStaleThreshold) ? nil : actionableRelationshipAccountID
                        } else {
                            return actionableRelationshipAccountID
                        }
                    case .none:
                        return actionableRelationshipAccountID
                    }
                } else {
                    return nil
                }
            }
        }
        
        let relationships = try await APIService.shared.relationship(forAccountIds: needToFetch, authenticationBox: authenticatedUser).value
        let currentTimestamp = Date.now
        for relationshipEntity in relationships {
            cachedRelationships[relationshipEntity.id] = MastodonAccount.Relationship.isNotMe(MastodonAccount.RelationshipInfo(relationshipEntity, fetchedAt: currentTimestamp))
        }
    }
}

struct CacheableTimeline: CacheableFeed {
    
    let items: [TimelineItem]
    
    var filteredPosts: [TimelineItem] {
        return items.filter { item in
            switch item {
            case .missingPosts, .loadingIndicator:
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
 
    init(older: [TimelineItem], newer: [TimelineItem]) {
        var combined: [TimelineItem]
        
        let oldestIdInNewBatch = newer.last(where: { item in
            switch item {
            case .missingPosts, .loadingIndicator: return false
            case .post: return true
            }
        })?.id
        
        if let oldestIdInNewBatch {
            let overlapIndex = older.firstIndex(where: { item in
                switch item {
                case .post:
                    return item.id == oldestIdInNewBatch
                case .missingPosts, .loadingIndicator:
                    return false
                }
            })
            if let overlapIndex {
                let firstOlderIndexToRetain = overlapIndex + 1
                if firstOlderIndexToRetain < older.count {
                    let olderTail = older.suffix(from: firstOlderIndexToRetain)
                    combined = newer + olderTail
                } else {
                    combined = newer
                }
            } else if let gapItem = TimelineItem.gapBetween(older.first, newerItem: newer.last) {
                combined = newer + [gapItem] + older
            } else {
                assert(older.isEmpty, "How else did we get here?")
                combined = newer + older
            }
        } else {
            assert(newer.isEmpty, "How else did we get here?")
            combined = older
        }
        
        items = combined
    }
}

@MainActor
class TimelineCacheManager: MastodonFeedCacheManager {
    typealias CachedType = CacheableTimeline
    
    private let currentUser: MastodonAuthenticationBox
    
    init(currentUser: MastodonAuthenticationBox) {
        self.currentUser = currentUser
    }
    
    func currentResults() -> CacheableTimeline? {
        return mostRecentlyFetchedResults
    }
    
    var mostRecentlyFetchedResults: CacheableTimeline?
    
    func updateByInserting(newlyFetched: CacheableTimeline, at insertionPoint: MastodonFeedLoaderRequest.InsertLocation) {
        switch insertionPoint {
        case .start:
            mostRecentlyFetchedResults = CacheableTimeline(older: currentResults()?.items ?? [], newer: newlyFetched.items)
        case .end:
            mostRecentlyFetchedResults = CacheableTimeline(older: newlyFetched.items, newer: currentResults()?.items ?? [])
        case .replace:
            mostRecentlyFetchedResults = newlyFetched
        }
    }
    
    var currentLastReadMarker: LastReadMarkers.MarkerPosition?
    
    func didFetchMarkers(_ updatedMarkers: MastodonSDK.Mastodon.Entity.Marker) {
        // TODO: implement
    }
    
    func updateToNewerMarker(_ newMarker: LastReadMarkers.MarkerPosition, enforceForwardProgress: Bool) {
        // TODO: implement
    }
    
    func commitToCache() async {
        // TODO: implement
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
