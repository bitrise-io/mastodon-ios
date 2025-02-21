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

    struct FeedLoadRequest: Equatable {
        let olderThan: String?
        let newerThan: String?

        var resultsInsertionPoint: InsertLocation {
            if olderThan != nil {
                return .end
            } else if newerThan != nil {
                return .start
            } else {
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

    @Published private(set) var records: FeedLoadResult = FeedLoadResult(
        allRecords: [], canLoadOlder: true)

    private let useGroupedNotificationsApi: Bool
    private let cacheManager: any NotificationsCacheManager
    private let kind: MastodonFeedKind
    private let navigateToScene:
        ((SceneCoordinator.Scene, SceneCoordinator.Transition) -> Void)?
    private let presentError: ((Error) -> Void)?

    private var activeFilterBoxSubscription: AnyCancellable?

    init(
        kind: MastodonFeedKind,
        navigateToScene: (
            (SceneCoordinator.Scene, SceneCoordinator.Transition) -> Void
        )?, presentError: ((Error) -> Void)?
    ) {
        self.kind = kind
        self.navigateToScene = navigateToScene
        self.presentError = presentError
        
        let useGrouped: Bool
        let currentUser = AuthenticationServiceProvider.shared.currentActiveUser.value?.uniqueUserDomainIdentifier ?? "ERROR_no_user_found"
        switch kind {
        case .notificationsAll, .notificationsMentionsOnly:
            if let currentInstance = AuthenticationServiceProvider.shared.currentActiveUser.value?.authentication.instanceConfiguration {
                useGrouped = currentInstance.canGroupNotifications
            } else { assertionFailure("no instance configuration")
                useGrouped = false
            }
        case .notificationsWithAccount:
            useGrouped = false
        }
        self.useGroupedNotificationsApi = useGrouped
        if useGrouped {
            self.cacheManager = GroupedNotificationCacheManager(feedKind: kind, userAcct: currentUser)
        } else {
            self.cacheManager = UngroupedNotificationCacheManager(feedKind: kind, userAcct: currentUser)
        }
        
        activeFilterBoxSubscription = StatusFilterService.shared
            .$activeFilterBox
            .sink { filterBox in
                if filterBox != nil {
                    Task { [weak self] in
                        guard let self else { return }
                        let curAllRecords = self.records.allRecords
                        let curCanLoadOlder = self.records.canLoadOlder
                        await self.replaceRecordsAfterFiltering(
                            curAllRecords, canLoadOlder: curCanLoadOlder)
                    }
                }
            }
    }
    
    public func doFirstLoad() {
        Task {
            do {
                try await loadCached()
                loadMore(olderThan: nil, newerThan: records.allRecords.first?.newestID)
            } catch {
                presentError?(error)
            }
        }
    }

    private func replaceRecordsAfterFiltering(_ unfiltered: [NotificationRowViewModel], canLoadOlder: Bool? = nil) async {
        let filtered: [NotificationRowViewModel]
        if let filterBox = StatusFilterService.shared.activeFilterBox {
            filtered = await filter(unfiltered, forFeed: kind, with: filterBox)
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
        for (i, model) in rowViewModels.enumerated() {
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
    
    public func loadMore(
        olderThan: String?,
        newerThan: String?
    ) {
        let request = FeedLoadRequest(
            olderThan: olderThan, newerThan: newerThan)
        Task {
            let newlyFetched = try await load(request)
            await updateAfterInserting(newlyFetchedResults: newlyFetched, at: request.resultsInsertionPoint)
        }
    }

    public func asyncLoadMore(
        olderThan: String?,
        newerThan: String?
    ) async {
        let request = FeedLoadRequest(
            olderThan: olderThan, newerThan: newerThan)
        do {
            let newlyFetched = try await load(request)
            await updateAfterInserting(newlyFetchedResults: newlyFetched, at: request.resultsInsertionPoint)
        } catch {
            presentError?(error)
        }
    }
    
    private func loadCached() async throws {
        try await replaceRecordsAfterFiltering(rowViewModels(from: cacheManager.currentResults), canLoadOlder: true)
    }

    private func load(_ request: FeedLoadRequest) async throws
    -> NotificationsResultType
    {
        switch kind {
        case .notificationsAll:
            return try await loadNotifications(
                withScope: .everything, olderThan: request.olderThan)
        case .notificationsMentionsOnly:
            return try await loadNotifications(
                withScope: .mentions, olderThan: request.olderThan)
        case .notificationsWithAccount(let accountID):
            return try await loadNotifications(
                withAccountID: accountID, olderThan: request.olderThan)
        }
    }
}

// MARK: - Filtering
extension GroupedNotificationFeedLoader {
    private func updateAfterInserting(newlyFetchedResults: NotificationsResultType,
                                      at insertionPoint: GroupedNotificationFeedLoader.FeedLoadRequest.InsertLocation) async {
        do {
            cacheManager.updateByInserting(newlyFetched: newlyFetchedResults, at: insertionPoint)
            let unfiltered = try rowViewModels(from: cacheManager.currentResults)
            
            let canLoadOlder: Bool? = {
                switch insertionPoint {
                case .start:
                    return records.canLoadOlder
                case .end:
                    return nil
                case .replace:
                    return nil
                }
            }()
    
            await replaceRecordsAfterFiltering(unfiltered, canLoadOlder: canLoadOlder)
        } catch {
            presentError?(error)
        }
    }

    private func filter(
        _ records: [NotificationRowViewModel],
        forFeed feedKind: MastodonFeedKind,
        with filterBox: Mastodon.Entity.FilterBox
    ) async -> [NotificationRowViewModel] {
        return records
    }
}

// MARK: - Notifications
extension GroupedNotificationFeedLoader {
    private func loadNotifications(
        withScope scope: APIService.MastodonNotificationScope,
        olderThan maxID: String? = nil
    ) async throws -> NotificationsResultType {
        if useGroupedNotificationsApi {
            return try await getGroupedNotifications(
                withScope: scope, olderThan: maxID)
        } else {
            return try await getUngroupedNotifications(withScope: scope, olderThan: maxID)
        }
    }

    private func loadNotifications(
        withAccountID accountID: String, olderThan maxID: String? = nil
    ) async throws -> [Mastodon.Entity.Notification] {
        return try await getUngroupedNotifications(
            accountID: accountID, olderThan: maxID)
    }

    private func getGroupedNotifications(
        withScope scope: APIService.MastodonNotificationScope, olderThan maxID: String? = nil
    ) async throws -> Mastodon.Entity.GroupedNotificationsResults {
        guard
            let authenticationBox = AuthenticationServiceProvider.shared
                .currentActiveUser.value
        else { throw APIService.APIError.implicit(.authenticationMissing) }

        let results = try await APIService.shared.groupedNotifications(
            olderThan: maxID, fromAccount: nil, scope: scope,
            authenticationBox: authenticationBox
        )

        return results
    }

    private func getUngroupedNotifications(
        withScope scope: APIService.MastodonNotificationScope? = nil,
        accountID: String? = nil, olderThan maxID: String? = nil
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
                ungrouped, myAccountID: authenticationBox.userID,
                myAccountDomain: authenticationBox.domain,
                navigateToScene: navigateToScene ?? { _, _ in },
                presentError: presentError ?? { _ in }
            )
        } else if let grouped = results as? Mastodon.Entity.GroupedNotificationsResults {
            return NotificationRowViewModel
                .viewModelsFromGroupedNotificationResults(
                    grouped,
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

extension NotificationRowViewModel: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}
