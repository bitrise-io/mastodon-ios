// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import Boutique
import MastodonSDK
import MastodonCore

@MainActor
protocol NotificationsCacheManager<T> {
    associatedtype T: NotificationsResultType
    
    func currentResults() async -> T?
    var currentLastReadMarker: LastReadMarkers.MarkerPosition? { get }
    var mostRecentlyFetchedResults: T? { get }
    func updateByInserting(newlyFetched: NotificationsResultType, at insertionPoint: GroupedNotificationFeedLoader.FeedLoadRequest.InsertLocation)
    func didFetchMarkers(_ updatedMarkers: Mastodon.Entity.Marker)
    func updateToNewerMarker(_ newMarker: LastReadMarkers.MarkerPosition)
    func commitToCache() async
}

protocol NotificationsResultType {}
extension Mastodon.Entity.GroupedNotificationsResults: NotificationsResultType {}
extension Array<Mastodon.Entity.Notification>: NotificationsResultType {}

@MainActor
class UngroupedNotificationCacheManager: NotificationsCacheManager {
    typealias T = [Mastodon.Entity.Notification]
    private let userIdentifier: MastodonUserIdentifier
    private let feedKind: MastodonFeedKind
    private let lastReadMarkerStore: Store<LastReadMarkers>
    private let cachedNotifications: Store<Mastodon.Entity.Notification>
    
    private var staleResults: T?
    private var staleMarkers: LastReadMarkers?
    
    internal var mostRecentlyFetchedResults: T?
    private var mostRecentMarkers: LastReadMarkers?
    
    init(feedKind: MastodonFeedKind, userIdentifier: MastodonUserIdentifier) {
        self.feedKind = feedKind
        self.userIdentifier = userIdentifier
        lastReadMarkerStore = Store.lastReadMarkersStore()
        self.cachedNotifications = Store.ungroupedNotificationStore(forKind: feedKind, forUser: userIdentifier)
        staleResults = nil
        staleMarkers = nil
        self.mostRecentlyFetchedResults = nil
        self.mostRecentMarkers = nil
    }
    
    func currentResults() async -> T? {
        if let mostRecentlyFetchedResults {
            return mostRecentlyFetchedResults
        } else {
            do {
                switch feedKind {
                case .notificationsAll, .notificationsMentionsOnly:
                    try await lastReadMarkerStore.itemsHaveLoaded()
                    self.staleMarkers = lastReadMarkerStore.items.first(where: { $0.userGUID == userIdentifier.globallyUniqueUserIdentifier })
                case .notificationsWithAccount:
                    self.staleMarkers = nil
                }
                try await cachedNotifications.itemsHaveLoaded()
                staleResults = cachedNotifications.items
            } catch {
                assertionFailure("error reading notifications cache: \(error)")
            }
            return mostRecentlyFetchedResults ?? staleResults
        }
    }
    
    var currentLastReadMarker: LastReadMarkers.MarkerPosition? {
        guard let markers = mostRecentMarkers ?? staleMarkers else { return nil }
        return markers.lastRead(forKind: feedKind)
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
    
    func didFetchMarkers(_ updatedMarkers: Mastodon.Entity.Marker) {
        var updatable = mostRecentMarkers ?? staleMarkers ?? LastReadMarkers(userGUID: userIdentifier.globallyUniqueUserIdentifier, home: nil, notifications: nil, mentions: nil)
        if let notifications = updatedMarkers.notifications {
            updatable = updatable.bySettingLastRead(.fromServer(notifications), forKind: .notificationsAll)
        }
        mostRecentMarkers = updatable
    }
 
    func updateToNewerMarker(_ newMarker: LastReadMarkers.MarkerPosition) {
        let updatable = mostRecentMarkers ?? staleMarkers ?? LastReadMarkers(userGUID: userIdentifier.globallyUniqueUserIdentifier, home: nil, notifications: nil, mentions: nil)
        mostRecentMarkers = updatable.bySettingLastRead(newMarker, forKind: feedKind)
    }
    
    func commitToCache() async {
        if let mostRecentMarkers {
            try? await lastReadMarkerStore.insert(mostRecentMarkers)
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
    
    private let maxNotificationsListLength = 1000
    
    private let userIdentifier: MastodonUserIdentifier
    private let feedKind: MastodonFeedKind
    
    private var staleResults: T?
    private var staleMarkers: LastReadMarkers?
    
    internal var mostRecentlyFetchedResults: T?
    private var mostRecentMarkers: LastReadMarkers?
    
    private let lastReadMarkerStore: Store<LastReadMarkers>
    private let notificationGroupStore: Store<Mastodon.Entity.NotificationGroup>
    private let fullAccountStore: Store<Mastodon.Entity.Account>
    private let partialAccountStore: Store<Mastodon.Entity.PartialAccountWithAvatar>
    private let statusStore: Store<Mastodon.Entity.Status>
    
    init(feedKind: MastodonFeedKind, userIdentifier: MastodonUserIdentifier) {
        
        self.feedKind = feedKind
        self.userIdentifier = userIdentifier
        
        lastReadMarkerStore = Store.lastReadMarkersStore()
        notificationGroupStore = Store.notificationGroupStore(forKind: feedKind, forUser: userIdentifier)
        fullAccountStore = Store.notificationRelevantFullAccountStore(forKind: feedKind, forUser: userIdentifier)
        partialAccountStore = Store.notificationRelevantPartialAccountStore(forKind: feedKind, forUser: userIdentifier)
        statusStore = Store.notificationRelevantStatusStore(forKind: feedKind, forUser: userIdentifier)
        staleMarkers = nil
        staleResults = nil
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
        
        func truncate(notificationGroups: [Mastodon.Entity.NotificationGroup]) -> [Mastodon.Entity.NotificationGroup] {
            switch insertionPoint {
            case .start, .replace:
                return Array(notificationGroups.prefix(maxNotificationsListLength))
            case .end:
                return Array(notificationGroups.suffix(maxNotificationsListLength))
            }
        }
        
        let updatedNewerAccounts: [Mastodon.Entity.Account]
        let updatedNewerPartialAccounts: [Mastodon.Entity.PartialAccountWithAvatar]?
        let updatedNewerStatuses: [Mastodon.Entity.Status]
        if includePreviouslyFetched, let previouslyFetched = mostRecentlyFetchedResults {
            updatedNewerAccounts = (newlyFetched.accounts + previouslyFetched.accounts).removingDuplicates()
            updatedNewerPartialAccounts = ((newlyFetched.partialAccounts ?? []) + (previouslyFetched.partialAccounts ?? [])).removingDuplicates()
            updatedNewerStatuses = (newlyFetched.statuses + previouslyFetched.statuses).removingDuplicates()
        } else {
            updatedNewerAccounts = newlyFetched.accounts.removingDuplicates()
            updatedNewerPartialAccounts = newlyFetched.partialAccounts?.removingDuplicates()
            updatedNewerStatuses = newlyFetched.statuses.removingDuplicates()
        }
       
        let truncatedGroups: [Mastodon.Entity.NotificationGroup]
        let allAccounts: [Mastodon.Entity.Account]
        let allPartialAccounts: [Mastodon.Entity.PartialAccountWithAvatar]
        let allStatuses: [Mastodon.Entity.Status]
        
        if let staleResults, let combinedGroups = combineListsIfOverlapping(olderFeed: staleResults.notificationGroups, newerFeed: dedupedNewChunk) {
            truncatedGroups = truncate(notificationGroups: combinedGroups)
            allAccounts = staleResults.accounts + updatedNewerAccounts
            allPartialAccounts = (staleResults.partialAccounts ?? []) + (updatedNewerPartialAccounts ?? [])
            allStatuses = staleResults.statuses + updatedNewerStatuses
            self.staleResults = nil
        } else {
            truncatedGroups = truncate(notificationGroups: dedupedNewChunk)
            allAccounts = updatedNewerAccounts
            allPartialAccounts = updatedNewerPartialAccounts ?? []
            allStatuses = updatedNewerStatuses
        }
        
        let accountsMap = allAccounts.reduce(into: [ String : Mastodon.Entity.Account ]()) { partialResult, account in
            partialResult[account.id] = account
        }
        let partialAccountsMap = allPartialAccounts.reduce(into: [ String : Mastodon.Entity.PartialAccountWithAvatar ]()) { partialResult, account in
            partialResult[account.id] = account
        }
        let statusesMap = allStatuses.reduce(into: [ String : Mastodon.Entity.Status ]()) { partialResult, status in
            partialResult[status.id] = status
        }
        
        var allRelevantAccountIds = Set<String>()
        for group in truncatedGroups {
            for accountID in group.sampleAccountIDs {
                allRelevantAccountIds.insert(accountID)
            }
        }
        let accounts = allRelevantAccountIds.compactMap { accountsMap[$0] }
        let partialAccounts = allRelevantAccountIds.compactMap { partialAccountsMap[$0] }
        let statuses = truncatedGroups.compactMap { group -> Mastodon.Entity.Status? in
            guard let statusID = group.statusID else { return nil }
            return statusesMap[statusID]
        }
        
        mostRecentlyFetchedResults = Mastodon.Entity.GroupedNotificationsResults(notificationGroups: Array(truncatedGroups), fullAccounts: accounts, partialAccounts: partialAccounts, statuses: statuses)
    }
    
    func updateToNewerMarker(_ newMarker: LastReadMarkers.MarkerPosition) {
        let updatable = mostRecentMarkers ?? staleMarkers ?? LastReadMarkers(userGUID: userIdentifier.globallyUniqueUserIdentifier, home: nil, notifications: nil, mentions: nil)
        mostRecentMarkers = updatable.bySettingLastRead(newMarker, forKind: feedKind)
    }
    
    func didFetchMarkers(_ updatedMarkers: Mastodon.Entity.Marker) {
        var updatable = mostRecentMarkers ?? staleMarkers ?? LastReadMarkers(userGUID: userIdentifier.globallyUniqueUserIdentifier, home: nil, notifications: nil, mentions: nil)
        if let notifications = updatedMarkers.notifications {
            updatable = updatable.bySettingLastRead(.fromServer(notifications), forKind: .notificationsAll)
        }
        mostRecentMarkers = updatable
    }
    
    func currentResults() async -> T? {
        do {
            try await lastReadMarkerStore.itemsHaveLoaded()
            try await notificationGroupStore.itemsHaveLoaded()
            try await fullAccountStore.itemsHaveLoaded()
            try await partialAccountStore.itemsHaveLoaded()
            try await statusStore.itemsHaveLoaded()
            staleMarkers = lastReadMarkerStore.items.first(where: { $0.userGUID == userIdentifier.globallyUniqueUserIdentifier })
            staleResults = Mastodon.Entity.GroupedNotificationsResults(notificationGroups: notificationGroupStore.items, fullAccounts: fullAccountStore.items, partialAccounts: partialAccountStore.items, statuses: statusStore.items)
        } catch {
            assertionFailure("error loading notifications caches: \(error)")
        }
        return mostRecentlyFetchedResults ?? staleResults
    }
    
    var currentLastReadMarker: LastReadMarkers.MarkerPosition? {
        switch feedKind {
        case .notificationsAll, .notificationsMentionsOnly:
            return (mostRecentMarkers ?? staleMarkers)?.lastRead(forKind: feedKind)
        case .notificationsWithAccount:
            return nil
        }
    }
    
    func commitToCache() async {
        if let mostRecentMarkers {
            do {
                try await lastReadMarkerStore.insert(mostRecentMarkers)
            } catch {
            }
        }
        if let mostRecentlyFetchedResults {
            do {
                try await notificationGroupStore
                    .removeAll()
                    .insert(mostRecentlyFetchedResults.notificationGroups)
                    .run()
                try await fullAccountStore
                    .removeAll()
                    .insert(mostRecentlyFetchedResults.accounts)
                    .run()
                try await partialAccountStore
                    .removeAll()
                    .insert(mostRecentlyFetchedResults.partialAccounts ?? [])
                    .run()
                try await statusStore
                    .removeAll()
                    .insert(mostRecentlyFetchedResults.statuses)
                    .run()
            } catch {
                assertionFailure("error comitting to store \(error)")
            }
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

