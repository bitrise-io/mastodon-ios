//
//  ActionButtons.swift
//  Design
//
//  Created by Sam on 2024-03-28.
//

import SwiftUI
import MastodonSDK
import MastodonAsset

fileprivate func compactNumber(_ int: Int) -> String {
    return int.formatted(.number.notation(.compactName))
}

@MainActor
class TimelineActionViewModel: ObservableObject {
    private var status: Mastodon.Entity.Status?
    @Published private(set) var reply: PostActionType
    @Published private(set) var boost: PostActionType
    @Published private(set) var favourite: PostActionType
    @Published private(set) var isUpdatingBoost: Bool = false
    @Published private(set) var isUpdatingFavourite: Bool = false
    
    init(_ feedItemIdentifier: MastodonFeedItemIdentifier) {
        if let status = MastodonFeedItemCacheManager.shared.cachedItem(feedItemIdentifier) as? Mastodon.Entity.Status {
            reply = .reply(count: status.repliesCount ?? 0)
            boost = .boost(count: status.reblogsCount, isSelected: status.reblogged ?? false)
            favourite = .favourite(count: status.favouritesCount, isSelected: status.favourited ?? false)
        } else {
            reply = .reply(count: 0)
            boost = .boost(count: 0, isSelected: false)
            favourite = .favourite(count: 0, isSelected: false)
        }
    }
    
    func addReply() {
        // TODO: implement
    }
    
    func toggleBoost() {
        isUpdatingBoost = true
        // TODO: implement
//        MastodonFeedItemCacheManager.shared.doReblog(status)
//        let updatedStatus = try await APIService.shared.reblog(
//            status: status,
//            authenticationBox: provider.authenticationBox
//        ).value
    }
    
    func toggleFavourite() {
        // TODO: implement
        isUpdatingFavourite = true
    }
}

extension TimelinePostCell {
    struct ActionButtons: View {
        @State private var viewModel: TimelineActionViewModel
        
        @MainActor
        init(_ identifier: MastodonFeedItemIdentifier) {
            viewModel = TimelineActionViewModel(identifier)
        }
        
        var body: some View {
            HStack(alignment: .center) {
                HStack(spacing: 24) {
                    PostActionButton(actionType:  viewModel.reply) {
                        viewModel.addReply()
                    }
                    PostActionButton(actionType: viewModel.boost) {
                        viewModel.toggleBoost()
                    }
                    PostActionButton(actionType: viewModel.favourite) {
                        viewModel.toggleFavourite()
                    }
                }
                Spacer()
                PostActionButton(actionType: .share, action: nil)
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(.secondary)
        }
    }
}

enum PostActionType {
    case reply(count: Int)
    case boost(count: Int, isSelected: Bool)
    case favourite(count: Int, isSelected: Bool)
    case share
}

struct PostActionButton: View {
    let actionType: PostActionType
    var action: (() -> Void)?
    
    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.subheadline)
                // Adjusted to correctly display the count based on actionType
                switch actionType {
                case let .reply(count),
                     let .boost(count, _),
                     .favourite(let count, _):
                    ZStack(alignment: .leading) {
                        Text("0000")
                            .fontWeight(.semibold)
                            .hidden()
                        if count > 0 {
                            Text(compactNumber(count))
                                .contentTransition(.numericText(value: Double(count)))
                        }
                    }
                    .font(.footnote)
                case .share:
                    EmptyView()
                }
            }
            .fontWeight(weight)
            .foregroundStyle(color)
        }
    }
    
    private var iconName: String {
        switch actionType {
        case .reply:
            return "bubble.left"
        case .boost:
            return "arrow.2.squarepath"
        case .favourite(_, let isSelected):
            return PostAction.favourite.systemIconName(filled: isSelected)
        case .share:
            return "square.and.arrow.up"
        }
    }
    
    private var weight: SwiftUICore.Font.Weight {
        switch actionType {
        case .reply:
            return .regular
        case .boost(_, let isSelected):
            return isSelected ? .semibold : .regular
        case .favourite(_, let isSelected):
            return isSelected ? .semibold : .regular
        case .share:
            return .regular
        }
    }
    
    private var color: Color {
        switch actionType {
        case .reply, .share:
            return .secondary
        case .boost(_, let isSelected):
            return isSelected ? Color(asset: Asset.Colors.accent) : .secondary
        case .favourite(_, let isSelected):
            return isSelected ? .orange : .secondary
        }
    }
}


//#Preview {
//    TimelinePostCell.ActionButtons()
//}
