//
//  NotificationItem.swift
//  Mastodon
//
//  Created by sxiaojian on 2021/4/13.
//

import CoreData
import Foundation
import MastodonSDK
import MastodonLocalization

enum NotificationListItem {
    case filteredNotificationsInfo(
        Mastodon.Entity.NotificationPolicy?,
        FilteredNotificationsRowView.ViewModel?)
    case notification(MastodonFeedItemIdentifier)  // TODO: Remove. Will require rewriting the NotificationRequestsTableViewController.
    case groupedNotification(NotificationRowViewModel)
    case bottomLoader
    
    var rowViewModel: NotificationRowViewModel? {
        switch self {
        case .filteredNotificationsInfo, .notification, .bottomLoader:
            return nil
        case .groupedNotification(let model):
            return model
        }
    }

    var fetchAnchor: MastodonFeedItemIdentifier? {
        switch self {
        case .filteredNotificationsInfo:
            return nil
        case .notification(let identifier):
            return identifier
        case .groupedNotification(let viewModel):
            return viewModel.notification.identifier
        case .bottomLoader:
            return nil
        }
    }

    var isFilteredNotificationsRow: Bool {
        switch self {
        case .filteredNotificationsInfo:
            return true
        default:
            return false
        }
    }
    
    var primaryA11yActionTitle: String? {
        switch self {
        case .filteredNotificationsInfo:
            return L10n.Scene.Notification.FilteredNotification.title // TODO: improve string
        case .notification:
            return nil
        case .groupedNotification(let viewModel):
            return viewModel.primaryNavigation?.a11yTitle
        case .bottomLoader:
            return nil
        }
    }
}

extension NotificationListItem: Identifiable, Equatable, Hashable {
    typealias ID = String

    var id: ID {
        switch self {
        case .filteredNotificationsInfo:
            return "filtered_notifications_info"
        case .notification(let identifier):
            return identifier.id
        case .groupedNotification(let viewModel):
            return viewModel.id
        case .bottomLoader:
            return "bottom_loader"
        }
    }

    static func == (lhs: NotificationListItem, rhs: NotificationListItem)
        -> Bool
    {
        switch (lhs, rhs) {
        case (.filteredNotificationsInfo(let lPolicy, _), .filteredNotificationsInfo(let rPolicy, _)):
            return lPolicy == rPolicy
        case (.groupedNotification(let lViewModel), .groupedNotification(let rViewModel)):
            return lViewModel.notification.identifier == rViewModel.notification.identifier && lViewModel.notification.newestID == rViewModel.notification.newestID
        case (.bottomLoader, .bottomLoader):
            return true
        case (.notification(let lFeedItem), .notification(let rFeedItem)):
            return lFeedItem == rFeedItem
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
