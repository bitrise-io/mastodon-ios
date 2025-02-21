// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import MastodonSDK
import Boutique

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

extension Store where Item == Mastodon.Entity.Notification {
    static func ungroupedNotificationStore(forKind feedKind: MastodonFeedKind, forUserAcct userAcct: String) -> Store<Mastodon.Entity.Notification> {
        let tag = feedKind.storageTag
        assert(tag != nil, "ATTEMPTING TO CACHE A FEED TYPE THAT SHOULD NOT BE CACHED")
        return Store<Mastodon.Entity.Notification>(
            storage: SQLiteStorageEngine.default(appendingPath: "ungrouped_notification_store_" + (tag ?? "UNEXPECTED") + userAcct), cacheIdentifier: \.id)
    }
}

extension Store where Item == Mastodon.Entity.NotificationGroup {
    static func notificationGroupStore(forKind feedKind: MastodonFeedKind, forUserAcct userAcct: String) -> Store<Mastodon.Entity.NotificationGroup> {
        let tag = feedKind.storageTag
        assert(tag != nil, "ATTEMPTING TO CACHE A FEED TYPE THAT SHOULD NOT BE CACHED")
        return Store<Mastodon.Entity.NotificationGroup>(
            storage: SQLiteStorageEngine.default(appendingPath: "notification_group_store_" + (tag ?? "UNEXPECTED") + userAcct), cacheIdentifier: \.id)
    }
}

extension Store where Item == Mastodon.Entity.Account {
    static func notificationRelevantFullAccountStore(forKind feedKind: MastodonFeedKind, forUserAcct userAcct: String) -> Store<Mastodon.Entity.Account> {
        let tag = feedKind.storageTag
        assert(tag != nil, "ATTEMPTING TO CACHE A FEED TYPE THAT SHOULD NOT BE CACHED")
        return Store<Mastodon.Entity.Account>(
            storage: SQLiteStorageEngine.default(appendingPath: "notification_relevant_full_account_store_" + (tag ?? "UNEXPECTED") + userAcct), cacheIdentifier: \.id)
    }
}

extension Store where Item == Mastodon.Entity.PartialAccountWithAvatar {
    static func notificationRelevantPartialAccountStore(forKind feedKind: MastodonFeedKind, forUserAcct userAcct: String) -> Store<Mastodon.Entity.PartialAccountWithAvatar> {
        let tag = feedKind.storageTag
        assert(tag != nil, "ATTEMPTING TO CACHE A FEED TYPE THAT SHOULD NOT BE CACHED")
        return Store<Mastodon.Entity.PartialAccountWithAvatar>(
            storage: SQLiteStorageEngine.default(appendingPath: "notification_relevant_partial_account_store_" + (tag ?? "UNEXPECTED") + userAcct), cacheIdentifier: \.id)
    }
}

extension Store where Item == Mastodon.Entity.Status {
    static func notificationRelevantStatusStore(forKind feedKind: MastodonFeedKind, forUserAcct userAcct: String) -> Store<Mastodon.Entity.Status> {
        let tag = feedKind.storageTag
        assert(tag != nil, "ATTEMPTING TO CACHE A FEED TYPE THAT SHOULD NOT BE CACHED")
        return Store<Mastodon.Entity.Status>(
            storage: SQLiteStorageEngine.default(appendingPath: "notification_relevant_status_store_" + (tag ?? "UNEXPECTED") + userAcct), cacheIdentifier: \.id)
    }
}

struct LastReadMarkerCache {
    @StoredValue(key: Mastodon.Entity.Marker.storageKey) private var userToMarkerMap = [ String : Mastodon.Entity.Marker ]()
    
    func getCachedMarker(forUserAcct userAcct: String) -> Mastodon.Entity.Marker? {
        return userToMarkerMap[userAcct]
    }
    
    @MainActor
    func setCachedMarker(_ marker: Mastodon.Entity.Marker, forUserAcct userAcct: String) {
        var newMap = userToMarkerMap
        newMap[userAcct] = marker
        $userToMarkerMap.set(newMap)
    }
    
    @MainActor
    func removeMarker(forUserAcct userAcct: String) {
        var newMap = userToMarkerMap
        newMap.removeValue(forKey: userAcct)
        $userToMarkerMap.set(newMap)
    }
}
