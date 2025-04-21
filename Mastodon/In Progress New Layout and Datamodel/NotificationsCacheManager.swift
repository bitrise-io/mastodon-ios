// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import MastodonSDK
import MastodonCore

@MainActor
protocol NotificationsCacheManager<T> {
    associatedtype T: NotificationsResultType
    
    func currentResults() -> T?
    var currentLastReadMarker: LastReadMarkers.MarkerPosition? { get }
    var mostRecentlyFetchedResults: T? { get }
    func updateByInserting(newlyFetched: NotificationsResultType, at insertionPoint: GroupedNotificationFeedLoader.FeedLoadRequest.InsertLocation)
    func didFetchMarkers(_ updatedMarkers: Mastodon.Entity.Marker)
    func updateToNewerMarker(_ newMarker: LastReadMarkers.MarkerPosition, enforceForwardProgress: Bool)
    func commitToCache() async
}

protocol NotificationsResultType {
    var hasContents: Bool { get }
}
extension Mastodon.Entity.GroupedNotificationsResults: NotificationsResultType {
    var hasContents: Bool {
        return notificationGroups.isNotEmpty
    }
}
extension Array<Mastodon.Entity.Notification>: NotificationsResultType {
    var hasContents: Bool {
        return isNotEmpty
    }
}

@MainActor
class UngroupedNotificationCacheManager: NotificationsCacheManager {
    typealias T = [Mastodon.Entity.Notification]
    private let userIdentifier: MastodonUserIdentifier
    private let feedKind: MastodonFeedKind
    
    private var staleResults: T?
    private var staleMarkers: LastReadMarkers?
    
    internal var mostRecentlyFetchedResults: T?
    private var mostRecentMarkers: LastReadMarkers?
    
    init(feedKind: MastodonFeedKind, userIdentifier: MastodonUserIdentifier) {
        self.feedKind = feedKind
        self.userIdentifier = userIdentifier
        staleResults = nil
        staleMarkers = nil
        self.mostRecentlyFetchedResults = nil
        self.mostRecentMarkers = nil
    }
    
    func currentResults() -> T? {
        if let mostRecentlyFetchedResults {
            return mostRecentlyFetchedResults
        } else if let staleResults {
            return staleResults
        } else {
            do {
                switch feedKind {
                case .notificationsAll, .notificationsMentionsOnly:
                    Task { [weak self] in
                        guard let self, self.staleMarkers == nil else { return }
                        self.staleMarkers = await BodegaPersistence.LastRead.lastReadMarkers(for: userIdentifier)
                    }
                case .notificationsWithAccount:
                    self.staleMarkers = nil
                }
                switch feedKind {
                case .notificationsAll:
                    staleResults = try PersistenceManager.shared.cached(.notificationsAll(userIdentifier))
                case .notificationsMentionsOnly:
                    staleResults = try PersistenceManager.shared.cached(.notificationsMentions(userIdentifier))
                case .notificationsWithAccount:
                    staleResults = nil
                }
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
                updatedMostRecentChunk = (previouslyFetched + newlyFetched)
            case .replace:
                updatedMostRecentChunk = newlyFetched
            }
        } else {
            updatedMostRecentChunk = newlyFetched
        }
        if let staleResults {
            let (dedupedNewer, stale) = merge(newer: updatedMostRecentChunk, older: staleResults)
            mostRecentlyFetchedResults = Array(dedupedNewer)
            if stale == nil {
                self.staleResults = nil
            }
        } else {
            mostRecentlyFetchedResults = updatedMostRecentChunk.removingDuplicates()
        }
    }
    
    func didFetchMarkers(_ updatedMarkers: Mastodon.Entity.Marker) {
        var updatable = mostRecentMarkers ?? staleMarkers ?? LastReadMarkers(userGUID: userIdentifier.globallyUniqueUserIdentifier, home: nil, notifications: nil, mentions: nil)
        if let notifications = updatedMarkers.notifications {
            updatable = updatable.bySettingPosition(.fromServer(notifications), forKind: .notificationsAll, enforceForwardProgress: true)
        }
        mostRecentMarkers = updatable
    }
 
    func updateToNewerMarker(_ newMarker: LastReadMarkers.MarkerPosition, enforceForwardProgress: Bool) {
        let updatable = mostRecentMarkers ?? staleMarkers ?? LastReadMarkers(userGUID: userIdentifier.globallyUniqueUserIdentifier, home: nil, notifications: nil, mentions: nil)
        mostRecentMarkers = updatable.bySettingPosition(newMarker, forKind: feedKind, enforceForwardProgress: enforceForwardProgress)
    }
    
    func commitToCache() async {
        if let mostRecentMarkers {
            try? await BodegaPersistence.LastRead.saveLastReadMarkers(mostRecentMarkers, for: userIdentifier)
        }
        if let mostRecentlyFetchedResults {
            switch feedKind {
            case .notificationsAll:
                PersistenceManager.shared.cache(mostRecentlyFetchedResults, for: .notificationsAll(userIdentifier))
            case .notificationsMentionsOnly:
                PersistenceManager.shared.cache(mostRecentlyFetchedResults, for: .notificationsMentions(userIdentifier))
            case .notificationsWithAccount:
                break
            }
        }
    }
}

enum Fetchable<T> {
    case initial
    case fetching
    case known(T?)
    
    var value: T? {
        switch self {
        case .initial, .fetching:
            return nil
        case .known(let value):
            return value
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
    private var staleMarkers: Fetchable<LastReadMarkers> = .initial
    
    internal var mostRecentlyFetchedResults: T?
    private var mostRecentMarkers: Fetchable<LastReadMarkers> = .initial
    
    init(feedKind: MastodonFeedKind, userIdentifier: MastodonUserIdentifier) {
        
        self.feedKind = feedKind
        self.userIdentifier = userIdentifier
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
        
        if let staleResults {
            let (dedupedNewer, dedupedStale) = merge(newer: updatedNewerChunk, older: staleResults.notificationGroups)
            truncatedGroups = truncate(notificationGroups: dedupedNewer)
            if dedupedStale == nil {
                // the lists were combined, so we don't have to keep track of the stale one anymore
                allAccounts = staleResults.accounts + updatedNewerAccounts
                allPartialAccounts = (staleResults.partialAccounts ?? []) + (updatedNewerPartialAccounts ?? [])
                allStatuses = staleResults.statuses + updatedNewerStatuses
                self.staleResults = nil
            } else {
                allAccounts = updatedNewerAccounts
                allPartialAccounts = updatedNewerPartialAccounts ?? []
                allStatuses = updatedNewerStatuses
            }
        } else {
            truncatedGroups = truncate(notificationGroups: updatedNewerChunk.removingDuplicates())
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
    
    func updateToNewerMarker(_ newMarker: LastReadMarkers.MarkerPosition, enforceForwardProgress: Bool) {
        let updatable = mostRecentMarkers.value ?? staleMarkers.value ?? LastReadMarkers(userGUID: userIdentifier.globallyUniqueUserIdentifier, home: nil, notifications: nil, mentions: nil)
        mostRecentMarkers = .known(updatable.bySettingPosition(newMarker, forKind: feedKind, enforceForwardProgress: enforceForwardProgress))
    }
    
    func didFetchMarkers(_ updatedMarkers: Mastodon.Entity.Marker) {
        var updatable = mostRecentMarkers.value ?? staleMarkers.value ?? LastReadMarkers(userGUID: userIdentifier.globallyUniqueUserIdentifier, home: nil, notifications: nil, mentions: nil)
        if let notifications = updatedMarkers.notifications {
            updatable = updatable.bySettingPosition(.fromServer(notifications), forKind: .notificationsAll, enforceForwardProgress: true)
        }
        mostRecentMarkers = .known(updatable)
    }
    
    func currentResults() -> T? {
        if let mostRecentlyFetchedResults {
            return mostRecentlyFetchedResults
        } else if let staleResults {
            return staleResults
        } else {
            switch feedKind {
            case .notificationsAll, .notificationsMentionsOnly:
                loadCachedMarkers()
            case .notificationsWithAccount:
                staleMarkers = .known(nil)
            }
            
            let notificationGroups: [Mastodon.Entity.NotificationGroup]
            let accounts: [Mastodon.Entity.Account]
            let partialAccounts: [Mastodon.Entity.PartialAccountWithAvatar]
            let statuses: [Mastodon.Entity.Status]
            switch feedKind {
            case .notificationsAll:
                notificationGroups = (try? PersistenceManager.shared.cached(.groupedNotificationsAll(userIdentifier))) ?? []
                accounts = (try? PersistenceManager.shared.cached(.groupedNotificationsAllAccounts(userIdentifier))) ?? []
                partialAccounts = (try? PersistenceManager.shared.cached(.groupedNotificationsAllPartialAccounts(userIdentifier))) ?? []
                statuses = (try? PersistenceManager.shared.cached(.groupedNotificationsAllStatuses(userIdentifier))) ?? []
            case .notificationsMentionsOnly:
                notificationGroups = (try? PersistenceManager.shared.cached(.groupedNotificationsMentions(userIdentifier))) ?? []
                accounts = (try? PersistenceManager.shared.cached(.groupedNotificationsMentionsAccounts(userIdentifier))) ?? []
                partialAccounts = (try? PersistenceManager.shared.cached(.groupedNotificationsMentionsPartialAccounts(userIdentifier))) ?? []
                statuses = (try? PersistenceManager.shared.cached(.groupedNotificationsMentionsStatuses(userIdentifier))) ?? []
            case .notificationsWithAccount:
                return mostRecentlyFetchedResults
            }
            staleResults = Mastodon.Entity.GroupedNotificationsResults(notificationGroups: notificationGroups, fullAccounts: accounts, partialAccounts: partialAccounts, statuses: statuses)
            return mostRecentlyFetchedResults ?? staleResults
        }
    }
    
    var currentLastReadMarker: LastReadMarkers.MarkerPosition? {
        switch feedKind {
        case .notificationsAll, .notificationsMentionsOnly:
            return (mostRecentMarkers.value ?? staleMarkers.value)?.lastRead(forKind: feedKind)
        case .notificationsWithAccount:
            return nil
        }
    }
    
    func loadCachedMarkers() {
        switch staleMarkers {
        case .fetching, .known:
            return
        case .initial:
           break
        }
        staleMarkers = .fetching
        Task { [weak self] in
            guard let self else { return }
            let fromCache = await BodegaPersistence.LastRead.lastReadMarkers(for: self.userIdentifier)
            staleMarkers = .known(fromCache)
        }
    }
    
    func commitToCache() async {
        if let updatedMarkers = mostRecentMarkers.value {
            Task {
                try await BodegaPersistence.LastRead.saveLastReadMarkers(updatedMarkers, for: userIdentifier)
            }
        }
        if let mostRecentlyFetchedResults {
            switch feedKind {
            case .notificationsAll:
                PersistenceManager.shared.cache(mostRecentlyFetchedResults.notificationGroups, for: .groupedNotificationsAll(userIdentifier))
                PersistenceManager.shared.cache(mostRecentlyFetchedResults.accounts, for: .groupedNotificationsAllAccounts(userIdentifier))
                PersistenceManager.shared.cache(mostRecentlyFetchedResults.partialAccounts ?? [], for: .groupedNotificationsAllPartialAccounts(userIdentifier))
                PersistenceManager.shared.cache(mostRecentlyFetchedResults.statuses, for: .groupedNotificationsAllStatuses(userIdentifier))
            case .notificationsMentionsOnly:
                PersistenceManager.shared.cache(mostRecentlyFetchedResults.notificationGroups, for: .groupedNotificationsMentions(userIdentifier))
                PersistenceManager.shared.cache(mostRecentlyFetchedResults.accounts, for: .groupedNotificationsMentionsAccounts(userIdentifier))
                PersistenceManager.shared.cache(mostRecentlyFetchedResults.partialAccounts ?? [], for: .groupedNotificationsMentionsPartialAccounts(userIdentifier))
                PersistenceManager.shared.cache(mostRecentlyFetchedResults.statuses, for: .groupedNotificationsMentionsStatuses(userIdentifier))
            case .notificationsWithAccount:
                break
            }
        }
    }
}

fileprivate func merge<T: Overlappable>(newer: [T], older: [T], assumeOverlap: Bool = true) -> ([T], [T]?) {
    // There can be multiple matches between the older and newer feeds, with no guarantee of order. The newer version of a duplicate is always the one that should be used.
    // Note that the check here is not fully sufficient to test for a gap between freshly fetched notifications and cached notifications (this check could miss a gap that was skipped over by a group that got promoted far enough up the list), which is why for now we fetch with a minID to avoid gaps and always assume there is an overlap.
    
    var dedupedNewer = [T]()
    var dedupedOlder = [T]()
    var alreadyAdded = Set<T.ID>()
    var hasOverlap = false

    for element in newer {
        guard !alreadyAdded.contains(element.id) else { continue }
        dedupedNewer.append(element)
        alreadyAdded.insert(element.id)
    }

    for element in older {
        guard !alreadyAdded.contains(element.id) else { hasOverlap = true; continue }
        dedupedOlder.append(element)
        alreadyAdded.insert(element.id)
    }
    
    if hasOverlap || assumeOverlap {
        return (dedupedNewer + dedupedOlder, nil)
    } else {
        return (dedupedNewer, dedupedOlder)
    }
}

protocol Overlappable: Identifiable {
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

