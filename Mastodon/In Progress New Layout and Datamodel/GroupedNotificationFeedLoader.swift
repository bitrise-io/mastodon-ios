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

@MainActor
final public class GroupedNotificationFeedLoader {

    struct FeedLoadResult {
        let allRecords: [NotificationRowViewModel]
        let canLoadOlder: Bool
    }

    public enum FeedLoadRequest {
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

    private let logger = Logger(
        subsystem: "GroupedNotificationFeedLoader", category: "Data")
    private static let entryNotFoundMessage =
        "Failed to find suitable record. Depending on the context this might result in errors (data not being updated) or can be discarded (e.g. when there are mixed data sources where an entry might or might not exist)."
    
    private var loadRequestQueue = [FeedLoadRequest]()

    @Published private(set) var records: FeedLoadResult = FeedLoadResult(
        allRecords: [], canLoadOlder: true)
    var lastReadMarker: LastReadMarkers.MarkerPosition? {
        return cacheManager?.currentLastReadMarker
    }
    
    private let timestampUpdater = TimestampUpdater(TimeInterval(30))
    
    private var isFetching: Bool = false {
        didSet {
            if !isFetching, let waitingRequest = nextRequestThatCanBeLoadedNow() {
                Task {
                    await load(waitingRequest)
                }
            }
        }
    }

    public let useGroupedNotificationsApi: Bool
    private let cacheManager: (any NotificationsCacheManager)?
    
    private let user: MastodonUserIdentifier?
    private let kind: MastodonFeedKind
    private let navigateToScene:
        ((SceneCoordinator.Scene, SceneCoordinator.Transition) -> Void)?
    private let presentError: ((Error) -> Void)?

    private var activeFilterBoxSubscription: AnyCancellable?

    init(kind: MastodonFeedKind,
        navigateToScene: (
            (SceneCoordinator.Scene, SceneCoordinator.Transition) -> Void
        )?, presentError: ((Error) -> Void)?
    ) {
        self.user = AuthenticationServiceProvider.shared.currentActiveUser.value?.authentication.userIdentifier()
        self.kind = kind
        self.navigateToScene = navigateToScene
        self.presentError = presentError
        
        let useGrouped: Bool
       
        switch kind {
        case .notificationsAll, .notificationsMentionsOnly:
            if let currentInstance = AuthenticationServiceProvider.shared.currentActiveUser.value?.authentication.instanceConfiguration {
                useGrouped = currentInstance.canGroupNotifications
            } else { assertionFailure("no instance configuration")
                useGrouped = true
            }
        case .notificationsWithAccount:
            useGrouped = false
        }
        self.useGroupedNotificationsApi = useGrouped
        if let authBox = AuthenticationServiceProvider.shared.currentActiveUser.value {
            let currentUserIdentifier = MastodonUserIdentifier(authenticationBox: authBox)
            if useGrouped {
                self.cacheManager = GroupedNotificationCacheManager(feedKind: kind, userIdentifier: currentUserIdentifier)
            } else {
                self.cacheManager = UngroupedNotificationCacheManager(feedKind: kind, userIdentifier: currentUserIdentifier)
            }
        } else {
            self.cacheManager = nil
        }
        
        activeFilterBoxSubscription = StatusFilterService.shared
            .$activeFilterBox
            .sink { filterBox in
                if filterBox != nil {
                    let curAllRecords = self.records.allRecords
                    let curCanLoadOlder = self.records.canLoadOlder
                    self.replaceRecordsAfterFiltering(
                        curAllRecords, canLoadOlder: curCanLoadOlder)
                }
            }
    }
    
    public func doFirstLoad() {
        Task {
            do {
                try loadCached()
            } catch {
            }
            do {
                if let authBox = AuthenticationServiceProvider.shared.currentActiveUser.value {
                    let markers = try await APIService.shared.lastReadMarkers(authenticationBox: authBox)
                    cacheManager?.didFetchMarkers(markers)
                }
            } catch {
            }
            requestLoad(.newer)
        }
    }
    
    public func commitToCache() async {
        await cacheManager?.commitToCache()
    }
    
    private func noMoreResultsToFetch() {
        if records.canLoadOlder {
            records = FeedLoadResult(allRecords: records.allRecords, canLoadOlder: false)
        }
    }

    private func replaceRecordsAfterFiltering(_ unfiltered: [NotificationRowViewModel], canLoadOlder: Bool? = nil) {
        let filtered: [NotificationRowViewModel]
        if let filterBox = StatusFilterService.shared.activeFilterBox {
            filtered = filter(unfiltered, forFeed: kind, with: filterBox)
        } else {
            filtered = unfiltered
        }
        
        let actuallyCanLoadOlder = {
            if let newLast = filtered.last?.identifier.id, let oldLast = records.allRecords.last?.identifier.id {
                return canLoadOlder ?? (newLast != oldLast)
            } else {
                return canLoadOlder ?? true
            }
        }()
       
        records = FeedLoadResult(allRecords: checkForDuplicates(filtered), canLoadOlder: actuallyCanLoadOlder)
    }
    
    private func checkForDuplicates(_ rowViewModels: [NotificationRowViewModel]) -> [NotificationRowViewModel] {
        var added = Set<String>()
        var deduped = [NotificationRowViewModel]()
        for model in rowViewModels {
            let id = model.identifier.id
            if added.contains(id) {
                continue
            } else {
                deduped.append(model)
                added.insert(id)
            }
        }
        return deduped
    }
    
    private func loadCached() throws {
        guard !isFetching, let cacheManager else { return }
        isFetching = true
        defer {
            isFetching = false
        }
        let currentResults = cacheManager.currentResults()
        try replaceRecordsAfterFiltering(rowViewModels(from: currentResults), canLoadOlder: true)
    }

    public func requestLoad(_ request: FeedLoadRequest) {
        if !loadRequestQueue.contains(request) {
            loadRequestQueue.append(request)
        }
        if let nextDoableRequest = nextRequestThatCanBeLoadedNow() {
            Task {
                await load(nextDoableRequest)
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
    public func loadImmediately(_ request: FeedLoadRequest) async {
        // This is only intended for use with pull to refresh, in order to properly update the progress spinner.
        guard isFetching else { assertionFailure("request permissionToLoadImmediately before calling loadImmediately"); return }
        await load(request)
    }
    
    private func nextRequestThatCanBeLoadedNow() -> FeedLoadRequest? {
        guard !isFetching else { return nil }
        guard !loadRequestQueue.isEmpty else { return nil }
        let nextRequest = loadRequestQueue.removeFirst()
        isFetching = true
        return nextRequest
    }
    
    private func load(_ request: FeedLoadRequest) async
    {
        defer { isFetching = false }
        do {
            let olderThan: String?
            let newerThan: String?
            switch request {
            case .newer:
                olderThan = nil
                newerThan = records.allRecords.first?.newestID
            case .older:
                olderThan = records.allRecords.last?.oldestID
                newerThan = nil
            case .reload:
                olderThan = nil
                newerThan = nil
            }
            let results: NotificationsResultType
            switch kind {
            case .notificationsAll:
                results = try await loadNotifications(
                    withScope: .everything, olderThan: olderThan, newerThan: newerThan)
            case .notificationsMentionsOnly:
                results = try await loadNotifications(
                    withScope: .mentions, olderThan: olderThan, newerThan: newerThan)
            case .notificationsWithAccount(let accountID):
                results = try await loadNotifications(
                    withAccountID: accountID, olderThan: olderThan, newerThan: newerThan)
            }
            updateAfterInserting(newlyFetchedResults: results, at: request.resultsInsertionPoint)
        } catch {
            presentError?(error)
        }
    }
}

// MARK: - Filtering
extension GroupedNotificationFeedLoader {
    private func updateAfterInserting(newlyFetchedResults: NotificationsResultType,
                                      at insertionPoint: GroupedNotificationFeedLoader.FeedLoadRequest.InsertLocation) {
        switch insertionPoint {
        case .start:
            guard newlyFetchedResults.hasContents else { return }
        case .replace:
            break
        case .end:
            guard newlyFetchedResults.hasContents else {
                noMoreResultsToFetch()
                return
            }
        }
        guard let cacheManager else { assertionFailure(); return }
        do {
            cacheManager.updateByInserting(newlyFetched: newlyFetchedResults, at: insertionPoint)
            let currentResults = cacheManager.currentResults()
            let unfiltered = try rowViewModels(from: currentResults)
            
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
    
            replaceRecordsAfterFiltering(unfiltered, canLoadOlder: canLoadOlder)
        } catch {
            presentError?(error)
        }
    }

    private func filter(
        _ records: [NotificationRowViewModel],
        forFeed feedKind: MastodonFeedKind,
        with filterBox: Mastodon.Entity.FilterBox
    ) -> [NotificationRowViewModel] {
        return records
    }
}

// MARK: - Notifications
extension GroupedNotificationFeedLoader {
    private func loadNotifications(
        withScope scope: APIService.MastodonNotificationScope,
        olderThan maxID: String? = nil,
        newerThan minID: String?
    ) async throws -> NotificationsResultType {
        if useGroupedNotificationsApi {
            do {
                return try await getGroupedNotifications(
                    withScope: scope, olderThan: maxID, newerThan: minID)
            } catch {
            }
        }
        return try await getUngroupedNotifications(withScope: scope, olderThan: maxID, newerThan: minID)
    }

    private func loadNotifications(
        withAccountID accountID: String, olderThan maxID: String? = nil, newerThan minID: String?
    ) async throws -> [Mastodon.Entity.Notification] {
        return try await getUngroupedNotifications(
            accountID: accountID, olderThan: maxID, newerThan: minID)
    }

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
    
    private func rowViewModels(from results: NotificationsResultType?) throws -> [NotificationRowViewModel] {
        guard let authenticationBox = AuthenticationServiceProvider.shared.currentActiveUser.value else { throw APIService.APIError.explicit(.authenticationMissing) }
        
        if let ungrouped = results as? [Mastodon.Entity.Notification] {
            return NotificationRowViewModel.viewModelsFromUngroupedNotifications(
                ungrouped, timestamper: timestampUpdater, myAccountID: authenticationBox.userID,
                myAccountDomain: authenticationBox.domain,
                navigateToScene: navigateToScene ?? { _, _ in },
                presentError: presentError ?? { _ in }
            )
        } else if let grouped = results as? Mastodon.Entity.GroupedNotificationsResults {
            return NotificationRowViewModel
                .viewModelsFromGroupedNotificationResults(
                    grouped,
                    timestamper: timestampUpdater,
                    myAccountID: authenticationBox.userID,
                    myAccountDomain: authenticationBox.domain,
                    navigateToScene: navigateToScene ?? { _, _ in },
                    presentError: presentError ?? { _ in }
                )
        } else {
            if results == nil {
                return []
            } else {
                assertionFailure("unexpected results type")
                return []
            }
        }
    }
}

extension GroupedNotificationFeedLoader {
    public func markAsRead(_ identifier: Mastodon.Entity.NotificationGroup.ID) {
        cacheManager?.updateToNewerMarker(.local(lastReadID: identifier))
    }
    
    public func isUnread(_ identifier: Mastodon.Entity.NotificationGroup.ID) -> Bool {
        if let lastRead = cacheManager?.currentLastReadMarker?.lastReadID {
            return identifier > lastRead
        } else {
            return true
        }
    }
}

extension NotificationRowViewModel: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}

class TimestampUpdater: ObservableObject {
    @Published var timestamp: Date = .now
    private var timer: Timer?
    
    init(_ interval: TimeInterval) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true, block: { [weak self] _ in
            Task { @MainActor in
                self?.timestamp = .now
            }
        })
    }
}
