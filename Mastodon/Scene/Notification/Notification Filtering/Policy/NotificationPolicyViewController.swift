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
    case notFollowers
    case newAccounts
    case privateMentions
    case limitedAccounts
    
    case adminReports
    case adminSignups
    
    static let regularOptions = [Self.notFollowing, .notFollowers, .newAccounts, .privateMentions, .limitedAccounts]
    static let adminOptions = [Self.adminReports, .adminSignups]

    var title: String {
        switch self {
        case .notFollowing:
            return L10n.Scene.Notification.Policy.NotFollowing.title
        case .notFollowers:
            return L10n.Scene.Notification.Policy.NoFollower.title
        case .newAccounts:
            return L10n.Scene.Notification.Policy.NewAccount.title
        case .privateMentions:
            return L10n.Scene.Notification.Policy.PrivateMentions.title
        case .limitedAccounts:
            return L10n.Scene.Notification.Policy.ModeratedAccounts.title
            
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
        case .notFollowers:
            return L10n.Scene.Notification.Policy.NoFollower.subtitle
        case .newAccounts:
            return L10n.Scene.Notification.Policy.NewAccount.subtitle
        case .privateMentions:
            return L10n.Scene.Notification.Policy.PrivateMentions.subtitle
        case .limitedAccounts:
            return L10n.Scene.Notification.Policy.ModeratedAccounts.subtitle
            
        case .adminReports:
            return L10n.Scene.Notification.AdminFilter.Reports.subtitle
        case .adminSignups:
            return L10n.Scene.Notification.AdminFilter.Signups.subtitle
        }
    }
}

struct NotificationFilterSettings: Codable, Equatable {
    let forNotFollowing: Mastodon.Entity.NotificationPolicy.NotificationFilterAction
    let forNotFollowers: Mastodon.Entity.NotificationPolicy.NotificationFilterAction
    let forNewAccounts: Mastodon.Entity.NotificationPolicy.NotificationFilterAction
    let forPrivateMentions: Mastodon.Entity.NotificationPolicy.NotificationFilterAction
    let forLimitedAccounts: Mastodon.Entity.NotificationPolicy.NotificationFilterAction
}
struct AdminNotificationFilterSettings: Codable, Equatable {
    let forReports: Mastodon.Entity.NotificationPolicy.NotificationFilterAction
    let forSignups: Mastodon.Entity.NotificationPolicy.NotificationFilterAction
    
    var excludedNotificationTypes: [Mastodon.Entity.NotificationType]? {
        var excluded = [Mastodon.Entity.NotificationType]()
        if forReports != .accept {
            excluded.append(.adminReport)
        }
        if forSignups != .accept {
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
    
    func value(forItem item: NotificationFilterItem) -> Mastodon.Entity.NotificationPolicy.NotificationFilterAction {
        switch item {
        case .notFollowing:
            return regularFilterSettings.forNotFollowing
        case .notFollowers:
            return regularFilterSettings.forNotFollowers
        case .newAccounts:
            return regularFilterSettings.forNewAccounts
        case .privateMentions:
            return regularFilterSettings.forPrivateMentions
        case .limitedAccounts:
            return regularFilterSettings.forLimitedAccounts
        case .adminReports:
            return adminFilterSettings?.forReports ?? .drop
        case .adminSignups:
            return adminFilterSettings?.forSignups ?? .drop
        }
    }

    func setValue(_ value: Mastodon.Entity.NotificationPolicy.NotificationFilterAction, forItem item: NotificationFilterItem) {
        switch item {
        case .notFollowing:
            regularFilterSettings = NotificationFilterSettings(
                forNotFollowing: value,
                forNotFollowers: regularFilterSettings.forNotFollowers,
                forNewAccounts: regularFilterSettings.forNewAccounts,
                forPrivateMentions: regularFilterSettings.forPrivateMentions,
                forLimitedAccounts: regularFilterSettings.forLimitedAccounts)
        case .notFollowers:
            regularFilterSettings = NotificationFilterSettings(
                forNotFollowing: regularFilterSettings.forNotFollowing,
                forNotFollowers: value,
                forNewAccounts: regularFilterSettings.forNewAccounts,
                forPrivateMentions: regularFilterSettings.forPrivateMentions,
                forLimitedAccounts: regularFilterSettings.forLimitedAccounts)
        case .newAccounts:
            regularFilterSettings = NotificationFilterSettings(
                forNotFollowing: regularFilterSettings.forNotFollowing,
                forNotFollowers: regularFilterSettings.forNotFollowers,
                forNewAccounts: value,
                forPrivateMentions: regularFilterSettings.forPrivateMentions,
                forLimitedAccounts: regularFilterSettings.forLimitedAccounts)
        case .privateMentions:
            regularFilterSettings = NotificationFilterSettings(
                forNotFollowing: regularFilterSettings.forNotFollowing,
                forNotFollowers: regularFilterSettings.forNotFollowers,
                forNewAccounts: regularFilterSettings.forNewAccounts,
                forPrivateMentions: value,
                forLimitedAccounts: regularFilterSettings.forLimitedAccounts)
        case .limitedAccounts:
            regularFilterSettings = NotificationFilterSettings(
                forNotFollowing: regularFilterSettings.forNotFollowing,
                forNotFollowers: regularFilterSettings.forNotFollowers,
                forNewAccounts: regularFilterSettings.forNewAccounts,
                forPrivateMentions: regularFilterSettings.forPrivateMentions,
                forLimitedAccounts: value)
            
        case .adminReports:
            guard let adminFilterSettings else { return }
            self.adminFilterSettings = AdminNotificationFilterSettings(
                forReports: value,
                forSignups: adminFilterSettings.forSignups)
        case .adminSignups:
            guard let adminFilterSettings else { return }
            self.adminFilterSettings = AdminNotificationFilterSettings(
                forReports: adminFilterSettings.forReports,
                forSignups: value)
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
        regularItems = [.notFollowing, .notFollowers, .newAccounts, .privateMentions, .limitedAccounts]
        adminItems = [.adminReports, .adminSignups]

        headerBar = NotificationPolicyHeaderView()
        headerBar.translatesAutoresizingMaskIntoConstraints = false

        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(
            NotificationPolicyFilterTableViewCell.self,
            forCellReuseIdentifier: NotificationPolicyFilterTableViewCell.reuseIdentifier
        )
        tableView.register(
            NotificationAdminFilterTableViewCell.self,
            forCellReuseIdentifier: NotificationAdminFilterTableViewCell.reuseIdentifier
        )
        tableView.contentInset.top = -20

        super.init(nibName: nil, bundle: nil)

        let dataSource = UITableViewDiffableDataSource<
            NotificationFilterSection, NotificationFilterItem
        >(tableView: tableView) {
            [weak self] tableView, indexPath, itemIdentifier in
            guard let self else {
                fatalError("No NotificationPolicyFilterTableViewCell")
            }
            
            let cell = tableView.dequeueReusableCell(
                withIdentifier: indexPath.section == 0 ? NotificationPolicyFilterTableViewCell
                    .reuseIdentifier: NotificationAdminFilterTableViewCell.reuseIdentifier, for: indexPath)
            
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
            if let cell = cell as? NotificationAdminFilterTableViewCell {
                cell.configure(with: item, viewModel: self.viewModel)
                cell.delegate = self
            } else if let cell = cell as? NotificationPolicyFilterTableViewCell {
                cell.configure(with: item, viewModel: self.viewModel)
                cell.delegate = self
            }
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
        if viewModel.adminFilterSettings != nil {
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
                        forNotFollowing: viewModel.value(forItem: .notFollowing),
                        forNotFollowers: viewModel.value(forItem: .notFollowers),
                        forNewAccounts: viewModel.value(forItem: .newAccounts),
                        forPrivateMentions: viewModel.value(forItem: .privateMentions),
                        forLimitedAccounts: viewModel.value(forItem: .limitedAccounts)
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

        guard indexPath.section == 1 else { return }
        let filterItem: NotificationFilterItem? = adminItems[indexPath.row]
        guard let filterItem else { return }
        let currentValue = viewModel.value(forItem: filterItem) == .accept
        setBool(!currentValue, forItem: filterItem)

        if let snapshot = dataSource?.snapshot() {
            dataSource?.applySnapshotUsingReloadData(snapshot)
        }
    }
}

extension NotificationPolicyViewController {
    func setBool(_ boolValue: Bool, forItem filterItem: NotificationFilterItem) {
        let option = boolValue ? Mastodon.Entity.NotificationPolicy.NotificationFilterAction.accept : .drop
        viewModel.setValue(option, forItem: filterItem)
        tableView.reloadData()
    }
}

extension NotificationPolicyViewController:
    NotificationPolicyFilterTableViewCellDelegate
{
    func pickerValueChanged(_ tableViewCell: NotificationPolicyFilterTableViewCell, filterItem: NotificationFilterItem, newValue: MastodonSDK.Mastodon.Entity.NotificationPolicy.NotificationFilterAction) {
        viewModel.setValue(newValue, forItem: filterItem)
        tableView.reloadData()
    }
}

extension NotificationPolicyViewController : NotificationAdminFilterTableViewCellDelegate {
    func toggleValueChanged(
        _ tableViewCell: NotificationAdminFilterTableViewCell,
        filterItem: NotificationFilterItem, newValue: Bool
    ) {
        setBool(newValue, forItem: filterItem)
    }
}
