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
                        let authorInfo = post.metaData.author.displayInfo
                        Text("Post from \(authorInfo.displayName) \(authorInfo.handle)")
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
}
