// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import MastodonSDK
import Boutique
import MastodonCore

extension MastodonFeedKind {
    var storageTag: String? {
        switch self {
        case .notificationsAll:
            return "all"
        case .notificationsMentionsOnly:
            return "mentions"
        case .notificationsWithAccount:
            return nil
        }
    }
}

fileprivate let storageFileNameComponentSeparator = "_"

fileprivate func storeFilenameFromBasename(_ basename: String, kind: MastodonFeedKind, forUser userIdentifier: MastodonUserIdentifier) -> String {
    assert(kind.storageTag != nil, "ATTEMPTING TO CACHE A FEED TYPE THAT SHOULD NOT BE CACHED")
    let components = [userIdentifier.globallyUniqueUserIdentifier,
                      basename,
                      (kind.storageTag ?? "UNEXPECTED")]
    return components.joined(separator: storageFileNameComponentSeparator)
}

extension Store where Item == Mastodon.Entity.Notification {
    static func ungroupedNotificationStore(forKind feedKind: MastodonFeedKind, forUser userIdentifier: MastodonUserIdentifier) -> Store<Mastodon.Entity.Notification> {
        return Store<Mastodon.Entity.Notification>(
            storage: SQLiteStorageEngine.default(appendingPath: storeFilenameFromBasename("ungrouped_notification_store", kind: feedKind, forUser: userIdentifier)), cacheIdentifier: \.id)
    }
}

extension Store where Item == Mastodon.Entity.NotificationGroup {
    static func notificationGroupStore(forKind feedKind: MastodonFeedKind, forUser userIdentifier: MastodonUserIdentifier) -> Store<Mastodon.Entity.NotificationGroup> {
        return Store<Mastodon.Entity.NotificationGroup>(
            storage: SQLiteStorageEngine.default(appendingPath: storeFilenameFromBasename("notification_group_store", kind: feedKind, forUser: userIdentifier)), cacheIdentifier: \.id)
    }
}

extension Store where Item == Mastodon.Entity.Account {
    static func notificationRelevantFullAccountStore(forKind feedKind: MastodonFeedKind, forUser userIdentifier: MastodonUserIdentifier) -> Store<Mastodon.Entity.Account> {
        return Store<Mastodon.Entity.Account>(
            storage: SQLiteStorageEngine.default(appendingPath: storeFilenameFromBasename("notification_relevant_full_account_store", kind: feedKind, forUser: userIdentifier)), cacheIdentifier: \.id)
    }
}

extension Store where Item == Mastodon.Entity.PartialAccountWithAvatar {
    static func notificationRelevantPartialAccountStore(forKind feedKind: MastodonFeedKind, forUser userIdentifier: MastodonUserIdentifier) -> Store<Mastodon.Entity.PartialAccountWithAvatar> {
        return Store<Mastodon.Entity.PartialAccountWithAvatar>(
            storage: SQLiteStorageEngine.default(appendingPath: storeFilenameFromBasename("notification_relevant_partial_account_store", kind: feedKind, forUser: userIdentifier)), cacheIdentifier: \.id)
    }
}

extension Store where Item == Mastodon.Entity.Status {
    static func notificationRelevantStatusStore(forKind feedKind: MastodonFeedKind, forUser userIdentifier: MastodonUserIdentifier) -> Store<Mastodon.Entity.Status> {
        return Store<Mastodon.Entity.Status>(
            storage: SQLiteStorageEngine.default(appendingPath: storeFilenameFromBasename("notification_relevant_status_store", kind: feedKind, forUser: userIdentifier)), cacheIdentifier: \.id)
    }
}

extension Store where Item == LastReadMarkers {
    static func lastReadMarkersStore() -> Store<LastReadMarkers> {
        return Store<LastReadMarkers>(
            storage: SQLiteStorageEngine.default(appendingPath: "last_read_markers_store"), cacheIdentifier: \.id)
    }
}

struct LastReadMarkers: Identifiable, Codable {
    enum MarkerPosition: Codable {
        case local(lastReadID: String)
        case fromServer(Mastodon.Entity.Marker.Position)
        
        var lastReadID: String {
            switch self {
            case .local(let lastReadID):
                return lastReadID
            case .fromServer(let position):
                return position.lastReadID
            }
        }
    }
    
    let userGUID: String
    let homeTimelineLastRead: MarkerPosition?
    let notificationsLastRead: MarkerPosition?
    let mentionsLastRead: MarkerPosition?
    
    var id: String {
        return userGUID
    }
    
    init(userGUID: String, home: MarkerPosition?, notifications: MarkerPosition?, mentions: MarkerPosition?) {
        self.userGUID = userGUID
        self.homeTimelineLastRead = home
        self.notificationsLastRead = notifications
        if let notifications, let mentions {
            if mentions.lastReadID > notifications.lastReadID {
                self.mentionsLastRead = mentions
            } else {
                self.mentionsLastRead = nil
            }
        } else {
            self.mentionsLastRead = mentions
        }
    }
    
    func lastRead(forKind kind: MastodonFeedKind) -> MarkerPosition? {
        switch kind {
        case .notificationsAll:
            return notificationsLastRead
        case .notificationsMentionsOnly:
            return mentionsLastRead ?? notificationsLastRead
        case .notificationsWithAccount:
            return nil
        }
    }
    
    func bySettingLastRead(_ newPosition: MarkerPosition, forKind kind: MastodonFeedKind) -> LastReadMarkers {
        if let previous = lastRead(forKind: kind) {
            guard previous.lastReadID < newPosition.lastReadID else { return self }
        }
        switch kind {
        case .notificationsAll:
            return LastReadMarkers(userGUID: userGUID, home: homeTimelineLastRead, notifications: newPosition, mentions: mentionsLastRead)
        case .notificationsMentionsOnly:
            return LastReadMarkers(userGUID: userGUID, home: homeTimelineLastRead, notifications: notificationsLastRead, mentions: newPosition)
        case .notificationsWithAccount:
            return self
        }
    }
}

