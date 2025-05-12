// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import Foundation
import SwiftUI

private let _eight: CGFloat = 8

let spacingBetweenGutterAndContent: CGFloat = _eight
let standardPadding: CGFloat = _eight

struct AvatarSize {
    static var large: CGFloat = 44
    static var small: CGFloat = 32
}

struct CornerRadius {
    static var standard: CGFloat = _eight
    static var small: CGFloat = _eight / 2
}

struct ButtonPadding {
    static var vertical: CGFloat = 3
    static var horizontal = _eight
    static var capsuleHorizontal: CGFloat = _eight * 2
}

extension HorizontalAlignment {
    enum GutterAlign: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[.leading]
        }
    }
    
    static let gutterAlign = HorizontalAlignment(GutterAlign.self)
}
