// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import Boutique
import MastodonSDK

@MainActor
protocol NotificationsCacheManager<T> {
    associatedtype T: NotificationsResultType
    
    var currentResults: T? { get }
    var currentMarker: Mastodon.Entity.Marker? { get }
    var mostRecentlyFetchedResults: T? { get }
    func updateByInserting(newlyFetched: NotificationsResultType, at insertionPoint: GroupedNotificationFeedLoader.FeedLoadRequest.InsertLocation)
    func updateToNewerMarker(_ newMarker: Mastodon.Entity.Marker)
    func commitToCache(forUserAcct userAcct: String) async
}

protocol NotificationsResultType {}
extension Mastodon.Entity.GroupedNotificationsResults: NotificationsResultType {}
extension Array<Mastodon.Entity.Notification>: NotificationsResultType {}

@MainActor
class UngroupedNotificationCacheManager: NotificationsCacheManager {
    typealias T = [Mastodon.Entity.Notification]
    private let cachedNotifications: Store<Mastodon.Entity.Notification>
    
    private var staleResults: T?
    private var staleMarker: Mastodon.Entity.Marker?
    
    internal var mostRecentlyFetchedResults: T?
    private var mostRecentlyFetchedMarker: Mastodon.Entity.Marker?
    
    init(feedKind: MastodonFeedKind, userAcct: String) {
        self.cachedNotifications = Store.ungroupedNotificationStore(forKind: feedKind, forUserAcct: userAcct)
        self.staleResults = cachedNotifications.items
        switch feedKind {
        case .notificationsAll, .notificationsMentionsOnly:
            self.staleMarker = LastReadMarkerCache().getCachedMarker(forUserAcct: userAcct)
        case .notificationsWithAccount:
            self.staleMarker = nil
        }
        self.mostRecentlyFetchedResults = nil
        self.mostRecentlyFetchedMarker = nil
    }
    
    var currentResults: T? {
        return mostRecentlyFetchedResults ?? staleResults
    }
    
    var currentMarker: Mastodon.Entity.Marker? {
        return mostRecentlyFetchedMarker ?? staleMarker ?? nil
    }
    
    func updateByInserting(newlyFetched: NotificationsResultType, at insertionPoint: GroupedNotificationFeedLoader.FeedLoadRequest.InsertLocation) {

        guard let newlyFetched = newlyFetched as? [Mastodon.Entity.Notification] else {
            assertionFailure("unexpected type cannot be processed")
            return
        }
        
        var updatedMostRecentChunk: [Mastodon.Entity.Notification]

        if let previouslyFetched = mostRecentlyFetchedResults {
            switch insertionPoint {
            case .start:
                updatedMostRecentChunk = (newlyFetched + previouslyFetched)
            case .end:
                updatedMostRecentChunk = (previouslyFetched + newlyFetched).removingDuplicates()
            case .replace:
                updatedMostRecentChunk = newlyFetched.removingDuplicates()
            }
        } else {
            updatedMostRecentChunk = newlyFetched
        }
        if let staleResults, let combined = combineListsIfOverlapping(olderFeed: staleResults, newerFeed: updatedMostRecentChunk) {
            mostRecentlyFetchedResults = Array(combined)
            self.staleResults = nil
        } else {
            mostRecentlyFetchedResults = updatedMostRecentChunk
        }
    }
 
    
    func updateToNewerMarker(_ newMarker: Mastodon.Entity.Marker) {
        mostRecentlyFetchedMarker = newMarker
    }
    
    func commitToCache(forUserAcct userAcct: String) async {
        if let mostRecentlyFetchedMarker {
            LastReadMarkerCache().setCachedMarker(mostRecentlyFetchedMarker, forUserAcct: userAcct)
        }
        if let mostRecentlyFetchedResults {
            try? await cachedNotifications
                .removeAll()
                .insert(mostRecentlyFetchedResults)
                .run()
        } else {
            try? await cachedNotifications.removeAll()
        }
    }
}

@MainActor
class GroupedNotificationCacheManager: NotificationsCacheManager {
    typealias T = Mastodon.Entity.GroupedNotificationsResults
    
    private var staleResults: T?
    private var staleMarker: Mastodon.Entity.Marker?
    
    internal var mostRecentlyFetchedResults: T?
    private var mostRecentlyFetchedMarker: Mastodon.Entity.Marker?
    
    private let notificationGroupStore: Store<Mastodon.Entity.NotificationGroup>
    private let fullAccountStore: Store<Mastodon.Entity.Account>
    private let partialAccountStore: Store<Mastodon.Entity.PartialAccountWithAvatar>
    private let statusStore: Store<Mastodon.Entity.Status>
    
    init(feedKind: MastodonFeedKind, userAcct: String) {
        notificationGroupStore = Store.notificationGroupStore(forKind: feedKind, forUserAcct: userAcct)
        fullAccountStore = Store.notificationRelevantFullAccountStore(forKind: feedKind, forUserAcct: userAcct)
        partialAccountStore = Store.notificationRelevantPartialAccountStore(forKind: feedKind, forUserAcct: userAcct)
        statusStore = Store.notificationRelevantStatusStore(forKind: feedKind, forUserAcct: userAcct)
        
        staleResults = Mastodon.Entity.GroupedNotificationsResults(notificationGroups: notificationGroupStore.items, fullAccounts: fullAccountStore.items, partialAccounts: partialAccountStore.items, statuses: statusStore.items)
       
        switch feedKind {
        case .notificationsAll, .notificationsMentionsOnly:
            staleMarker = LastReadMarkerCache().getCachedMarker(forUserAcct: userAcct)
        case .notificationsWithAccount:
            staleMarker = nil
        }
    }
    
    func updateByInserting(newlyFetched: NotificationsResultType, at insertionPoint: GroupedNotificationFeedLoader.FeedLoadRequest.InsertLocation) {
        
        guard let newlyFetched = newlyFetched as? Mastodon.Entity.GroupedNotificationsResults else {
            assertionFailure("unexpected type cannot be processed")
            return
        }
        
        let updatedNewerChunk: [Mastodon.Entity.NotificationGroup]
        let includePreviouslyFetched: Bool
        if let previouslyFetched = mostRecentlyFetchedResults {
            switch insertionPoint {
            case .start:
                includePreviouslyFetched = true
                updatedNewerChunk = newlyFetched.notificationGroups + previouslyFetched.notificationGroups
            case .end:
                includePreviouslyFetched = true
                updatedNewerChunk = previouslyFetched.notificationGroups + newlyFetched.notificationGroups
            case .replace:
                includePreviouslyFetched = false
                updatedNewerChunk = newlyFetched.notificationGroups
            }
        } else {
            includePreviouslyFetched = false
            updatedNewerChunk = newlyFetched.notificationGroups
        }
        let dedupedNewChunk = updatedNewerChunk.removingDuplicates()
        
        let updatedNewerAccounts: [Mastodon.Entity.Account]
        let updatedNewerPartialAccounts: [Mastodon.Entity.PartialAccountWithAvatar]?
        let updatedNewerStatuses: [Mastodon.Entity.Status]
        if includePreviouslyFetched, let previouslyFetched = mostRecentlyFetchedResults {
            updatedNewerAccounts = (newlyFetched.accounts + previouslyFetched.accounts).removingDuplicates()
            updatedNewerPartialAccounts = ((newlyFetched.partialAccounts ?? []) + (previouslyFetched.partialAccounts ?? [])).removingDuplicates()
            updatedNewerStatuses = (newlyFetched.statuses + previouslyFetched.statuses).removingDuplicates()
        } else {
            updatedNewerAccounts = newlyFetched.accounts
            updatedNewerPartialAccounts = newlyFetched.partialAccounts
            updatedNewerStatuses = newlyFetched.statuses
        }
       
        if let staleResults, let combinedGroups = combineListsIfOverlapping(olderFeed: staleResults.notificationGroups, newerFeed: dedupedNewChunk) {
            let accountsMap = (staleResults.accounts + updatedNewerAccounts).reduce(into: [ String : Mastodon.Entity.Account ]()) { partialResult, account in
                partialResult[account.id] = account
            }
            let partialAccountsMap = ((staleResults.partialAccounts ?? []) + (updatedNewerPartialAccounts ?? [])).reduce(into: [ String : Mastodon.Entity.PartialAccountWithAvatar ]()) { partialResult, account in
                partialResult[account.id] = account
            }
            let statusesMap = (staleResults.statuses + updatedNewerStatuses).reduce(into: [ String : Mastodon.Entity.Status ]()) { partialResult, status in
                partialResult[status.id] = status
            }
            
            var allRelevantAccountIds = Set<String>()
            for group in combinedGroups {
                for accountID in group.sampleAccountIDs {
                    allRelevantAccountIds.insert(accountID)
                }
            }
            let accounts = allRelevantAccountIds.compactMap { accountsMap[$0] }
            let partialAccounts = allRelevantAccountIds.compactMap { partialAccountsMap[$0] }
            let statuses = combinedGroups.compactMap { group -> Mastodon.Entity.Status? in
                guard let statusID = group.statusID else { return nil }
                return statusesMap[statusID]
            }
            
            mostRecentlyFetchedResults = Mastodon.Entity.GroupedNotificationsResults(notificationGroups: Array(combinedGroups), fullAccounts: accounts, partialAccounts: partialAccounts, statuses: statuses)
            self.staleResults = nil
        } else {
            mostRecentlyFetchedResults = Mastodon.Entity.GroupedNotificationsResults(notificationGroups: dedupedNewChunk, fullAccounts: updatedNewerAccounts.removingDuplicates(), partialAccounts: updatedNewerPartialAccounts?.removingDuplicates(), statuses: updatedNewerStatuses.removingDuplicates())
        }
    }
    
    func updateToNewerMarker(_ newMarker: MastodonSDK.Mastodon.Entity.Marker) {
        mostRecentlyFetchedMarker = newMarker
    }
    
    var currentResults: T? {
        return mostRecentlyFetchedResults ?? staleResults
    }
    
    var currentMarker: Mastodon.Entity.Marker? {
        return mostRecentlyFetchedMarker ?? staleMarker
    }
    
    func commitToCache(forUserAcct userAcct: String) async {
        if let mostRecentlyFetchedResults {
            try? await notificationGroupStore
                .removeAll()
                .insert(mostRecentlyFetchedResults.notificationGroups)
                .run()
            try? await fullAccountStore
                .removeAll()
                .insert(mostRecentlyFetchedResults.accounts)
                .run()
            try? await partialAccountStore
                .removeAll()
                .insert(mostRecentlyFetchedResults.partialAccounts ?? [])
                .run()
            try? await statusStore
                .removeAll()
                .insert(mostRecentlyFetchedResults.statuses)
                .run()
        }
    }
}

fileprivate func combineListsIfOverlapping<T: Overlappable>(olderFeed: [T], newerFeed: [T]) -> [T]? {
    // if the last item in the new feed overlaps with something in the older feed, they can be combined
    guard let oldestNewItem = newerFeed.last else { return olderFeed }
    let overlapIndex = olderFeed.firstIndex { item in
        oldestNewItem.overlaps(withOlder: item)
    }
    guard let overlapIndex else { return nil }
    let suffixStart = overlapIndex + 1
    let olderChunk = (olderFeed.count > suffixStart) ? olderFeed.suffix(from: suffixStart) : []
    return newerFeed + olderChunk
}

protocol Overlappable {
    func overlaps(withOlder olderItem: Self) -> Bool
}

extension Mastodon.Entity.Notification: Overlappable {
    func overlaps(withOlder olderItem: Mastodon.Entity.Notification) -> Bool {
        return self.id == olderItem.id
    }
}

extension Mastodon.Entity.NotificationGroup: Overlappable {
    func overlaps(withOlder olderItem: Mastodon.Entity.NotificationGroup) -> Bool {
        return self.id == olderItem.id
    }
}

