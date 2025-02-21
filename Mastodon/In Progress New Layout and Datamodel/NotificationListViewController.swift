// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import Combine
import MastodonAsset
import MastodonCore
import MastodonLocalization
import MastodonSDK
import SwiftUI

class NotificationListViewController: UIHostingController<NotificationListView>
{
    fileprivate var viewModel: NotificationListViewModel

    init() {
        viewModel = NotificationListViewModel()
        let root = NotificationListView(viewModel: viewModel)
        super.init(rootView: root)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease.circle"), style: .plain, target: self, action: #selector(showNotificationPolicySettings))

        viewModel.presentError = { error in
            let alert = UIAlertController(
                title: "Error", message: error.localizedDescription,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.sceneCoordinator?.rootViewController?.topMost?.present(
                alert, animated: true)
        }

        viewModel.navigateToScene = { [weak self] scene, transition in
            guard let self else { return }
            Task { @MainActor in
                self.sceneCoordinator?.present(
                    scene: scene, from: self, transition: transition)
            }
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError(
            "init(coder:) not implemented for NotificationListViewController")
    }
    
    @objc private func showNotificationPolicySettings(_ sender: Any) {
        guard let policy = viewModel.filteredNotificationsViewModel.policy else { return }
        Task {
            let policyViewModel = await NotificationFilterViewModel(
                notFollowing: policy.filterNotFollowing,
                noFollower: policy.filterNotFollowers,
                newAccount: policy.filterNewAccounts,
                privateMentions: policy.filterPrivateMentions
            )
            
            guard let policyViewController = self.sceneCoordinator?.present(scene: .notificationPolicy(viewModel: policyViewModel), transition: .formSheet) as? NotificationPolicyViewController else { return }
            
            policyViewController.delegate = self
        }
    }
}

extension NotificationListViewController: NotificationPolicyViewControllerDelegate {
    func policyUpdated(_ viewController: NotificationPolicyViewController, newPolicy: MastodonSDK.Mastodon.Entity.NotificationPolicy) {
        viewModel.updateFilteredNotificationsPolicy(newPolicy)
    }
}

private enum ListType {
    case everything
    case mentions

    var pickerLabel: String {
        switch self {
        case .everything:
            L10n.Scene.Notification.Title.everything
        case .mentions:
            L10n.Scene.Notification.Title.mentions
        }
    }

    var feedKind: MastodonFeedKind {
        switch self {
        case .everything:
            return .notificationsAll
        case .mentions:
            return .notificationsMentionsOnly
        }
    }
}
extension ListType: Identifiable {
    var id: String {
        return pickerLabel
    }
}

struct NotificationListView: View {
    @ObservedObject private var viewModel: NotificationListViewModel

    fileprivate init(viewModel: NotificationListViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack {
            Spacer().frame(maxHeight: 8)

            HStack {
                Spacer()
                Picker(selection: $viewModel.displayedNotifications) {
                    ForEach(
                        [ListType.everything, .mentions]
                    ) {
                        Text($0.pickerLabel)
                            .tag($0)
                    }
                } label: {
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .fixedSize()
                Spacer()
            }

            List {
                ForEach(viewModel.notificationItems) { item in
                    rowView(item)
                        .onAppear {
                            switch item {
                            case .groupedNotification(let viewModel):
                                viewModel.prepareForDisplay()
                            case .bottomLoader:
                                loadMore()
                            default:
                                break
                            }
                        }
                        .onTapGesture {
                            didTap(item: item)
                        }
                }
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.refreshFeedFromTop()
            }
        }
        .onAppear() {
            NotificationService.shared.clearNotificationCountForActiveUser()
            Task {
                await viewModel.refreshFeedFromTop()
            }
        }
        .onDisappear() {
            NotificationService.shared.clearNotificationCountForActiveUser()
        }
    }

    @ViewBuilder func rowView(_ notificationListItem: NotificationListItem)
        -> some View
    {
        switch notificationListItem {
        case .bottomLoader:
            HStack {
                Spacer()
                ProgressView().progressViewStyle(.circular)
                Spacer()
            }
        case .filteredNotificationsInfo(_, let viewModel):
            if let viewModel {
                FilteredNotificationsRowView(viewModel)
            } else {
                Text("Some notifications have been filtered.")
            }
        case .notification:
            Text("obsolete item")
        case .groupedNotification(let viewModel):
            // TODO: implement unread using Mastodon.Entity.Marker
            NotificationRowView(viewModel: viewModel)
                .padding(.vertical, 4)
                .listRowBackground(
                    Rectangle()
                        .fill(viewModel.usePrivateBackground ?  Asset.Colors.accent.swiftUIColor : .clear)
                        .opacity(0.1)
                )
        }
    }

    func loadMore() {
        viewModel.loadOlder()
    }

    func didTap(item: NotificationListItem) {
        switch item {
        case .filteredNotificationsInfo(_, let viewModel):
            guard let viewModel else { return }
            Task {
                viewModel.isPreparingToNavigate = true
                await navigateToFilteredNotifications()
                viewModel.isPreparingToNavigate = false
            }
        case .notification:
            return
        case .groupedNotification(let notificationViewModel):
            notificationViewModel.defaultNavigation?()
        default:
            return
        }
    }

    func navigateToFilteredNotifications() async {
        guard
            let authBox = AuthenticationServiceProvider.shared.currentActiveUser
                .value
        else { return }

        do {
            let notificationRequests = try await APIService.shared
                .notificationRequests(authenticationBox: authBox).value
            let requestsViewModel = NotificationRequestsViewModel(
                authenticationBox: authBox, requests: notificationRequests)

            viewModel.navigateToScene?(
                .notificationRequests(viewModel: requestsViewModel), .show)  // TODO: should be .modal(animated) on large screens?
        } catch {
            viewModel.presentError?(error)
        }
    }
}

@MainActor
private class NotificationListViewModel: ObservableObject {

    @Published var displayedNotifications: ListType = .everything {
        didSet {
            createNewFeedLoader()
        }
    }
    @Published var notificationItems: [NotificationListItem] = []

    var filteredNotificationsViewModel =
        FilteredNotificationsRowView.ViewModel(policy: nil)
    private var notificationPolicyBannerRow: [NotificationListItem] {
        if filteredNotificationsViewModel.shouldShow {
            return [
                NotificationListItem.filteredNotificationsInfo(
                    nil, filteredNotificationsViewModel)
            ]
        } else {
            return []
        }
    }

    private var feedSubscription: AnyCancellable?
    private var feedLoader = GroupedNotificationFeedLoader(
        kind: .notificationsAll, navigateToScene: { _, _ in },
        presentError: { _ in })

    fileprivate var navigateToScene:
        ((SceneCoordinator.Scene, SceneCoordinator.Transition) -> Void)?
    {
        didSet {
            createNewFeedLoader()
        }
    }
    fileprivate var presentError: ((Error) -> Void)? {
        didSet {
            createNewFeedLoader()
        }
    }
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(notificationFilteringPolicyDidChange), name: .notificationFilteringChanged, object: nil)
    }
    
    @objc func notificationFilteringPolicyDidChange(_ notification: Notification) {
        fetchFilteredNotificationsPolicy()
    }

    private func fetchFilteredNotificationsPolicy() {
        guard presentError != nil && navigateToScene != nil else { return }
        guard
            let authBox = AuthenticationServiceProvider.shared.currentActiveUser
                .value
        else { return }
        Task {
            let policy = try? await APIService.shared.notificationPolicy(
                authenticationBox: authBox)
            updateFilteredNotificationsPolicy(policy?.value)
        }
    }

    func updateFilteredNotificationsPolicy(
        _ policy: Mastodon.Entity.NotificationPolicy?
    ) {

        filteredNotificationsViewModel.policy = policy

        let withoutFilteredRow = notificationItems.filter {
            !$0.isFilteredNotificationsRow
        }

        notificationItems =
            notificationPolicyBannerRow
            + withoutFilteredRow
        
        Task {
            await feedLoader.asyncLoadMore(olderThan: nil, newerThan: nil)
        }
    }

    private func createNewFeedLoader() {
        fetchFilteredNotificationsPolicy()
        feedLoader = GroupedNotificationFeedLoader(
            kind: displayedNotifications.feedKind,
            navigateToScene: navigateToScene, presentError: presentError)
        feedSubscription = feedLoader.$records
            .receive(on: DispatchQueue.main)
            .sink { [weak self] records in
                guard let self else { return }
                var updatedItems = records.allRecords.map {
                    NotificationListItem.groupedNotification($0)
                }
                if records.canLoadOlder {
                    updatedItems.append(.bottomLoader)
                }
                updatedItems = self.notificationPolicyBannerRow + updatedItems
                self.notificationItems = updatedItems
            }
        feedLoader.doFirstLoad()
    }

    public func refreshFeedFromTop() async {
        let newestKnown = feedLoader.records.allRecords.first?.newestID
        await feedLoader.asyncLoadMore(olderThan: nil, newerThan: newestKnown)
    }

    public func loadOlder() {
        let oldestKnown = feedLoader.records.allRecords.last?.oldestID
        Task {
            await feedLoader.asyncLoadMore(olderThan: oldestKnown, newerThan: nil)
        }
    }
}
