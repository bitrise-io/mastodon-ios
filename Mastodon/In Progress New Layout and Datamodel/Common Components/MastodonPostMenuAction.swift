// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import SwiftUI
import MastodonLocalization

@MainActor
protocol MastodonPostMenuActionDoer {
    func doAction(_ action: MastodonPostMenuAction, forPost post: MastodonContentPost)
}

enum MastodonPostMenuAction {
    enum SubmenuType: String {
        case edit
        case translate
        case postActions
        case relationshipActions
        case defensiveActions
        case delete
    }
    
    struct Submenu: Identifiable {
        let id: MastodonPostMenuAction.SubmenuType
        let items: [MastodonPostMenuAction]
        
        init?(_ id: MastodonPostMenuAction.SubmenuType, items: [MastodonPostMenuAction]?) {
            guard let items, !items.isEmpty else { return nil }
            self.id = id
            self.items = items
        }
    }
    
    // EDIT
    case editPost
    
    // TRANSLATE
    case translatePost
    case showOriginal
    
    // POST ACTIONS
    case sharePost
    case openPostInBrowser
    case copyLinkToPost

    // RELATIONSHIP ACTIONS
    case follow
    case unfollow
    case mute
    case unmute
    
    // DEFENSIVE ACTIONS
    case blockUser
    case unblockUser
    case reportUser
    
    // DELETE
    case deletePost
    
    var iconSystemName: String {
        switch self {
        case .translatePost, .showOriginal:
            "character.book.closed"
        case .reportUser:
            "flag"
        case .follow:
            "person.fill.badge.plus"
        case .unfollow:
            "person.fill.badge.minus"
        case .mute:
            "speaker.slash"
        case .unmute:
            "speaker.wave.2"
        case .blockUser:
            "hand.raised.slash"
        case .unblockUser:
            "hand.raised"
        case .sharePost:
            "square.and.arrow.up"
        case .deletePost:
            "minus.circle"
        case .editPost:
            "pencil"
        case .copyLinkToPost:
            "doc.on.doc"
        case .openPostInBrowser:
            "safari"
        }
    }
    
    func labelText(_ text: String? = "") -> String {
        switch self {
        case .translatePost:
            let language = Locale.current.localizedString(forIdentifier: text!) ?? L10n.Common.Controls.Actions.TranslatePost.unknownLanguage
            return L10n.Common.Controls.Actions.TranslatePost.title(language)
        case .showOriginal:
            return L10n.Common.Controls.Status.Translation.showOriginal
        case .reportUser:
            return L10n.Common.Controls.Actions.reportUser(text!)
        case .follow:
            return L10n.Common.Controls.Actions.follow(text!)
        case .unfollow:
            return L10n.Common.Controls.Actions.unfollow(text!)
        case .mute:
            return L10n.Common.Controls.Friendship.muteUser(text!)
        case .unmute:
            return L10n.Common.Controls.Friendship.unmuteUser(text!)
        case .blockUser:
            return L10n.Common.Controls.Friendship.blockUser(text!)
        case .unblockUser:
            return L10n.Common.Controls.Friendship.unblockUser(text!)
        case .sharePost:
            return L10n.Common.Controls.Actions.sharePost
        case .deletePost:
            return L10n.Common.Controls.Actions.delete
        case .editPost:
            return L10n.Common.Controls.Actions.editPost
        case .copyLinkToPost:
            return L10n.Common.Controls.Status.Actions.copyLink
        case .openPostInBrowser:
            return L10n.Common.Controls.Actions.openInBrowser
        }
    }
    
    var isDestructive: Bool {
        switch self {
        case .blockUser, .reportUser, .deletePost:
            return true
        default:
            return false
        }
    }
    
    static func menuItems(forPostBy relationship: MastodonAccount.Relationship, isMyLanguage: Bool) -> [MastodonPostMenuAction.Submenu] {
        
        let editAction: [MastodonPostMenuAction]? =  {
            switch relationship {
            case .isMe:
                [ MastodonPostMenuAction.editPost ]
            case .isNotMe:
                nil
            }
        }()
        
        let translateAction = isMyLanguage ? nil : [MastodonPostMenuAction.translatePost]
        
        let postActions = [MastodonPostMenuAction.sharePost, .copyLinkToPost, .openPostInBrowser]
        
        let relationshipActions: [MastodonPostMenuAction]?
        let defensiveActions: [MastodonPostMenuAction]?
        
        switch relationship {
        case .isMe:
            relationshipActions = nil
            defensiveActions = nil
        case .isNotMe(let info):
            if let info {
                relationshipActions = [
                    (info.iFollowThem || info.iHaveRequestedToFollowThem) ? .unfollow : .follow,
                    info.iAmMutingThem ? .unmute : .mute
                ]
                defensiveActions = [
                    info.iAmBlockingThem ? .unblockUser : .blockUser,
                    .reportUser
                ]
            } else {
                relationshipActions = nil
                defensiveActions = nil
            }
        }
        
        let deleteAction: [MastodonPostMenuAction]? = {
            switch relationship {
            case .isMe:
                [.deletePost]
            case .isNotMe:
                nil
            }
        }()
        
        let submenus: [MastodonPostMenuAction.Submenu] = [
            .init(.edit, items: editAction),
            .init(.translate, items: translateAction),
            .init(.postActions, items: postActions),
            .init(.relationshipActions, items: relationshipActions),
            .init(.defensiveActions, items: defensiveActions),
            .init(.delete, items: deleteAction)
        ].compactMap { $0 }
        return submenus
    }
}
