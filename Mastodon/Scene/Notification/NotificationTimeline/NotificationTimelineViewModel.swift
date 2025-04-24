//
//  NotificationTimelineViewModel.swift
//  Mastodon
//
//  Created by MainasuK on 2022-1-21.
//

import UIKit
import Combine
import CoreDataStack
import GameplayKit
import MastodonSDK
import MastodonCore
import MastodonLocalization

@MainActor
final class NotificationTimelineViewModel {
    
    var disposeBag = Set<AnyCancellable>()
    
    // input
    let authenticationBox: MastodonAuthenticationBox
    let scope: Scope
    var notificationPolicy: Mastodon.Entity.NotificationPolicy?
    let feedLoader: UngroupedNotificationsFeedLoader
    @Published var isLoadingLatest = false
    @Published var lastAutomaticFetchTimestamp: Date?
    
    // output
    var diffableDataSource: UITableViewDiffableDataSource<NotificationSection, NotificationListItem>?
    var didLoadLatest = PassthroughSubject<Void, Never>()

    // bottom loader
    private(set) lazy var loadOldestStateMachine: GKStateMachine = {
        // exclude timeline middle fetcher state
        let stateMachine = GKStateMachine(states: [
            LoadOldestState.Initial(viewModel: self),
            LoadOldestState.Loading(viewModel: self),
            LoadOldestState.Fail(viewModel: self),
            LoadOldestState.Idle(viewModel: self),
            LoadOldestState.NoMore(viewModel: self),
        ])
        stateMachine.enter(LoadOldestState.Initial.self)
        return stateMachine
    }()
    
    @MainActor
    init(
        authenticationBox: MastodonAuthenticationBox,
        scope: Scope,
        notificationPolicy: Mastodon.Entity.NotificationPolicy? = nil
    ) {
        self.authenticationBox = authenticationBox
        self.scope = scope
        self.feedLoader = UngroupedNotificationsFeedLoader(scope.feedKind, forUser: authenticationBox.authentication.userIdentifier())
        self.notificationPolicy = notificationPolicy

        NotificationCenter.default.addObserver(self, selector: #selector(Self.notificationFilteringChanged(_:)), name: .notificationFilteringChanged, object: nil)
    }

    //MARK: - Notifications

    @objc func notificationFilteringChanged(_ notification: Notification) {
        Task { [weak self] in
            guard let self else { return }

            let policy = try await APIService.shared.notificationPolicy(authenticationBox: self.authenticationBox)
            self.notificationPolicy = policy.value

            await self.loadLatest()
        }
    }
    
    func didActOnFollowRequest(_ notification: MastodonNotification, approved: Bool) {
        defer {
            Task {
                await loadLatest()
            }
        }
        guard var currentSnapshot = diffableDataSource?.snapshot() else { return }
        let identifier = NotificationListItem.notification(.notification(id: notification.id))
        if currentSnapshot.itemIdentifiers.contains(identifier) {
            if !approved {
                currentSnapshot.deleteItems([identifier])
            }
        }
    }
}

extension NotificationTimelineViewModel {
    enum Scope: Hashable {
        case everything
        case mentions
        case fromAccount(Mastodon.Entity.Account)

        var title: String {
            switch self {
            case .everything:
                return L10n.Scene.Notification.Title.everything
            case .mentions:
                return L10n.Scene.Notification.Title.mentions
            case .fromAccount(let account):
                return "Notifications from \(account.displayName)"
            }
        }
        
        var feedKind: MastodonFeedKind {
            switch self {
            case .everything:
                return .notificationsAll
            case .mentions:
                return .notificationsMentionsOnly
            case .fromAccount(let account):
                return .notificationsWithAccount(account.id)
            }
        }
    }
}

extension NotificationTimelineViewModel {
    
    func reloadData() {
        guard let diffableDataSource else { return }
        diffableDataSource.applySnapshotUsingReloadData(diffableDataSource.snapshot())
    }
    
    // load lastest
    func loadLatest() async {
        isLoadingLatest = true
        defer { isLoadingLatest = false }
        let currentFirst = diffableDataSource?.snapshot().itemIdentifiers.first
        await loadMore(olderThan: nil, newerThan: currentFirst)
        didLoadLatest.send()
    }
    
    func loadMore(olderThan: NotificationListItem?, newerThan: NotificationListItem?) async {
        
        func fetchAnchor(for item: NotificationListItem?) -> MastodonFeedItemIdentifier? {
            switch item {
            case .notification:
                return item?.fetchAnchor
            case .bottomLoader:
                return diffableDataSource?.snapshot().itemIdentifiers.last(where: { $0.fetchAnchor != nil })?.fetchAnchor
            case .filteredNotificationsInfo:
                return  diffableDataSource?.snapshot().itemIdentifiers.first(where: { $0.fetchAnchor != nil })?.fetchAnchor
            case .groupedNotification(let viewModel):
                return viewModel.notification.identifier
            case .none:
                return nil
            }
        }
        
        do {
            if let olderThan {
                try await feedLoader.load(.older)
            } else if let newerThan {
                try await feedLoader.load(.newer)
            }
        } catch {
        }
    }
}
