// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import Foundation
import MastodonCore
import MastodonSDK

struct MastodonAccount: Identifiable, Codable {
    let id: Mastodon.Entity.Account.ID
    let metadata: MetaData
    let displayInfo: DisplayInfo
}

struct ImageUrl: Codable {
    private let animatedUrl: URL?
    private let staticUrl: URL

    init?(
        potentiallyAnimated: String?, definitelyStatic: String?, fallback: URL?
    ) {
        let animatedUrl: URL? = {
            guard let potentiallyAnimated else { return nil }
            return URL(string: potentiallyAnimated)
        }()
        let staticUrl: URL? = {
            guard let definitelyStatic else { return fallback }
            return URL(string: definitelyStatic) ?? fallback
        }()

        guard let staticUrl else { return nil }

        if animatedUrl == staticUrl {
            self.staticUrl = staticUrl
            self.animatedUrl = nil
        } else {
            self.animatedUrl = animatedUrl
            self.staticUrl = staticUrl
        }
    }

    var preferredUrl: URL {
        if UserDefaults.standard.preferredStaticAvatar {
            return staticUrl
        } else {
            return animatedUrl ?? staticUrl
        }
    }
}

extension MastodonAccount {
    struct MetaData: Codable {
        let profileUrl: URL?
        let createdAt: Date
        let manuallyApprovesNewFollows: Bool
    }
}

extension MastodonAccount {
    struct DisplayInfo: Codable {
        let handle: String
        let displayName: String
        let emojis: [Mastodon.Entity.Emoji]
        private let avatarImage: ImageUrl
        private let headerImage: ImageUrl?

        var avatarUrl: URL {
            return avatarImage.preferredUrl
        }

        var headerUrl: URL? {
            return headerImage?.preferredUrl
        }
    }
}

protocol FromAccountEntityDerivable {
    static func fromEntity(
        _ entity: Mastodon.Entity.Account
    ) -> Self
}

extension MastodonAccount: FromAccountEntityDerivable {
    static func fromEntity(
        _ entity: Mastodon.Entity.Account
    ) -> Self {
        return MastodonAccount(
            id: entity.id,
            metadata: MetaData.fromEntity(entity),
            displayInfo: DisplayInfo.fromEntity(
                entity))
    }
}

extension MastodonAccount.MetaData: FromAccountEntityDerivable {
    static func fromEntity(_ entity: Mastodon.Entity.Account) -> MastodonAccount.MetaData {
        return MastodonAccount.MetaData(profileUrl: URL(string: entity.url), createdAt: entity.createdAt, manuallyApprovesNewFollows: entity.locked)
    }
}

extension MastodonAccount.DisplayInfo: FromAccountEntityDerivable {
    static func fromEntity(
        _ entity: Mastodon.Entity.Account
    ) -> Self {
        // TODO: GET THE ACTUAL USER DOMAIN! or just get the image and keep it somewhere
        let currentUserDomain = "mastodon.social"
        let avatarImage = ImageUrl(
            potentiallyAnimated: entity.avatar,
            definitelyStatic: entity.avatarStatic,
            fallback: fallbackAvatarURL(
                fromCurrentUserDomain: currentUserDomain))!
        let headerImage = ImageUrl(
            potentiallyAnimated: entity.avatar,
            definitelyStatic: entity.avatarStatic,
            fallback: fallbackAvatarURL(
                fromCurrentUserDomain: currentUserDomain))
        return Self(
            handle: entity.acct, displayName: entity.displayNameWithFallback,
            emojis: entity.emojis, avatarImage: avatarImage,
            headerImage: headerImage)
    }
}

func fallbackAvatarURL(fromCurrentUserDomain domain: String) -> URL {
    let missingImageName = "missing.png"
    return URL(
        string: "https://\(domain)/avatars/original/\(missingImageName)")!
}
