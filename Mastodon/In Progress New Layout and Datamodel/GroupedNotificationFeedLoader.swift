//
//  GroupedNotificationFeedLoader.swift
//  MastodonSDK
//
//  Created by Shannon Hughes on 1/31/25.
//

import Combine
import Foundation
import MastodonCore
import MastodonSDK
import UIKit
import os.log

public protocol CacheableFeed {
    var hasResults: Bool { get }
}

@MainActor
protocol MastodonFeedCacheManager<CachedType> {
    associatedtype CachedType

    func currentResults() -> CachedType?
    var currentLastReadMarker: LastReadMarkers.MarkerPosition? { get }
    var mostRecentlyFetchedResults: CachedType? { get }
    func updateByInserting(newlyFetched: CachedType, at insertionPoint: MastodonFeedLoaderRequest.InsertLocation)
    func didFetchMarkers(_ updatedMarkers: Mastodon.Entity.Marker)
    func updateToNewerMarker(_ newMarker: LastReadMarkers.MarkerPosition, enforceForwardProgress: Bool)
    func commitToCache() async
}

public struct MastodonFeedLoaderResult<ResultType> {
    let allRecords: [ResultType]
    let canLoadOlder: Bool
}

public enum MastodonFeedLoaderRequest {
    case older
    case newer
    case reload
    
    var resultsInsertionPoint: InsertLocation {
        switch self {
        case .older:
            return .end
        case .newer:
            return .start
        case .reload:
            return .replace
        }
    }
    enum InsertLocation {
        case start
        case end
        case replace
    }
}

@MainActor
public class MastodonFeedLoader<PublishedType: Identifiable, CachedType: CacheableFeed> {
    private var activeFilterBoxSubscription: AnyCancellable?
    private var loadRequestQueue = [MastodonFeedLoaderRequest]()
    private var cacheManager: (any MastodonFeedCacheManager<CachedType>)?
    
    @Published private(set) var records = MastodonFeedLoaderResult<PublishedType>(
        allRecords: [], canLoadOlder: true)
    @Published private(set) var currentError: Error? = nil
    
    init(_ cacheManager: (any MastodonFeedCacheManager<CachedType>)?) {
        self.cacheManager = cacheManager
        
        activeFilterBoxSubscription = StatusFilterService.shared // error because type of curAllRecords is wrong
            .$activeFilterBox
            .sink { _ in
                // TODO: reload completely
            }
    }
    
    private var isFetching: Bool = false {
        didSet {
            if !isFetching, let waitingRequest = nextRequestThatCanBeLoadedNow() {
                Task {
                    do {
                        try await load(waitingRequest)
                        currentError = nil
                    } catch {
                        currentError = error
                    }
                }
            }
        }
    }
    
    private func nextRequestThatCanBeLoadedNow() -> MastodonFeedLoaderRequest? {
        guard !isFetching else { return nil }
        guard !loadRequestQueue.isEmpty else { return nil }
        let nextRequest = loadRequestQueue.removeFirst()
        isFetching = true
        return nextRequest
    }
    
    // MARK: Subclasses Must Override
    // TODO: add @available marks
    func fetchResults(for request: MastodonFeedLoaderRequest) async throws -> CachedType {
        fatalError("Subclasses must override fetchResults(for:)")
    }
    func filteredResults(fromCachedType: CachedType) -> [PublishedType] {
        fatalError("Subclasses must override publishedType(fromCachedType:)")
    }
}

extension MastodonFeedLoader {
    public func doFirstLoad() {
        Task {
            do {
                try loadCached()
            } catch {
            }
            do {
                if let cacheManager, let authBox = AuthenticationServiceProvider.shared.currentActiveUser.value {
                    let markers = try await APIService.shared.lastReadMarkers(authenticationBox: authBox)
                    cacheManager.didFetchMarkers(markers)
                }
            } catch {
            }
            requestLoad(.newer)
        }
    }
    
    public func requestLoad(_ request: MastodonFeedLoaderRequest) {
        if !loadRequestQueue.contains(request) {
            loadRequestQueue.append(request)
        }
        if let nextDoableRequest = nextRequestThatCanBeLoadedNow() {
            Task {
                do {
                    try await load(nextDoableRequest)
                    currentError = nil
                } catch {
                    currentError = error
                }
            }
        }
    }
    
    public var permissionToLoadImmediately: Bool {
        // This is only intended for use with pull to refresh, in order to properly update the progress spinner.
        if isFetching {
            return false
        } else {
            isFetching = true
            return true
        }
    }
    public func loadImmediately(_ request: MastodonFeedLoaderRequest) async {
        // This is only intended for use with pull to refresh, in order to properly update the progress spinner.
        guard isFetching else { assertionFailure("request permissionToLoadImmediately before calling loadImmediately"); return }
        do {
            try await load(request)
            currentError = nil
        } catch {
            currentError = error
        }
    }
    
    
    func load(_ request: MastodonFeedLoaderRequest) async throws
    {
        defer { isFetching = false }
        let unfiltered = try await fetchResults(for: request)
        updateAfterInserting(newlyFetchedResults: unfiltered, at: request.resultsInsertionPoint)
    }
    
    func updateAfterInserting(newlyFetchedResults: CachedType, at insertionPoint: MastodonFeedLoaderRequest.InsertLocation) {
        updateCacheByInserting(newlyFetchedResults: newlyFetchedResults, at: insertionPoint)
        
        let currentResults = cacheManager?.currentResults() ?? newlyFetchedResults
        let filtered = filteredResults(fromCachedType: currentResults)
        
        let canLoadOlder: Bool? = {
            switch insertionPoint {
            case .start:
                return records.canLoadOlder
            case .end:
                return nil
            case .replace:
                return true
            }
        }()
        replaceRecords(filtered, canLoadOlder: canLoadOlder)
        currentError = nil
    }
    
    private func noMoreResultsToFetch() {
        if records.canLoadOlder {
            records = MastodonFeedLoaderResult(allRecords: records.allRecords, canLoadOlder: false)
        }
    }
    
    private func replaceRecords(_ filtered: [PublishedType], canLoadOlder: Bool? = nil) {
        let actuallyCanLoadOlder = {
            if let newLast = filtered.last?.id, let oldLast = records.allRecords.last?.id {
                return canLoadOlder ?? (newLast != oldLast)
            } else {
                return canLoadOlder ?? true
            }
        }()
        
        records = MastodonFeedLoaderResult(allRecords: checkForDuplicates(filtered), canLoadOlder: actuallyCanLoadOlder)
    }
    
    private func checkForDuplicates(_ items: [PublishedType]) -> [PublishedType] {
        var added = Set<PublishedType.ID>()
        var deduped = [PublishedType]()
        for item in items {
            let id = item.id
            if added.contains(id) {
                continue
            } else {
                deduped.append(item)
                added.insert(id)
            }
        }
        return deduped
    }
}

extension MastodonFeedLoader {
    public func commitToCache() async {
        await cacheManager?.commitToCache()
    }
    
    private func loadCached() throws {
        guard !isFetching, let cacheManager else { return }
        isFetching = true
        defer {
            isFetching = false
        }
        if let currentResults = cacheManager.currentResults() {
            replaceRecords(filteredResults(fromCachedType: currentResults), canLoadOlder: true)
        }
    }

    private func updateCacheByInserting(newlyFetchedResults: CachedType,
                                        at insertionPoint: MastodonFeedLoaderRequest.InsertLocation) {
        switch insertionPoint {
        case .start:
            guard newlyFetchedResults.hasResults else { return }
        case .replace:
            break
        case .end:
            guard newlyFetchedResults.hasResults else {
                noMoreResultsToFetch()
                return
            }
        }
        guard let cacheManager else { return }
        cacheManager.updateByInserting(newlyFetched: newlyFetchedResults, at: insertionPoint)
    }
}

extension MastodonFeedLoader {
    var lastReadMarker: LastReadMarkers.MarkerPosition? {
        return cacheManager?.currentLastReadMarker
    }
    
    public func markAsRead(_ identifier: String) {
        cacheManager?.updateToNewerMarker(.local(lastReadID: identifier), enforceForwardProgress: true)
    }
    
    public func isUnread(_ identifier: String) -> Bool {
        if let lastRead = cacheManager?.currentLastReadMarker?.lastReadID {
            return LastReadMarkers.id(lastRead, isOlderThan: identifier)
        } else {
            return false
        }
    }
    
    public func lastRead() -> String? {
        return cacheManager?.currentLastReadMarker?.lastReadID
    }
}

@MainActor
final class UngroupedNotificationsFeedLoader: MastodonFeedLoader<GroupedNotificationInfo, [Mastodon.Entity.Notification]> {
    private let user: MastodonUserIdentifier
    private let kind: MastodonFeedKind
    
    init(_ kind: MastodonFeedKind, forUser user: MastodonUserIdentifier) {
        self.kind = kind
        self.user = user
        
        switch kind {
        case .home:
            fatalError("nonsensical")
        case .notificationsAll, .notificationsMentionsOnly:
            super.init(UngroupedNotificationCacheManager(feedKind: kind, userIdentifier: user))
        case .notificationsWithAccount:
            super.init(nil)
        }
    }
    
    private func getUngroupedNotifications(
        withScope scope: APIService.MastodonNotificationScope? = nil,
        accountID: String? = nil, olderThan maxID: String? = nil, newerThan minID: String?
    ) async throws -> [Mastodon.Entity.Notification] {
        
        assert(scope != nil || accountID != nil, "need a scope or an accountID")
        
        guard
            let authenticationBox = AuthenticationServiceProvider.shared
                .currentActiveUser.value
        else { throw APIService.APIError.implicit(.authenticationMissing) }
        
        let ungrouped = try await APIService.shared.notifications(
            olderThan: maxID, fromAccount: accountID, scope: scope,
            authenticationBox: authenticationBox
        ).value
        
        return ungrouped
    }
    
    override func fetchResults(for request: MastodonFeedLoaderRequest) async throws -> [Mastodon.Entity.Notification] {
        let olderThan: String?
        let newerThan: String?
        switch request {
        case .newer:
            olderThan = nil
            newerThan = records.allRecords.first?.newestNotificationID
        case .older:
            olderThan = records.allRecords.last?.oldestNotificationID
            newerThan = nil
        case .reload:
            olderThan = nil
            newerThan = nil
        }
        
        switch kind {
        case .home:
            assertionFailure("NOT IMPLEMENTED")
            return try await getUngroupedNotifications(
                withScope: .everything, olderThan: olderThan, newerThan: newerThan)
        case .notificationsAll:
            return try await getUngroupedNotifications(
                withScope: .everything, olderThan: olderThan, newerThan: newerThan)
        case .notificationsMentionsOnly:
            return try await getUngroupedNotifications(
                withScope: .mentions, olderThan: olderThan, newerThan: newerThan)
        case .notificationsWithAccount(let accountID):
            return try await getUngroupedNotifications(accountID: accountID, olderThan: olderThan, newerThan: newerThan)
        }
    }
    
    override func filteredResults(fromCachedType unfiltered: [Mastodon.Entity.Notification]) -> [GroupedNotificationInfo] {
        return unfiltered
            .filter({ !shouldHide($0.status?.filtered ?? []) })
            .map({ notification in
                let sourceAccounts = NotificationSourceAccounts(myAccountID: user.domain, accounts: [notification.account], totalActorCount: 1)
                let notificationType = GroupedNotificationType(notification, myAccountDomain: user.domain, sourceAccounts: sourceAccounts, adminReportID: nil)
                let navigation = NotificationRowViewModel.defaultNavigation(notificationType, isGrouped: false, primaryAccount: notification.account)
                let info = GroupedNotificationInfo(id: notification.id, timestamp: notification.createdAt, oldestNotificationID: notification.id, newestNotificationID: notification.id, groupedNotificationType: notificationType, sourceAccounts: sourceAccounts, status: notification.status, primaryNavigation: navigation)
                return info
            })
    }
}

@MainActor
final class GroupedNotificationsFeedLoader: MastodonFeedLoader<GroupedNotificationInfo, Mastodon.Entity.GroupedNotificationsResults> {
    
    private let user: MastodonUserIdentifier
    private let kind: MastodonFeedKind

    init(_ kind: MastodonFeedKind, forUser user: MastodonUserIdentifier) {
        self.user = user
        self.kind = kind
        switch kind {
        case .home, .notificationsWithAccount:
            fatalError("nonsensical")
        case .notificationsAll, .notificationsMentionsOnly:
            super.init(GroupedNotificationCacheManager(feedKind: kind, userIdentifier: user))
        }
    }
    
    override func fetchResults(for request: MastodonFeedLoaderRequest) async throws -> Mastodon.Entity.GroupedNotificationsResults {
        let olderThan: String?
        let newerThan: String?
        switch request {
        case .newer:
            olderThan = nil
            newerThan = records.allRecords.first?.newestNotificationID
        case .older:
            olderThan = records.allRecords.last?.oldestNotificationID
            newerThan = nil
        case .reload:
            olderThan = nil
            newerThan = nil
        }
        
        switch kind {
        case .home, .notificationsWithAccount:
            assertionFailure("NOT IMPLEMENTED")
            return try await getGroupedNotifications(
                withScope: .everything, olderThan: olderThan, newerThan: newerThan)
        case .notificationsAll:
            return try await getGroupedNotifications(
                withScope: .everything, olderThan: olderThan, newerThan: newerThan)
        case .notificationsMentionsOnly:
            return try await getGroupedNotifications(
                withScope: .mentions, olderThan: olderThan, newerThan: newerThan)
        }
    }
    
    override func filteredResults(fromCachedType results: Mastodon.Entity.GroupedNotificationsResults) -> [GroupedNotificationInfo] {
      
        let fullAccounts = results.accounts.reduce(
            into: [String: Mastodon.Entity.Account]()
        ) { partialResult, account in
            partialResult[account.id] = account
        }
        let partialAccounts = results.partialAccounts?.reduce(
            into: [String: Mastodon.Entity.PartialAccountWithAvatar]()
        ) { partialResult, account in
            partialResult[account.id] = account
        }
        
        let statuses = results.statuses.reduce(
            into: [String: Mastodon.Entity.Status](),
            { partialResult, status in
                partialResult[status.id] = status
            })
        
        return results.notificationGroups.map { group in
            let accounts: [AccountInfo] = group.sampleAccountIDs.compactMap { accountID in
                return fullAccounts[accountID] ?? partialAccounts?[accountID]
            }
            
            let sourceAccounts = NotificationSourceAccounts(
                myAccountID: user.userID, accounts: accounts,
                totalActorCount: group.notificationsCount)
            
            let status = group.statusID == nil ? nil : statuses[group.statusID!]
            
            let type = GroupedNotificationType(
                group, myAccountDomain: user.domain, sourceAccounts: sourceAccounts, status: status, adminReportID: group.adminReport?.id)
            
            return GroupedNotificationInfo(
                id: group.id,
                timestamp: group.latestPageNotificationAt,
                oldestNotificationID: group.pageNewestID ?? "",
                newestNotificationID: group.pageOldestID ?? "",
                groupedNotificationType: type,
                sourceAccounts: sourceAccounts,
                status: status,
                primaryNavigation: NotificationRowViewModel.defaultNavigation(
                    type, isGrouped: group.notificationsCount > 1,
                    primaryAccount: sourceAccounts.primaryAuthorAccount)
            )
        }
    }
}

extension GroupedNotificationsFeedLoader {
    private func getGroupedNotifications(
        withScope scope: APIService.MastodonNotificationScope, olderThan maxID: String? = nil, newerThan minID: String?
    ) async throws -> Mastodon.Entity.GroupedNotificationsResults {
        guard
            let authenticationBox = AuthenticationServiceProvider.shared
                .currentActiveUser.value
        else { throw APIService.APIError.implicit(.authenticationMissing) }

        let adminFilterPreferences = await BodegaPersistence.Notifications.currentPreferences(for: authenticationBox)
        let results = try await APIService.shared.groupedNotifications(
            olderThan: maxID, newerThan: minID, fromAccount: nil, scope: scope, excludingAdminTypes: adminFilterPreferences?.excludedNotificationTypes,
            authenticationBox: authenticationBox
        )

        return results
    }
}

func shouldHide(_ filterResults: [Mastodon.Entity.ServerFilterResult]) -> Bool {
    for result in filterResults {
        guard let keywordMatches = result.keywordMatches, let statusMatches = result.statusMatches else { return false }
        if result.filter.filterAction == .hide && (!keywordMatches.isEmpty || !statusMatches.isEmpty) {
            return true
        }
    }
    return false
}

extension Array<Mastodon.Entity.Notification>: CacheableFeed {
    public var hasResults: Bool {
        return !isEmpty
    }
}

extension Mastodon.Entity.GroupedNotificationsResults: CacheableFeed {
    public var hasResults: Bool {
        hasContents
    }
}
