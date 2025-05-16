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
            if newerPost.metaData.createdAt.timeIntervalSince(olderPost.metaData.createdAt) < 120 {
                return .missingPosts(newerThan: olderPost.id, olderThan: newerPost.id, timeGapDescription: "")
            } else {
                let gapDescription = olderPost.metaData.createdAt.localizedExtremelyAbbreviatedTimeElapsedUntil(now: newerPost.metaData.createdAt)
                return .missingPosts(newerThan: olderPost.id, olderThan: newerPost.id, timeGapDescription: gapDescription)
            }
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
    private let filterContext = Mastodon.Entity.FilterContext.home
    
    private let authenticatedUser: MastodonAuthenticationBox
    private let authenticatedUserID: Mastodon.Entity.Account.ID?
    private var cachedRelationships = [Mastodon.Entity.Account.ID : MastodonAccount.Relationship]()
    private var accountsCache = [Mastodon.Entity.Account.ID : MastodonAccount]()
    private var contentConcealViewModels = [Mastodon.Entity.Status.ID : ContentConcealViewModel]()
    
    init(currentUser: MastodonAuthenticationBox) {
        authenticatedUser = currentUser
        authenticatedUserID = authenticatedUser.cachedAccount?.id
        if let authenticatedUserID {
            cachedRelationships[authenticatedUserID] = .isMe
        }
        super.init(TimelineCacheManager(currentUser: currentUser))
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
            olderThan = {
                let count = records.allRecords.count
                switch count {
                case 0, 1:
                    return records.allRecords.last?.id
                default:
                    return records.allRecords[count - 2].id  // we want to allow the possibility of an overlap in order to detect gaps
                }
            }()
            newerThan = nil
        case .reload:
            olderThan = nil
            newerThan = nil
        case .newerThan(let id):
            olderThan = nil
            newerThan = id
        case .olderThan(let id):
            olderThan = id
            newerThan = nil
        }
        
        await AuthenticationServiceProvider.shared.fetchAccounts(onlyIfItHasBeenAwhile: true) // TODO: legacy comments indicated this may not be the best place for this call

        let response = try await APIService.shared.homeTimeline(sinceID: newerThan, maxID: olderThan, authenticationBox: authenticatedUser)
        let newBatch = response.value.map { status in
            let post = GenericMastodonPost.fromStatus(status)
            return TimelineItem.post(post)
        }
        let newCache = CacheableTimeline(older: [], newer: newBatch)
        
        createContentConcealViewModels(newCache)
        try await fetchRelationships(newCache)
        try? await fetchReplyTos(newCache)
        
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
    
    init(inserting: [TimelineItem], into existingItems: [TimelineItem], asOlderThan: String) {
        // Assume that there should have been a gap item at the requested insertion point.
        let matchingGapItemIndex = existingItems.firstIndex { item in
            switch item {
            case .loadingIndicator, .post:
                return false
            case .missingPosts(_, let olderThan, _):
                return olderThan == asOlderThan
            }
        }
        guard let matchingGapItemIndex else { assertionFailure(); items = existingItems; return }
        
        var updatedItems = existingItems.prefix(upTo: matchingGapItemIndex)
        
        var itemsSeen = Set<String>()
        
        for newItem in inserting {
            switch newItem {
            case .loadingIndicator, .missingPosts:
                assertionFailure("items to insert should only be .post items")
                break
            case .post(let post):
                itemsSeen.insert(post.id)
                updatedItems.append(newItem)
            }
        }
        
        var potentialStartOfNewGap = updatedItems.last
        
        for olderExistingItem in existingItems.suffix(from: matchingGapItemIndex + 1) {
            switch olderExistingItem {
            case .loadingIndicator, .missingPosts:
                updatedItems.append(olderExistingItem)
            case .post(let post):
                if let newGapStart = potentialStartOfNewGap {
                    if post.id == potentialStartOfNewGap?.id {
                        // Found overlap, so there is no gap. Proceed.
                    } else {
                        if let newGap = TimelineItem.gapBetween(olderExistingItem, newerItem: newGapStart) {
                            updatedItems.append(newGap)
                        } else {
                            assertionFailure("why no new gap item?")
                        }
                    }
                    potentialStartOfNewGap = nil
                }
                
                if !itemsSeen.contains(post.id) {
                    itemsSeen.insert(post.id)
                    updatedItems.append(olderExistingItem)
                }
            }
        }
        
        items = Array(updatedItems)
    }
    
    init(inserting: [TimelineItem], into existingItems: [TimelineItem], asNewerThan: String) {
        // Assume that there should have been a gap item at the requested insertion point.
        let matchingGapItemIndex = existingItems.firstIndex { item in
            switch item {
            case .loadingIndicator, .post:
                return false
            case .missingPosts(let newerThan, _, _):
                return newerThan == asNewerThan
            }
        }
        guard let matchingGapItemIndex, let firstInsertingItem = inserting.first else { assertionFailure(); items = existingItems; return }
        
        let firstOverlapIndex = existingItems.firstIndex { item in
            item.id == firstInsertingItem.id
        }
        
        var updatedItems: [TimelineItem]
        if let firstOverlapIndex {
            // gap is now erased
            updatedItems = Array(existingItems.prefix(upTo: firstOverlapIndex))
        } else {
            // there is a new gap
            updatedItems = Array(existingItems.prefix(upTo: matchingGapItemIndex))
            if let lastItemBeforeGap = updatedItems.last, let newGap = TimelineItem.gapBetween(firstInsertingItem, newerItem: lastItemBeforeGap) {
                updatedItems.append(newGap)
            } else {
                assertionFailure("why no new gap item?")
            }
        }
        
        updatedItems = updatedItems + inserting
        
        updatedItems = updatedItems + existingItems.suffix(from: matchingGapItemIndex + 1)
        
        items = updatedItems
    }
    
    func byUpdating(post updated: GenericMastodonPost) -> CacheableTimeline {
        guard let actionableUpdatedId = updated.actionablePost?.id else { return self }
        let newItems = items.map { item in
            switch item {
            case .loadingIndicator, .missingPosts:
                return item
            case .post(let existing):
                if existing.id == actionableUpdatedId {
                    return .post(updated)
                } else if existing.actionablePost?.id == actionableUpdatedId {
                    do {
                        let updated = try existing.byReplacingActionablePost(with: updated)
                        return .post(updated)
                    } catch {
                        assertionFailure("Trying to update a boost post?  byReplacingActionablePost(with:) will need to handle that")
                        return item
                    }
                } else {
                    return item
                }
            }
        }
        
        return CacheableTimeline(older: [], newer: newItems)
    }
    
    func byDeleting(postId: Mastodon.Entity.Status.ID) -> CacheableTimeline {
        let newItems = items.filter { item in
            switch item {
            case .loadingIndicator, .missingPosts:
                return true
            case .post(let post):
                return post.actionablePost?.id != postId
            }
        }
        return CacheableTimeline(older: [], newer: newItems)
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
        case .asOlderThan(let id):
            mostRecentlyFetchedResults = CacheableTimeline(inserting: newlyFetched.items, into: currentResults()?.items ?? [], asOlderThan: id)
        case .asNewerThan(let id):
            mostRecentlyFetchedResults = CacheableTimeline(inserting: newlyFetched.items, into: currentResults()?.items ?? [], asNewerThan: id)
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

// MARK: Update Posts
extension TimelineFeedLoader {
    func updatePost(post: GenericMastodonPost) {
        updateCachedResults { cached in
            return cached.byUpdating(post: post)
        }
    }
    
    func didDeletePost(_ postID: Mastodon.Entity.Status.ID) {
        updateCachedResults { cached in
            return cached.byDeleting(postId: postID)
        }
    }
}

// MARK: Relationships
extension TimelineFeedLoader {
    func myRelationship(to accountID: Mastodon.Entity.Account.ID) -> MastodonAccount.Relationship {
        if accountID == authenticatedUserID {
            return .isMe
        } else {
            return cachedRelationships[accountID] ?? .isNotMe(nil)
        }
    }
    
    func refetchAllRelationships() async throws {
        cachedRelationships.removeAll()
        if let authenticatedUserID {
            cachedRelationships[authenticatedUserID] = .isMe
        }
        if let currentTimeline = cacheManager.currentResults() {
            try await fetchRelationships(currentTimeline)
        }
    }
    
    func updateMyRelationship(_ relationship: MastodonAccount.Relationship, to accountID: Mastodon.Entity.Account.ID) {
        cachedRelationships[accountID] = relationship
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

// MARK: Accounts Cache
extension TimelineFeedLoader {
    func account(_ id: Mastodon.Entity.Account.ID) -> MastodonAccount? {
        return accountsCache[id]
    }
    
    private func fetchReplyTos(_ timeline: CacheableTimeline) async throws {
        for item in timeline.items {
            switch item {
            case .loadingIndicator, .missingPosts:
                break
            case .post(let post):
                accountsCache[post.metaData.author.id] = post.metaData.author
                if let contentPost = post.actionablePost, contentPost.id != post.id {
                    accountsCache[post.metaData.author.id] = post.metaData.author
                }
            }
        }
        let needToFetch: [Mastodon.Entity.Account.ID] = timeline.filteredPosts.compactMap { item -> Mastodon.Entity.Account.ID? in
            switch item {
            case .loadingIndicator, .missingPosts:
                return nil
            case .post(let post):
                guard let basicPost = post as? MastodonBasicPost, let inReplyTo = basicPost.inReplyTo?.accountID else { return nil }
                if let alreadyCached = accountsCache[inReplyTo] {
                    return nil
                } else {
                    return inReplyTo
                }
            }
        }
        
        let accounts = try await APIService.shared.accountsInfo(userIDs: needToFetch, authenticationBox: authenticatedUser)
        for account in accounts {
            accountsCache[account.id] = MastodonAccount.fromEntity(account)
        }
        // TODO: handle servers < 4.3.0 by looking up each account individually?
    }
}

// MARK: Filters and Content Warnings
extension TimelineFeedLoader {
    private func createContentConcealViewModels(_ cache: CacheableTimeline) {
        for item in cache.items {
            switch item {
            case .loadingIndicator, .missingPosts:
                break
            case .post(let post):
                if let contentPost = post.actionablePost, contentConcealViewModels[contentPost.id] == nil {
                    contentConcealViewModels[contentPost.id] = ContentConcealViewModel(contentPost: contentPost, context: filterContext)
                }
            }
        }
    }
    
    public func contentConcealViewModel(forContentPost contentPost: MastodonContentPost?) -> ContentConcealViewModel? {
        guard let contentPost else { return nil }
        return contentConcealViewModels[contentPost.id]
    }
}
