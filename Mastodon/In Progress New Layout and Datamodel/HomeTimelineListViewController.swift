// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import SwiftUI
import MastodonCore
import MastodonLocalization
import Combine

class HomeTimelineListViewController: UIHostingController<HomeTimelineListView>
{
    init() {
        let root = HomeTimelineListView(viewModel: HomeTimelineListViewModel())
        super.init(rootView: root)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError(
            "init(coder:) not implemented for HomeTimelineListViewController")
    }
}

@MainActor
private class HomeTimelineListViewModel: ObservableObject {
    @Published var timelineItems = [TimelineItem]()
    private var feedLoader: TimelineFeedLoader?
    private var feedLoaderResultsSubscription: AnyCancellable?
    private var feedLoaderErrorSubscription: AnyCancellable?
    
    func doInitialLoad() async throws {
        guard feedLoader == nil else { return }
        guard let currentUser = AuthenticationServiceProvider.shared.currentActiveUser.value else { assertionFailure("no active authenticated user, cannot create feed loader"); return }
        feedLoader = TimelineFeedLoader(currentUser: currentUser)
        feedLoaderResultsSubscription = feedLoader?.$records
            .sink{ [weak self] results in
                self?.timelineItems = results.allRecords
            }
        // TODO: add feedLoaderErrorSubscription
        feedLoader?.doFirstLoad()
    }
    
    func requestLoad(_ loadRequest: MastodonFeedLoaderRequest) {
        guard let feedLoader else { assertionFailure(); return }
        feedLoader.requestLoad(loadRequest)
    }
    
    func refreshFeedFromTop() async {
        guard let feedLoader else { assertionFailure(); return }
        if feedLoader.permissionToLoadImmediately {
            await feedLoader.loadImmediately(.newer)
        }
    }
}

struct HomeTimelineListView: View {
    @ObservedObject private var viewModel: HomeTimelineListViewModel
    
    fileprivate init(viewModel: HomeTimelineListViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(viewModel.timelineItems, id: \.self) { item in // without explicit id, scrollTo(:) does not work
                    switch item {
                    case let .missingPosts(newerThan, olderThan, timeGapDescription):
                        Text(timeGapDescription)
                    case .post(let post):
                        postRowView(post)
                    }
                }
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.refreshFeedFromTop()
            }
            .accessibilityAction(named: L10n.Common.Controls.Actions.seeMore) {
                viewModel.requestLoad(.newer)
            }
        }
        .onAppear() {
            Task {
                try await viewModel.doInitialLoad()
            }
        }
    }
    
    @ViewBuilder func postRowView(_ post: GenericMastodonPost) -> some View {
        let authorInfo = post.metaData.author.displayInfo
        Text("Post from \(authorInfo.displayName) \(authorInfo.handle)")
    }
}

@MainActor
class MastodonPostViewModel: ObservableObject {
    let post: GenericMastodonPost

    
    @Published var favorited: AsyncBool = .unknown
    @Published var boosted: AsyncBool = .unknown
    @Published var muted: AsyncBool = .unknown
    @Published var bookmarked: AsyncBool = .unknown
    @Published var pinned: AsyncBool = .unknown
    
    init(post: GenericMastodonPost) {
        self.post = post
        let actionablePost: MastodonContentPost?
        if let contentPost = post as? MastodonContentPost {
            actionablePost = contentPost
        } else if let boost = post as? MastodonBoostPost {
            actionablePost = boost.boostedPost
        } else {
            actionablePost = nil
        }
        
        guard let actionablePost else {
            assertionFailure("unexpected post type")
            favorited = .unknown
            boosted = .unknown
            muted = .unknown
            bookmarked = .unknown
            pinned = .unknown
            return
        }
        
        let myActions = actionablePost.content.myActions
        favorited = AsyncBool.fromBool(myActions.favorited)
        boosted = AsyncBool.fromBool(myActions.boosted)
        muted = AsyncBool.fromBool(myActions.muted)
        bookmarked = AsyncBool.fromBool(myActions.bookmarked)
        pinned = AsyncBool.fromBool(myActions.pinned)
    }
}

enum AsyncBool {
    case unknown
    case fetching
    case isTrue
    case settingToTrue
    case isFalse
    case settingToFalse
    
    static func fromBool(_ value: Bool?) -> AsyncBool {
        guard let value else { return .unknown }
        if value {
            return .isTrue
        } else {
            return .isFalse
        }
    }
}
