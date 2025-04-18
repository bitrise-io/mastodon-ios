// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import Bodega
import MastodonCore

/// Cache user data in a local database.
///  MAKE SURE TO UPDATE removeUser() WHEN ADDING ADDITIONAL CACHES
public class BodegaPersistence {
    private static let adminNotificationPreferenceStore = ObjectStorage<AdminNotificationFilterSettings>(storage:  SQLiteStorageEngine(directory: .documents(appendingPath: "AdminNotificationPreferences"))!)
    private static let lastReadMarkerStore = ObjectStorage<LastReadMarkers>(storage: SQLiteStorageEngine(directory: .documents(appendingPath: "LastReadMarkers"))!)
    
    public static func removeUser(_ userID: UserIdentifier) async throws {
        let cacheKey = CacheKey(userID.globallyUniqueUserIdentifier)
        try await adminNotificationPreferenceStore.removeObject(forKey: cacheKey)
        try await lastReadMarkerStore.removeObject(forKey: cacheKey)
    }
    
    public struct Notifications {
        static func currentPreferences(for userID: UserIdentifier) async -> AdminNotificationFilterSettings? {
            return await adminNotificationPreferenceStore.object(forKey: CacheKey(userID.globallyUniqueUserIdentifier))
        }
        
        static func updatePreferences(_ preferences: AdminNotificationFilterSettings, for userID: UserIdentifier) async throws {
            try await adminNotificationPreferenceStore.store(preferences, forKey: CacheKey(userID.globallyUniqueUserIdentifier))
        }
    }
    
    public struct LastRead {
        static func lastReadMarkers(for userID: UserIdentifier) async -> LastReadMarkers? {
            return await lastReadMarkerStore.object(forKey: CacheKey(userID.globallyUniqueUserIdentifier))
        }
        
        static func saveLastReadMarkers(_ markers: LastReadMarkers, for userID: UserIdentifier) async throws {
            try await lastReadMarkerStore.store(markers, forKey: CacheKey(userID.globallyUniqueUserIdentifier))
        }
    }
}
