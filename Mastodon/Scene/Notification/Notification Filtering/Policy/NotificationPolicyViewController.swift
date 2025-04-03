// Copyright © 2024 Mastodon gGmbH. All rights reserved.

import MastodonAsset
import MastodonCore
import MastodonLocalization
import MastodonSDK
import UIKit

enum NotificationFilterSection: Hashable {
    case main
    case admin
}

enum NotificationFilterItem: Hashable {
    case notFollowing
    case noFollower
    case newAccount
    case privateMentions
    case adminReports
    case adminSignups

    var title: String {
        switch self {
        case .notFollowing:
            return L10n.Scene.Notification.Policy.NotFollowing.title
        case .noFollower:
            return L10n.Scene.Notification.Policy.NoFollower.title
        case .newAccount:
            return L10n.Scene.Notification.Policy.NewAccount.title
        case .privateMentions:
            return L10n.Scene.Notification.Policy.PrivateMentions.title
        case .adminReports:
            return L10n.Scene.Notification.AdminFilter.Reports.title
        case .adminSignups:
            return L10n.Scene.Notification.AdminFilter.Signups.title
        }
    }

    var subtitle: String {
        switch self {
        case .notFollowing:
            return L10n.Scene.Notification.Policy.NotFollowing.subtitle
        case .noFollower:
            return L10n.Scene.Notification.Policy.NoFollower.subtitle
        case .newAccount:
            return L10n.Scene.Notification.Policy.NewAccount.subtitle
        case .privateMentions:
            return L10n.Scene.Notification.Policy.PrivateMentions.subtitle
        case .adminReports:
            return L10n.Scene.Notification.AdminFilter.Reports.subtitle
        case .adminSignups:
            return L10n.Scene.Notification.AdminFilter.Signups.subtitle
        }
    }
}

struct NotificationFilterSettings: Codable, Equatable {
    let notFollowing: Bool
    let noFollower: Bool
    let newAccount: Bool
    let privateMentions: Bool
}
struct AdminNotificationFilterSettings: Codable, Equatable {
    let filterOutReports: Bool
    let filterOutSignups: Bool
    
    var excludedNotificationTypes: [Mastodon.Entity.NotificationType]? {
        var excluded = [Mastodon.Entity.NotificationType]()
        if filterOutReports {
            excluded.append(.adminReport)
        }
        if filterOutSignups {
            excluded.append(.adminSignUp)
        }
        return excluded.isEmpty ? nil : excluded
    }
}

class NotificationFilterViewModel {
    let originalRegularSettings: NotificationFilterSettings
    let originalAdminSettings: AdminNotificationFilterSettings?

    var regularFilterSettings: NotificationFilterSettings
    var adminFilterSettings: AdminNotificationFilterSettings?

    init(
        _ regularSettings: NotificationFilterSettings,
        adminSettings: AdminNotificationFilterSettings?
    ) async {
        self.originalRegularSettings = regularSettings
        self.regularFilterSettings = regularSettings
        self.originalAdminSettings = adminSettings
        self.adminFilterSettings = adminSettings
    }
    
    func value(forItem item: NotificationFilterItem) -> Bool {
        switch item {
        case .notFollowing:
            return regularFilterSettings.notFollowing
        case .noFollower:
            return regularFilterSettings.noFollower
        case .newAccount:
            return regularFilterSettings.newAccount
        case .privateMentions:
            return regularFilterSettings.privateMentions
        case .adminReports:
            return adminFilterSettings?.filterOutReports ?? true
        case .adminSignups:
            return adminFilterSettings?.filterOutSignups ?? true
        }
    }

    func setValue(_ value: Bool, forItem item: NotificationFilterItem) {
        switch item {
        case .notFollowing:
            regularFilterSettings = NotificationFilterSettings(
                notFollowing: value,
                noFollower: regularFilterSettings.noFollower,
                newAccount: regularFilterSettings.newAccount,
                privateMentions: regularFilterSettings.privateMentions)
        case .noFollower:
            regularFilterSettings = NotificationFilterSettings(
                notFollowing: regularFilterSettings.notFollowing,
                noFollower: value,
                newAccount: regularFilterSettings.newAccount,
                privateMentions: regularFilterSettings.privateMentions)
        case .newAccount:
            regularFilterSettings = NotificationFilterSettings(
                notFollowing: regularFilterSettings.notFollowing,
                noFollower: regularFilterSettings.noFollower,
                newAccount: value,
                privateMentions: regularFilterSettings.privateMentions)
        case .privateMentions:
            regularFilterSettings = NotificationFilterSettings(
                notFollowing: regularFilterSettings.notFollowing,
                noFollower: regularFilterSettings.noFollower,
                newAccount: regularFilterSettings.newAccount,
                privateMentions: value)
        case .adminReports:
            guard let adminFilterSettings else { return }
            self.adminFilterSettings = AdminNotificationFilterSettings(
                filterOutReports: value,
                filterOutSignups: adminFilterSettings.filterOutSignups)
        case .adminSignups:
            guard let adminFilterSettings else { return }
            self.adminFilterSettings = AdminNotificationFilterSettings(
                filterOutReports: adminFilterSettings.filterOutReports,
                filterOutSignups: value)
        }
    }
}

protocol NotificationPolicyViewControllerDelegate: AnyObject {
    func policyUpdated(
        _ viewController: NotificationPolicyViewController,
        newPolicy: Mastodon.Entity.NotificationPolicy)
}

class NotificationPolicyViewController: UIViewController {

    let tableView: UITableView
    let headerBar: NotificationPolicyHeaderView
    var saveItem: UIBarButtonItem?
    var dataSource:
        UITableViewDiffableDataSource<
            NotificationFilterSection, NotificationFilterItem
        >?
    let regularItems: [NotificationFilterItem]
    let adminItems: [NotificationFilterItem]
    var viewModel: NotificationFilterViewModel
    weak var delegate: NotificationPolicyViewControllerDelegate?

    init(viewModel: NotificationFilterViewModel) {
        self.viewModel = viewModel
        regularItems = [.notFollowing, .noFollower, .newAccount, .privateMentions]
        adminItems = [.adminReports, .adminSignups]

        headerBar = NotificationPolicyHeaderView()
        headerBar.translatesAutoresizingMaskIntoConstraints = false

        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(
            NotificationPolicyFilterTableViewCell.self,
            forCellReuseIdentifier: NotificationPolicyFilterTableViewCell
                .reuseIdentifier)
        tableView.contentInset.top = -20

        super.init(nibName: nil, bundle: nil)

        let dataSource = UITableViewDiffableDataSource<
            NotificationFilterSection, NotificationFilterItem
        >(tableView: tableView) {
            [weak self] tableView, indexPath, itemIdentifier in
            guard let self,
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: NotificationPolicyFilterTableViewCell
                        .reuseIdentifier, for: indexPath)
                    as? NotificationPolicyFilterTableViewCell
            else {
                fatalError("No NotificationPolicyFilterTableViewCell")
            }

            let item: NotificationFilterItem?
            switch indexPath.section {
            case 0:
                item = regularItems[indexPath.row]
            case 1:
                item = adminItems[indexPath.row]
            default:
                item = nil
                assertionFailure()
            }
            guard let item else { return nil }
            cell.configure(with: item, viewModel: self.viewModel)
            cell.delegate = self

            return cell
        }

        tableView.dataSource = dataSource
        tableView.delegate = self

        self.dataSource = dataSource
        view.addSubview(headerBar)
        view.addSubview(tableView)
        view.backgroundColor = .systemGroupedBackground
        headerBar.closeButton.addTarget(
            self, action: #selector(NotificationPolicyViewController.save(_:)),
            for: .touchUpInside)

        setupConstraints()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        var snapshot = NSDiffableDataSourceSnapshot<
            NotificationFilterSection, NotificationFilterItem
        >()

        snapshot.appendSections([.main])
        snapshot.appendItems(regularItems)
        if let adminFilterSettings = viewModel.adminFilterSettings {
            snapshot.appendSections([.admin])
            snapshot.appendItems(adminItems)
        }

        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupConstraints() {
        let constraints = [
            headerBar.topAnchor.constraint(equalTo: view.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: tableView.bottomAnchor),
        ]

        NSLayoutConstraint.activate(constraints)
    }

    // MARK: - Action

    @objc private func save(_ sender: UIButton) {
        guard
            let authenticationBox = AuthenticationServiceProvider.shared
                .currentActiveUser.value
        else { return }

        Task { [weak self] in
            guard let self else { return }

            do {
                if let adminPreferences = viewModel.adminFilterSettings, viewModel.adminFilterSettings != viewModel.originalAdminSettings {
                    try await BodegaPersistence.Notifications.updatePreferences(adminPreferences, for: authenticationBox)
                }
            } catch {}
            
            do {
                let updatedPolicy = try await APIService.shared
                    .updateNotificationPolicy(
                        authenticationBox: authenticationBox,
                        filterNotFollowing: viewModel.value(forItem: .notFollowing),
                        filterNotFollowers: viewModel.value(forItem: .noFollower),
                        filterNewAccounts: viewModel.value(forItem: .newAccount),
                        filterPrivateMentions: viewModel.value(forItem: .privateMentions)
                    ).value

                delegate?.policyUpdated(self, newPolicy: updatedPolicy)

                NotificationCenter.default.post(
                    name: .notificationFilteringChanged, object: nil)

            } catch {}
        }

        dismiss(animated: true)
    }

    @objc private func cancel(_ sender: UIBarButtonItem) {
        dismiss(animated: true)
    }
}

//MARK: - UITableViewDelegate

extension NotificationPolicyViewController: UITableViewDelegate {
    func tableView(
        _ tableView: UITableView, didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)

        let filterItem: NotificationFilterItem? = {
            switch indexPath.section {
            case 0:
                return regularItems[indexPath.row]
            case 1:
                return adminItems[indexPath.row]
            default:
                return nil
            }
        }()
        guard let filterItem else { return }
        let currentValue = viewModel.value(forItem: filterItem)
        viewModel.setValue(!currentValue, forItem: filterItem)

        if let snapshot = dataSource?.snapshot() {
            dataSource?.applySnapshotUsingReloadData(snapshot)
        }
    }
}

extension NotificationPolicyViewController:
    NotificationPolicyFilterTableViewCellDelegate
{
    func toggleValueChanged(
        _ tableViewCell: NotificationPolicyFilterTableViewCell,
        filterItem: NotificationFilterItem, newValue: Bool
    ) {
        viewModel.setValue(newValue, forItem: filterItem)
    }
}
