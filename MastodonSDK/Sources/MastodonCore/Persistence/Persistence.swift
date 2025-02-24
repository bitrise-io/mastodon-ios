//
//  Persistence.swift
//  Persistence
//
//  Created by Cirno MainasuK on 2021-8-18.
//  Copyright © 2021 Twidere. All rights reserved.
//

import Foundation

public enum Persistence {
    case searchHistory(UserIdentifier)
    case homeTimeline(UserIdentifier)
    case notificationsMentions(UserIdentifier)
    case notificationsAll(UserIdentifier)
    case accounts(UserIdentifier)

    private var filename: String {
        switch self {
            case .searchHistory(let userIdentifier):
                return "search_history_\(userIdentifier.globallyUniqueUserIdentifier))"
            case let .homeTimeline(userIdentifier):
                return "home_timeline_\(userIdentifier.globallyUniqueUserIdentifier)"
            case let .notificationsMentions(userIdentifier):
                return "notifications_mentions_\(userIdentifier.globallyUniqueUserIdentifier)"
            case let .notificationsAll(userIdentifier):
                return "notifications_all_\(userIdentifier.globallyUniqueUserIdentifier)"
            case .accounts(let userIdentifier):
                return "account_\(userIdentifier.globallyUniqueUserIdentifier)"
        }
    }

    public func filepath(baseURL: URL) -> URL {
        baseURL
            .appending(path: filename)
            .appendingPathExtension("json")
    }
}


extension Persistence {
    public enum MastodonUser { }
    public enum Status { }
    public enum SearchHistory { }
    public enum Notification { }
}

extension Persistence {
    public class PersistCache<T> {
        var dictionary: [String : T] = [:]
        
        public init(dictionary: [String : T] = [:]) {
            self.dictionary = dictionary
        }
    }
}

