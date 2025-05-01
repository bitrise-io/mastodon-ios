// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import Foundation
import SwiftUI

let spacingBetweenGutterAndContent: CGFloat = 8

struct AvatarSize {
    static var large: CGFloat = 44
    static var small: CGFloat = 32
}

extension HorizontalAlignment {
    enum GutterAlign: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[.leading]
        }
    }
    
    static let gutterAlign = HorizontalAlignment(GutterAlign.self)
}
