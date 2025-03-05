// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import MastodonSDK
import MastodonCore
import Foundation

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

