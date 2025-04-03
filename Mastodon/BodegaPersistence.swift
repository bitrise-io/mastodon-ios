// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import Bodega
import MastodonCore

/// Cache user data in a local database.
///  MAKE SURE TO UPDATE removeUser() WHEN ADDING ADDITIONAL CACHES
public class BodegaPersistence {
    private static let adminNotificationPreferenceStore = ObjectStorage<AdminNotificationFilterSettings>(storage:  SQLiteStorageEngine(directory: .documents(appendingPath: "AdminNotificationPreferences"))!)
    
    public static func removeUser(_ userID: UserIdentifier) async throws {
        try await adminNotificationPreferenceStore.removeObject(forKey: CacheKey(userID.globallyUniqueUserIdentifier))
    }
    
    public struct Notifications {
        static func currentPreferences(for userID: UserIdentifier) async -> AdminNotificationFilterSettings? {
            return await adminNotificationPreferenceStore.object(forKey: CacheKey(userID.globallyUniqueUserIdentifier))
        }
        
        static func updatePreferences(_ preferences: AdminNotificationFilterSettings, for userID: UserIdentifier) async throws {
            try await adminNotificationPreferenceStore.store(preferences, forKey: CacheKey(userID.globallyUniqueUserIdentifier))
        }
    }
}
