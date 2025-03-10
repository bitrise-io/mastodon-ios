// Copyright © 2023 Mastodon gGmbH. All rights reserved.

import UIKit
import CoreDataStack
import MastodonAsset
import MastodonSDK

extension MastodonVisibility {
    
    public var title: String {
        switch self {
        case .public: return Mastodon.Entity.Status.Visibility.public.title
        case .unlisted: return Mastodon.Entity.Status.Visibility.unlisted.title
        case .private: return Mastodon.Entity.Status.Visibility.private.title
        case .direct: return Mastodon.Entity.Status.Visibility.direct.title
        case ._other(let string): return string
        }
    }

    public var image: UIImage {
        let asset: UIImage
        switch self {
        case .public: asset = Mastodon.Entity.Status.Visibility.public.image
        case .unlisted: asset = Mastodon.Entity.Status.Visibility.unlisted.image
        case .private: asset = Mastodon.Entity.Status.Visibility.private.image
        case .direct: asset = Mastodon.Entity.Status.Visibility.direct.image
        case ._other: asset = Mastodon.Entity.Status.Visibility._other("").image
        }
        return asset.withRenderingMode(.alwaysTemplate)
    }
}
