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
    private var picker = UISegmentedControl(items: [ ListType.everything.pickerLabel, ListType.mentions.pickerLabel ])

    init() {
        viewModel = NotificationListViewModel()
        let root = NotificationListView(viewModel: viewModel)
        super.init(rootView: root)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease.circle"), style: .plain, target: self, action: #selector(showNotificationPolicySettings))

        viewModel.presentError = { [weak self] error in
            let alert = UIAlertController(
                title: "Error", message: error.localizedDescription,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self?.sceneCoordinator?.rootViewController?.topMost?.present(
                alert, animated: true)
        }

        viewModel.navigateToScene = { [weak self] scene, transition in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sceneCoordinator?.present(
                    scene: scene, from: self, transition: transition)
            }
        }
        
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.selectedSegmentIndex = 0
        navigationItem.titleView = picker
        NSLayoutConstraint.activate([
            picker.widthAnchor.constraint(greaterThanOrEqualToConstant: 287)
        ])
        picker.addTarget(self, action: #selector(pickerValueChanged(_:)), for: .valueChanged)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError(
            "init(coder:) not implemented for NotificationListViewController")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        viewModel.checkCanGroupNotifications()
    }
    
    @objc private func pickerValueChanged(_ sender: UISegmentedControl) {
        viewModel.displayedNotifications = ListType(rawValue: sender.selectedSegmentIndex) ?? .everything
    }
    
    @objc private func showNotificationPolicySettings(_ sender: Any) {
        guard let policy = viewModel.filteredNotificationsViewModel.policy else { return }
        Task {
            let adminSettings: AdminNotificationFilterSettings? = await {
                guard let user = AuthenticationServiceProvider.shared.currentActiveUser.value, let role = user.cachedAccount?.role else { print("no role"); return nil }
                let hasAdminPermissions = role.hasPermissions(.administrator) || role.hasPermissions(.manageReports) || role.hasPermissions(.manageUsers)
                guard hasAdminPermissions else { print("no permissions"); return nil }
                if let existingPreferences = await BodegaPersistence.Notifications.currentPreferences(for: user.authentication) {
                    return existingPreferences
                } else {
                    return AdminNotificationFilterSettings(filterOutReports: false, filterOutSignups: false)
                }
            }()
            
            let policyViewModel = await NotificationFilterViewModel(
                NotificationFilterSettings(
                    notFollowing: policy.filterNotFollowing,
                    noFollower: policy.filterNotFollowers,
                    newAccount: policy.filterNewAccounts,
                    privateMentions: policy.filterPrivateMentions
                ),
                adminSettings: adminSettings
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

private enum ListType: Int {
    case everything = 0
    case mentions = 1

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
            ScrollViewReader { proxy in
                List {
                    ForEach(viewModel.notificationItems, id: \.self) { item in // without explicit id, scrollTo(:) does not work
                        let isUnread = viewModel.isUnread(item)
                        rowView(item, isUnread: isUnread ?? false)
                            .onAppear {
                                didAppear(item)
                            }
                            .onDisappear {
                                didDisappear(item, wasUnread: isUnread ?? false)
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
                .onAppear() {
                    viewDidAppear()
                }
                .onDisappear() {
                    viewDidDisappear()
                }
                .accessibilityAction(named: L10n.Common.Controls.Actions.seeMore) {
                    viewModel.requestLoad(.newer)
                }
            }
        }
    }

    @ViewBuilder func rowView(_ notificationListItem: NotificationListItem, isUnread: Bool)
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
                    .accessibilityElement(children: .combine)
                    .accessibilityAction {
                        didTap(item: notificationListItem)
                    }
            } else {
                Text("Some notifications have been filtered.")
            }
        case .notification:
            Text("obsolete item")
        case .groupedNotification(let viewModel):
            NotificationRowView(viewModel: viewModel)
                .padding(.vertical, 4)
//                .listRowBackground(
//                    backgroundView(isPrivate: viewModel.usePrivateBackground, isUnread: isUnread)
//                )
        }
    }
    
    
    @ViewBuilder func backgroundView(isPrivate: Bool, isUnread: Bool) -> some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 3)
            if isUnread {
                Rectangle()
                    .fill(Asset.Colors.accent.swiftUIColor)
                    .frame(width: 5)
            }
            Rectangle()
                .fill(isPrivate ?  Asset.Colors.accent.swiftUIColor : .clear)
                .opacity(0.1)
        }
    }
    
    func didAppear(_ item: NotificationListItem) {
        switch item {
        case .groupedNotification(let viewModel):
            viewModel.prepareForDisplay()
        case .bottomLoader:
            loadMore()
        default:
            break
        }
    }

    func didDisappear(_ item: NotificationListItem, wasUnread: Bool) {
        if wasUnread {
            viewModel.markAsRead(item)
        }
    }
    
    func viewDidAppear() {
        NotificationService.shared.clearNotificationCountForActiveUser()
        viewModel.requestLoad(.newer)
    }
    
    func viewDidDisappear() {
        NotificationService.shared.clearNotificationCountForActiveUser()
        Task {
            await viewModel.commitToCache()
        }
    }
    
    func loadMore() {
        viewModel.requestLoad(.older)
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
            notificationViewModel.doPrimaryNavigation()
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

    var displayedNotifications: ListType = .everything {
        didSet {
            Task { [weak self] in
                guard let self else { return }
                await self.feedLoader.commitToCache()
                self.createNewFeedLoader()
            }
        }
    }
    @Published var notificationItems: [NotificationListItem] = []
    
    private var firstUnreadItem: NotificationListItem? {
        guard let marker =  feedLoader.lastReadMarker else { return nil }
        let firstUnread = notificationItems.reversed().first { item in
            switch item {
            case .groupedNotification(let itemViewModel):
                if let itemNewestID =  itemViewModel.newestID {
                    return itemNewestID > marker.lastReadID
                } else {
                    return false
                }
            default:
                return false
            }
        }
        return firstUnread
    }
    
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
    private var feedLoader = GroupedNotificationFeedLoader(kind: .notificationsAll, navigateToScene: { _, _ in },
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
        
        feedLoader.requestLoad(.reload)
    }
    
    func isUnread(_ item: NotificationListItem) -> Bool? {
        switch item {
        case .bottomLoader, .filteredNotificationsInfo:
            return nil
        case .groupedNotification(let viewModel):
            if let id = viewModel.newestID {
                return feedLoader.isUnread(id)
            } else {
                return false
            }
        case .notification:
            assert(false)
            return nil
        }
    }
    
    func markAsRead(_ item: NotificationListItem) {
        switch item {
        case .bottomLoader, .filteredNotificationsInfo:
            break
        case .groupedNotification(let viewModel):
            if let id = viewModel.newestID {
                feedLoader.markAsRead(id)
            }
        case .notification:
            assert(false)
            break
        }
    }
    
    func checkCanGroupNotifications() {
        guard let currentInstance = AuthenticationServiceProvider.shared.currentActiveUser.value?.authentication.instanceConfiguration else {
            presentError?(APIService.APIError.implicit(.authenticationMissing))
            return
        }
        if currentInstance.canGroupNotifications, !feedLoader.useGroupedNotificationsApi {
            createNewFeedLoader()
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
                if !records.allRecords.isEmpty && records.canLoadOlder {
                    updatedItems.append(.bottomLoader)
                }
                updatedItems = self.notificationPolicyBannerRow + updatedItems
                self.notificationItems = updatedItems
            }
        feedLoader.doFirstLoad()
    }

    public func refreshFeedFromTop() async {
        if feedLoader.permissionToLoadImmediately {
            await feedLoader.loadImmediately(.newer)
        }
    }
    
    public func requestLoad(_ loadRequest: GroupedNotificationFeedLoader.FeedLoadRequest) {
        feedLoader.requestLoad(loadRequest)
    }
    
    public func commitToCache() async {
        await feedLoader.commitToCache()
    }
}

extension NotificationRowViewModel.NotificationNavigation {
    var a11yTitle: String? {
        switch self {
        case .link(let description, _):
            return description
        case .myFollowers:
            return L10n.Scene.Profile.Dashboard.myFollowers // TODO: improve string
        case .profile(let account):
            return  L10n.Common.Controls.Status.MetaEntity.mention(account.displayNameWithFallback)
        }
    }
}
