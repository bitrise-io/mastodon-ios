//
//  NotificationTimelineViewModel+Diffable.swift
//  Mastodon
//
//  Created by MainasuK on 2022-1-21.
//

import UIKit
import CoreData
import MastodonSDK
import MastodonCore

extension NotificationTimelineViewModel {
    
    func setupDiffableDataSource(
        tableView: UITableView,
        notificationTableViewCellDelegate: NotificationTableViewCellDelegate
    ) {
        diffableDataSource = NotificationSection.diffableDataSource(
            tableView: tableView,
            configuration: NotificationSection.Configuration(
                authenticationBox: authenticationBox,
                notificationTableViewCellDelegate: notificationTableViewCellDelegate,
                filterContext: .notifications
            )
        )

        var snapshot = NSDiffableDataSourceSnapshot<NotificationSection, NotificationListItem>()
        snapshot.appendSections([.main])
        diffableDataSource?.apply(snapshot)
        
        feedLoader.$records
            .receive(on: DispatchQueue.main)
            .sink { [weak self] records in
                guard let self else { return }
                guard let diffableDataSource = self.diffableDataSource else { return }

                Task {
                    let oldSnapshot = diffableDataSource.snapshot()
                    let newSnapshot: NSDiffableDataSourceSnapshot<NotificationSection, NotificationListItem> = {
                        let newItems = records.allRecords.map { record in
                            NotificationListItem.notification(MastodonFeedItemIdentifier.notification(id: record.id))
                        }
                        var snapshot = NSDiffableDataSourceSnapshot<NotificationSection, NotificationListItem>()
                        snapshot.appendSections([.main])
                        if self.scope == .everything, let notificationPolicy = self.notificationPolicy, notificationPolicy.summary.pendingRequestsCount > 0 {
                            snapshot.appendItems([.filteredNotificationsInfo(notificationPolicy, nil)])
                        }
                        snapshot.appendItems(newItems.removingDuplicates(), toSection: .main)
                        return snapshot
                    }()

                    let hasChanges = newSnapshot.itemIdentifiers != oldSnapshot.itemIdentifiers
                    if !hasChanges {
                        self.didLoadLatest.send()
                        return
                    }

                    await self.updateSnapshotUsingReloadData(snapshot: newSnapshot)
                    self.didLoadLatest.send()
                }   // end Task
            }
            .store(in: &disposeBag)
    }   // end func setupDiffableDataSource

}

extension NotificationTimelineViewModel {
    @MainActor func updateSnapshotUsingReloadData(
        snapshot: NSDiffableDataSourceSnapshot<NotificationSection, NotificationListItem>
    ) async {
        await self.diffableDataSource?.applySnapshotUsingReloadData(snapshot)
    }
    
}
