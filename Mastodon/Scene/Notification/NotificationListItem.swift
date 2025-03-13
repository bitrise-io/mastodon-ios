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
    case notification(MastodonFeedItemIdentifier)  // TODO: remove
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
            return viewModel.identifier
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
        case .notification(let identifier):
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
            return viewModel.identifier.id
        case .bottomLoader:
            return "bottom_loader"
        }
    }

    static func == (lhs: NotificationListItem, rhs: NotificationListItem)
        -> Bool
    {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
