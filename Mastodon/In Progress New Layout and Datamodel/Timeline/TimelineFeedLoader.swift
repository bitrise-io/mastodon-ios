// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import Combine
import Foundation
import MastodonCore
import MastodonSDK

public enum MastodonTimelineType: Equatable {
    case following
    case local
    case list(String)
    case hashtag(String)
}

extension GenericMastodonPost {
    struct InitialDisplayInfo: Codable {
        let id: Mastodon.Entity.Status.ID
        let actionablePostID: Mastodon.Entity.Status.ID
        let shouldFilterOut: Bool
        let actionableAuthorStaticAvatar: URL?
        let actionableAuthorHandle: String
        let actionableAuthorDisplayName: String
        let actionableVisibility: GenericMastodonPost.PrivacyLevel
        let actionableCreatedAt: Date
    }
}

enum TimelineItem: Identifiable {
    case post(MastodonPostViewModel)
    case missingPosts(newerThan: Mastodon.Entity.Status.ID, olderThan: Mastodon.Entity.Status.ID)
    case loadingIndicator
    
    var id: String {
        switch self {
        case .post(let postViewModel):
            return postViewModel.initialDisplayInfo.id
        case .missingPosts(let newerThan, let olderThan):
            return "\(newerThan)-\(olderThan)"
        case .loadingIndicator:
            return "loading..."
        }
    }
    
    static func gapBetween(_ olderItem: TimelineItem?, newerItem: TimelineItem?) -> TimelineItem? {
        switch (olderItem, newerItem) {
        case (.post(let olderViewModel), .post(let newerViewModel)):
            let olderID = olderViewModel.initialDisplayInfo.id
            let newerID = newerViewModel.initialDisplayInfo.id
            assert(olderID < newerID)
            return .missingPosts(newerThan: olderID, olderThan: newerID)
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

#if DEBUG
public var recentlyInsertedItemIds: Set<String>?
#endif

@MainActor
final class TimelineFeedLoader: MastodonFeedLoader<TimelineItem, CacheableTimeline> {
#if DEBUG
    private var _createArtificialGapForTesting = false
#endif
    
    private let filterContext = Mastodon.Entity.FilterContext.home
    
    private let authenticatedUser: MastodonAuthenticationBox
    private let authenticatedUserID: Mastodon.Entity.Account.ID?
    private var cachedRelationships = [Mastodon.Entity.Account.ID : MastodonAccount.Relationship]()
    private var accountsCache = [Mastodon.Entity.Account.ID : MastodonAccount]()
    private var contentConcealViewModels = [Mastodon.Entity.Status.ID : ContentConcealViewModel]()
    private var timestamper = TimestampUpdater(TimeInterval(30))
    
    let timeline: MastodonTimelineType
    
    init(currentUser: MastodonAuthenticationBox, timeline: MastodonTimelineType) {
        self.timeline = timeline
        authenticatedUser = currentUser
        authenticatedUserID = authenticatedUser.cachedAccount?.id
        if let authenticatedUserID {
            cachedRelationships[authenticatedUserID] = .isMe
        }
        super.init(TimelineCacheManager(currentUser: currentUser))
    }

    override func fetchResults(for request: MastodonFeedLoaderRequest) async throws -> CacheableTimeline {
        
        await AuthenticationServiceProvider.shared.fetchAccounts(onlyIfItHasBeenAwhile: true) // TODO: legacy comments indicated this may not be the best place for this call
        
        let itemsNoOlderThan: String?
        let itemsImmediatelyBefore: String?
        let itemsImmediatelyAfter: String?
        
        switch request {
        case .newer:
            let mostRecentID = {
                switch records.allRecords.count {
                case 0, 1:
                    return records.allRecords.first?.id
                default:
                    return records.allRecords[1].id  // we want to allow the possibility of an overlap in order to detect gaps
                }
            }()
            itemsNoOlderThan = mostRecentID
            itemsImmediatelyBefore = nil
            itemsImmediatelyAfter = nil
        case .older:
            let olderThan = {
                let count = records.allRecords.count
                switch count {
                case 0, 1:
                    return records.allRecords.last?.id
                default:
                    return records.allRecords[count - 2].id  // we want to allow the possibility of an overlap in order to detect gaps
                }
            }()
            itemsImmediatelyBefore = olderThan
            itemsNoOlderThan = nil
            itemsImmediatelyAfter = nil
        case .reload:
            itemsNoOlderThan = nil
            itemsImmediatelyBefore = nil
            itemsImmediatelyAfter = nil
        case .newerThan(let id):
            itemsImmediatelyAfter = id
            itemsImmediatelyBefore = nil
            itemsNoOlderThan = nil
        case .olderThan(let id):
            itemsImmediatelyBefore = id
            itemsImmediatelyAfter = nil
            itemsNoOlderThan = nil
        }

        let response: Mastodon.Response.Content<[Mastodon.Entity.Status]>
        switch timeline {
        case .following:
            response = try await APIService.shared.homeTimeline(itemsNoOlderThan: itemsNoOlderThan, itemsImmediatelyAfter: itemsImmediatelyAfter, itemsImmediatelyBefore: itemsImmediatelyBefore, authenticationBox: authenticatedUser)
        case .local:
            response = try await APIService.shared.publicTimeline(
                query: .init(local: true, maxID: itemsImmediatelyBefore, sinceID: itemsNoOlderThan, minID: itemsImmediatelyAfter),
                authenticationBox: authenticatedUser
            )
        case .list(let listId):
            response = try await APIService.shared.listTimeline(
                id: listId,
                query: .init(local: true, maxID: itemsImmediatelyBefore, sinceID: itemsNoOlderThan, minID: itemsImmediatelyAfter),
                authenticationBox: authenticatedUser
            )
        case .hashtag(let hashtag):
            response = try await APIService.shared.hashtagTimeline(
                sinceID: itemsNoOlderThan,
                maxID: itemsImmediatelyBefore,
                hashtag: hashtag,
                authenticationBox: authenticatedUser
            )
        }
        
        let newBatch = response.value.map { status in
            let post = GenericMastodonPost.fromStatus(status)
            let initialDisplayInfo = post.initialDisplayInfo
            return TimelineItem.post(MastodonPostViewModel(initialDisplayInfo, timestamper: timestamper))
        }
        
        let associatedPolls = polls(response.value)
        
        let newCache: CacheableTimeline
#if DEBUG && false
        if _createArtificialGapForTesting {
            _createArtificialGapForTesting = false
            let testingOldID = "" // insert useful postid for your purposes here
            let older = try await APIService.shared.homeTimeline(itemsImmediatelyBefore: testingOldID, authenticationBox: authenticatedUser)
            let oldBatch = older.value.map { status in
                let post = GenericMastodonPost.fromStatus(status)
                return TimelineItem.post(post)
            }
            let associatedPollsPlus = polls(older.value, addedTo: associatedPolls)
            newCache = CacheableTimeline(older: oldBatch, newer: newBatch, polls: associatedPollsPlus)
        } else {
            newCache = CacheableTimeline(older: [], newer: newBatch, polls: associatedPolls)
        }
#else
        newCache = CacheableTimeline(older: [], newer: newBatch, polls: associatedPolls)
#endif

        createContentConcealViewModels(newCache)
        try await fetchRelationships(newCache)
        try? await fetchReplyTos(newCache)
        
        return newCache
    }
    
    override func filteredResults(fromCachedType cached: CacheableTimeline) -> [TimelineItem] {
        cached.filteredPosts
    }
    
    func poll(_ id: Mastodon.Entity.Poll.ID) -> Mastodon.Entity.Poll? {
        return cacheManager.currentResults()?.polls[id]
    }
}

private func polls(_ statuses: [Mastodon.Entity.Status], addedTo existing: [Mastodon.Entity.Poll.ID : Mastodon.Entity.Poll]? = nil) -> [Mastodon.Entity.Poll.ID : Mastodon.Entity.Poll] {
    let starter = existing ?? [Mastodon.Entity.Poll.ID : Mastodon.Entity.Poll]()
    return statuses.reduce(into: starter, { partialResult, status in
        if let poll = status.poll ?? status.reblog?.poll {
            partialResult[poll.id] = poll
        }
    })
}

struct CacheableTimeline: CacheableFeed {
    
    let items: [TimelineItem]
    let polls: [Mastodon.Entity.Poll.ID : Mastodon.Entity.Poll]
    
    @MainActor
    var filteredPosts: [TimelineItem] {
        return items.filter { item in
            switch item {
            case .missingPosts, .loadingIndicator:
                return true
            case .post(let postViewModel):
                if let contentPost = postViewModel.fullPost as? MastodonContentPost {
                    return !contentPost.content.shouldBeRemovedFromFeed
                } else if let boost = postViewModel.fullPost as? MastodonBoostPost {
                    return !boost.boostedPost.content.shouldBeRemovedFromFeed
                } else {
                    return !postViewModel.initialDisplayInfo.shouldFilterOut
                }
            }
        }
    }
    
    var hasResults: Bool {
        return !items.isEmpty
    }
 
    init(older: [TimelineItem], newer: [TimelineItem], polls: [Mastodon.Entity.Poll.ID : Mastodon.Entity.Poll]) {
        
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
        self.polls = polls
    }
    
    init(inserting: [TimelineItem], into existingItems: [TimelineItem], asOlderThan: String, polls: [Mastodon.Entity.Poll.ID : Mastodon.Entity.Poll]) {
        // Assume that there should have been a gap item at the requested insertion point.
        let matchingGapItemIndex = existingItems.firstIndex { item in
            switch item {
            case .loadingIndicator, .post:
                return false
            case .missingPosts(_, let olderThan):
                return olderThan == asOlderThan
            }
        }
        
        self.polls = polls
        
        guard let matchingGapItemIndex else { assertionFailure(); items = existingItems; return }
        
        // start with the exiting items newer than the gap
        var updatedItems = Array(existingItems.prefix(upTo: matchingGapItemIndex))
 
        // add the items being inserted
        var alreadySeen = Set<String>()
        for insertingItem in inserting {
            alreadySeen.insert(insertingItem.id)
            updatedItems.append(insertingItem)
        }
        
#if DEBUG
        recentlyInsertedItemIds = alreadySeen
#endif
        
        // Now deal with any remaining gap or overlap
        
        let firstIndexAfterGap = matchingGapItemIndex + 1
        guard firstIndexAfterGap < existingItems.count else {
            assertionFailure("A gap ought to have items on both sides of it")
            items = Array(updatedItems)
            return
        }
        
        guard let lastNewItem = updatedItems.last else {
            assertionFailure("should have had some existing items before the gap, at least")
            items = existingItems
            return
        }
        
        if let firstDuplicateIndex = existingItems.suffix(from: firstIndexAfterGap).firstIndex(where: { alreadySeen.contains($0.id) }) {
            // There is an overlap, so no need to include a gap, but we also don't want to include duplicates
            if let firstNonDuplicateIndex = existingItems.suffix(from: firstIndexAfterGap).firstIndex(where: { !alreadySeen.contains($0.id) }) {
                
                for item in existingItems.suffix(from: firstNonDuplicateIndex) {
                    if !alreadySeen.contains(item.id) {
                        updatedItems.append(item)
                    }
                }
            }
        } else {
            // There is a gap
            if let newGap = TimelineItem.gapBetween(existingItems[firstIndexAfterGap], newerItem: lastNewItem) {
                updatedItems.append(newGap)
            } else {
                assertionFailure("why no new gap item?")
            }
            updatedItems.append(contentsOf: existingItems.suffix(from: firstIndexAfterGap))
        }
        
        items = Array(updatedItems)
    }
    
    init(inserting: [TimelineItem], into existingItems: [TimelineItem], asNewerThan: String, polls: [Mastodon.Entity.Poll.ID : Mastodon.Entity.Poll]) {
        // Assume that there should have been a gap item at the requested insertion point.
        let matchingGapItemIndex = existingItems.firstIndex { item in
            switch item {
            case .loadingIndicator, .post:
                return false
            case .missingPosts(let newerThan, _):
                return newerThan == asNewerThan
            }
        }
        self.polls = polls
        
        guard let matchingGapItemIndex, let firstInsertingItem = inserting.first else { assertionFailure(); items = existingItems; return }
        
        let insertingItemIDs: Set<String> = inserting.reduce(into: Set<String>()) { partialResult, item in
            partialResult.insert(item.id)
        }
#if DEBUG
        recentlyInsertedItemIds = insertingItemIDs
#endif
        
        var updatedItems: [TimelineItem]
        
        // start with the existing items newer than the gap (possibly truncated), and any remaining gap
        if let firstOverlapIndex = existingItems.prefix(upTo: matchingGapItemIndex).firstIndex(where: { insertingItemIDs.contains($0.id) }) {
            // The inserting items have overlap with the newer existing items, so no gap. But avoid duplicates, and prefer the inserting items (they are more freshly fetched).
            let firstNonDuplicateIndex = existingItems.suffix(from: firstOverlapIndex).firstIndex(where: { !insertingItemIDs.contains($0.id)})
            updatedItems = Array(existingItems.prefix(upTo: firstOverlapIndex))
        } else {
            // There is still a gap.
            updatedItems = Array(existingItems.prefix(upTo: matchingGapItemIndex))
            
            if let lastItemBeforeGap = updatedItems.last, let newGap = TimelineItem.gapBetween(firstInsertingItem, newerItem: lastItemBeforeGap) {
                updatedItems.append(newGap)
            } else {
                assertionFailure("why no new gap item?")
            }
        }
        
        // add the inserting items
        updatedItems.append(contentsOf: inserting)

        // add the existing items older than the gap
        let firstIndexAfterGap = matchingGapItemIndex + 1
        guard firstIndexAfterGap < existingItems.count else {
            assertionFailure("a gap should have items on both sides of it")
            items = updatedItems
            return
        }

        updatedItems.append(contentsOf: existingItems.suffix(from: firstIndexAfterGap))
        
        items = updatedItems
    }
    
    @MainActor
    func byUpdating(post updated: GenericMastodonPost) -> CacheableTimeline {
        guard let actionableUpdatedId = updated.actionablePost?.id else { return self }
        
        let newItems = items.map { item in
            switch item {
            case .loadingIndicator, .missingPosts:
                return item
            case .post(let existingViewModel):
                let newViewModel = existingViewModel.byReplacingActionablePost(with: updated)
                return .post(newViewModel)
            }
        }
        
        let updatedPolls = {
            if let poll = updated.actionablePost?._legacyEntity.poll {
                var existingPolls = polls
                existingPolls[poll.id] = poll
                return existingPolls
            } else {
                return polls
            }
        }()
        
        return CacheableTimeline(older: [], newer: newItems, polls: updatedPolls)
    }
    
    func byUpdating(poll updatedPoll: Mastodon.Entity.Poll) -> CacheableTimeline {
        var updatedPolls = polls
        updatedPolls[updatedPoll.id] = updatedPoll
        
        return CacheableTimeline(older: items, newer: [], polls: updatedPolls)
    }
    
    @MainActor
    func byDeleting(postId: Mastodon.Entity.Status.ID, pollID: Mastodon.Entity.Poll.ID?) -> CacheableTimeline {
        let newItems = items.filter { item in
            switch item {
            case .loadingIndicator, .missingPosts:
                return true
            case .post(let postViewModel):
                return postViewModel.fullPost?.actionablePost?.id != postId
            }
        }
        
        var updatedPolls = polls
        if let pollID {
            updatedPolls.removeValue(forKey: pollID)
        }
        
        return CacheableTimeline(older: [], newer: newItems, polls: updatedPolls)
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
        
        var updatedPolls = currentResults()?.polls ?? [:]
        for pollID in newlyFetched.polls.keys {
            updatedPolls[pollID] = newlyFetched.polls[pollID]
        }
        
        switch insertionPoint {
        case .start:
            mostRecentlyFetchedResults = CacheableTimeline(older: currentResults()?.items ?? [], newer: newlyFetched.items, polls: updatedPolls)
        case .end:
            mostRecentlyFetchedResults = CacheableTimeline(older: newlyFetched.items, newer: currentResults()?.items ?? [], polls: updatedPolls)
        case .replace:
            mostRecentlyFetchedResults = newlyFetched
        case .asOlderThan(let id):
            mostRecentlyFetchedResults = CacheableTimeline(inserting: newlyFetched.items, into: currentResults()?.items ?? [], asOlderThan: id, polls: updatedPolls)
        case .asNewerThan(let id):
            mostRecentlyFetchedResults = CacheableTimeline(inserting: newlyFetched.items, into: currentResults()?.items ?? [], asNewerThan: id, polls: updatedPolls)
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
    
    func didDeletePost(_ postID: Mastodon.Entity.Status.ID, pollID: Mastodon.Entity.Poll.ID?) {
        updateCachedResults { cached in
            return cached.byDeleting(postId: postID, pollID: pollID)
        }
    }
    
    func updatePoll(_ poll: Mastodon.Entity.Poll) {
        updateCachedResults { cached in
            return cached.byUpdating(poll: poll)
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
    }
}

// MARK: Accounts Cache
extension TimelineFeedLoader {
    func account(_ id: Mastodon.Entity.Account.ID) -> MastodonAccount? {
        return accountsCache[id]
    }
    
    private func fetchReplyTos(_ timeline: CacheableTimeline) async throws {
    }
}

// MARK: Filters and Content Warnings
extension TimelineFeedLoader {
    private func createContentConcealViewModels(_ cache: CacheableTimeline) {
        for item in cache.items {
            switch item {
            case .loadingIndicator, .missingPosts:
                break
            case .post(let postViewModel):
                if let contentPost = postViewModel.fullPost?.actionablePost, contentConcealViewModels[contentPost.id] == nil {
                    contentConcealViewModels[contentPost.id] = ContentConcealViewModel(contentPost: contentPost, context: filterContext)
                }
            }
        }
    }
    
    public func contentConcealViewModel(forContentPost contentPost: Mastodon.Entity.Status.ID?) -> ContentConcealViewModel? {
        guard let contentPost else { return nil }
        return contentConcealViewModels[contentPost]
    }
}

extension GenericMastodonPost {
    var initialDisplayInfo: GenericMastodonPost.InitialDisplayInfo {
        let author = actionablePost?.metaData.author ?? metaData.author
        return GenericMastodonPost.InitialDisplayInfo(id: id, actionablePostID: actionablePost?.id ?? id, shouldFilterOut: actionablePost?.content.shouldBeRemovedFromFeed ?? false, actionableAuthorStaticAvatar: author.displayInfo.avatarUrl, actionableAuthorHandle: author.handle, actionableAuthorDisplayName: author.displayName(whenViewedBy: nil)?.plainString ?? "", actionableVisibility: actionablePost?.metaData.privacyLevel ?? metaData.privacyLevel ?? .loudPublic, actionableCreatedAt: actionablePost?.metaData.createdAt ?? metaData.createdAt)
    }
}
