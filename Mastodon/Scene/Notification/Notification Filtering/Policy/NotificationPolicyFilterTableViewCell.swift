// Copyright © 2024 Mastodon gGmbH. All rights reserved.

import MastodonSDK
import UIKit
import MastodonLocalization
import MastodonAsset

protocol NotificationPolicyFilterTableViewCellDelegate: AnyObject {
    func pickerValueChanged(
        _ tableViewCell: NotificationPolicyFilterTableViewCell,
        filterItem: NotificationFilterItem,
        newValue: Mastodon.Entity.NotificationPolicy.NotificationFilterAction)
}

class NotificationPolicyFilterTableViewCell: TrailingButtonTableViewCell
{
    typealias FilterActionOption = Mastodon.Entity.NotificationPolicy.NotificationFilterAction
    
    override class var reuseIdentifier: String {
        return "NotificationPolicyFilterTableViewCell"
    }

    private let options:
        [FilterActionOption] = [
            .accept, .filter, .drop,
        ]

    var filterItem: NotificationFilterItem?
    weak var delegate: NotificationPolicyFilterTableViewCellDelegate?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        label.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 17, weight: .regular))
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.font = UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .systemFont(ofSize: 15, weight: .regular))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func indexForOption(_ option: FilterActionOption) -> Int {
        return options.firstIndex(of: option) ?? 0
    }

    public func configure(
        with filterItem: NotificationFilterItem,
        viewModel: NotificationFilterViewModel
    ) {
        label.text = filterItem.title
        subtitleLabel.text = filterItem.subtitle
        self.filterItem = filterItem

        let buttonTitle: String
        switch viewModel.value(forItem: filterItem) {
        case .accept:               buttonTitle = L10n.Scene.Notification.Policy.Action.Accept.title
        case .filter:               buttonTitle = L10n.Scene.Notification.Policy.Action.Filter.title
        case .drop:                 buttonTitle = L10n.Scene.Notification.Policy.Action.Drop.title
        case ._other(let string):   buttonTitle = string
        }
        button.configuration = .bordered()
        button.configuration?.title = buttonTitle
        button.configuration?.background.strokeColor = Asset.Colors.Brand.blurple.color
        button.configuration?.baseForegroundColor = Asset.Colors.Brand.blurple.color
        button.showsMenuAsPrimaryAction = true
        
        let menuActions = [FilterActionOption.accept, .filter, .drop].map { option in
            UIAction(title: option.displayTitle, subtitle: option.displaySubtitle, state: viewModel.value(forItem: filterItem) == option ? .on : .off, handler: { [weak self] _ in
                guard let self else { return }
                self.delegate?.pickerValueChanged(self, filterItem: filterItem, newValue: option)
            })
        }
        
        button.menu = UIMenu.init(children: menuActions)
    }
}

protocol NotificationAdminFilterTableViewCellDelegate: AnyObject {
    func toggleValueChanged(
        _ tableViewCell: NotificationAdminFilterTableViewCell,
        filterItem: NotificationFilterItem,
        newValue: Bool)
}

class NotificationAdminFilterTableViewCell: ToggleTableViewCell {
    override class var reuseIdentifier: String {
        return "NotificationAdminFilterTableViewCell"
    }

    var filterItem: NotificationFilterItem?
    weak var delegate: NotificationAdminFilterTableViewCellDelegate?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        label.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 17, weight: .regular))
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.font = UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .systemFont(ofSize: 15, weight: .regular))

        toggle.addTarget(
            self,
            action: #selector(
                NotificationAdminFilterTableViewCell.toggleValueChanged(_:)),
            for: .valueChanged)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(
        with filterItem: NotificationFilterItem,
        viewModel: NotificationFilterViewModel
    ) {
        label.text = filterItem.title
        subtitleLabel.text = filterItem.subtitle
        self.filterItem = filterItem

        let toggleIsOn = viewModel.value(forItem: filterItem) == .accept

        toggle.isOn = toggleIsOn
    }

    @objc func toggleValueChanged(_ sender: UISwitch) {
        guard let filterItem, let delegate else { return }

        delegate.toggleValueChanged(
            self, filterItem: filterItem, newValue: sender.isOn)
    }
}

extension Mastodon.Entity.NotificationPolicy.NotificationFilterAction {
    var displayTitle: String {
        switch self {
        case .accept:  return L10n.Scene.Notification.Policy.Action.Accept.title
        case .filter:  return L10n.Scene.Notification.Policy.Action.Filter.title
        case .drop:    return L10n.Scene.Notification.Policy.Action.Drop.title
        case ._other(let string): return string
        }
    }
    
    var displaySubtitle: String {
        switch self {
        case .accept:  return L10n.Scene.Notification.Policy.Action.Accept.subtitle
        case .filter:  return L10n.Scene.Notification.Policy.Action.Filter.subtitle
        case .drop:    return L10n.Scene.Notification.Policy.Action.Drop.subtitle
        case ._other: return ""
        }
    }
}
