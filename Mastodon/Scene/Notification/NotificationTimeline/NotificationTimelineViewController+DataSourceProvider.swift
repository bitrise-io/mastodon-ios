//
//  NotificationTimelineViewController+DataSourceProvider.swift
//  Mastodon
//
//  Created by MainasuK on 2022-1-26.
//

import UIKit
import MastodonSDK

extension NotificationTimelineViewController: DataSourceProvider {
    var filterContext: MastodonSDK.Mastodon.Entity.FilterContext? {
        return .notifications
    }
    
    func didToggleContentWarningDisplayStatus(status: MastodonSDK.MastodonStatus) {
        tableView.reloadData()
    }
    
    func item(from source: DataSourceItem.Source) async -> DataSourceItem? {
        var _indexPath = source.indexPath
        if _indexPath == nil, let cell = source.tableViewCell {
            _indexPath = await self.indexPath(for: cell)
        }
        guard let indexPath = _indexPath else { return nil }
        
        guard let item = viewModel.diffableDataSource?.itemIdentifier(for: indexPath) else {
            return nil
        }
        
        switch item {
        case .notification(let notificationItem):
            switch notificationItem {
            case .notification, .notificationGroup:
                let item: DataSourceItem? = {
                    //                guard feed.kind == .notificationAll || feed.kind == .notificationMentions else { return nil }
                    if let cachedItem = MastodonFeedItemCacheManager.shared.cachedItem(notificationItem) {
                        if let notification = cachedItem as? Mastodon.Entity.Notification {
                            let mastodonNotification = MastodonNotification.fromEntity(notification, relationship: nil)
                            return .notification(record: mastodonNotification)
                        } else if let notificationGroup = cachedItem as? Mastodon.Entity.NotificationGroup {
                            if let statusID = notificationGroup.statusID, let statusEntity = MastodonFeedItemCacheManager.shared.cachedItem(.status(id: statusID)) as? Mastodon.Entity.Status {
                                let status = MastodonStatus.fromEntity(statusEntity)
                                return .status(record: status)
                            }/* else if notificationGroup.type == .follow {
                                return .followers
                            } */ else {
                                return nil
                            }
                        }
                    }
                    return nil
                }()
                return item
            case .status:
                assertionFailure("unexpected item in notifications feed")
                return nil
            }
        case .groupedNotification:
            assertionFailure("grouped notifications are not supported in the legacy NotificationTimelineViewController")
            return nil
        case .filteredNotificationsInfo(let policy, _):
            guard let policy else { return nil }
            return DataSourceItem.notificationBanner(policy: policy)
        case .bottomLoader:
            return nil
        }
    }
    
    func update(contentStatus: MastodonStatus, intent: MastodonStatus.UpdateIntent) {
        MastodonFeedItemCacheManager.shared.addToCache(contentStatus.entity)
        if let reblog = contentStatus.entity.reblog {
            MastodonFeedItemCacheManager.shared.addToCache(reblog)
        }
        viewModel.reloadData()
    }
    
    @MainActor
    private func indexPath(for cell: UITableViewCell) async -> IndexPath? {
        return tableView.indexPath(for: cell)
    }
}
