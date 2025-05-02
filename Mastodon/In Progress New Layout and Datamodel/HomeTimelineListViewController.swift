// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import SwiftUI
import MastodonAsset
import MastodonCore
import MastodonLocalization
import MastodonSDK
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
    private var tailItemIds = [String]()
    
    func doInitialLoad() async throws {
        guard feedLoader == nil else { return }
        guard let currentUser = AuthenticationServiceProvider.shared.currentActiveUser.value else { assertionFailure("no active authenticated user, cannot create feed loader"); return }
        feedLoader = TimelineFeedLoader(currentUser: currentUser)
        feedLoaderResultsSubscription = feedLoader?.$records
            .sink{ [weak self] results in
                self?.tailItemIds = results.allRecords.suffix(5).map { $0.id }
                self?.timelineItems = results.allRecords + (results.canLoadOlder ? [.loadingIndicator] : [])
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
    
    func didAppear(_ itemID: String) {
        guard feedLoader?.records.canLoadOlder == true else {
#if DEBUG
            print("nothing left to load")
#endif
            return
        }
        if tailItemIds.contains(itemID) {
            tailItemIds = []
            requestLoad(.older)
        }
    }
}

struct HomeTimelineListView: View {
    @ObservedObject private var viewModel: HomeTimelineListViewModel
    
    @ScaledMetric private var avatarSize = AvatarSize.large
    
    fileprivate init(viewModel: HomeTimelineListViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                List {
                    ForEach(viewModel.timelineItems, id: \.self) { item in // without explicit id, scrollTo(:) does not work
                        switch item {
                        case let .missingPosts(newerThan, olderThan, timeGapDescription):
                            Text(timeGapDescription)
                        case .loadingIndicator:
                            HStack {
                                Spacer()
                                ProgressView()
                                    .progressViewStyle(.circular)
                                Spacer()
                            }
                        case .post(let post):
                            let usableWidth = geo.size.width - geo.safeAreaInsets.leading - geo.safeAreaInsets.trailing
                            HomeTimelinePostRowView(viewModel: MastodonPostViewModel(post: post), contentWidth: usableWidth - (spacingBetweenGutterAndContent * 3) - avatarSize)
                                .padding(spacingBetweenGutterAndContent)
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                .frame(width: usableWidth)
                                .onAppear() {
                                    viewModel.didAppear(item.id)
                                }
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
        }
        .onAppear() {
            Task {
                try await viewModel.doInitialLoad()
            }
        }
    }
}

fileprivate struct HomeTimelinePostRowView: View {
    
    @ObservedObject var viewModel: MastodonPostViewModel
    let contentWidth: CGFloat
    
    var body: some View {
        VStack(alignment: .gutterAlign, spacing: spacingBetweenGutterAndContent) {
            viewModel.socialContextHeader
            componentView(.authorHeader(viewModel.post.metaData.author))
            viewModel.textContentView
                .frame(width: contentWidth, alignment: .leading)
            if let attachment = viewModel.attachmentComponent {
                componentView(attachment)
            }
//            if let hashtags = viewModel.hashtagComponent {
//                componentView(hashtags)
//            }
            viewModel.actionBar
                .frame(width: contentWidth, alignment: .leading)
        }
    }
    
    @ViewBuilder func componentView(_ component: PostViewComponent) -> some View {
        switch component {
        case .authorHeader(let author):
            AuthorHeaderView(author: author)
        case .content(let string):
            PostContentView(text: string)
        case .attachment(let attachment):
            switch attachment {
            case .linkPreviewCard(let card):
                LinkPreviewView(linkPreview: card)
            case .media(let media):
                MediaAttachmentView(media: media)
            case .poll(let poll):
                PollView(poll: poll)
            }
        case .hashtags(let tags):
            HashtagRowView(hashtags: tags)
        }
    }
}

fileprivate struct PostContentView: View {
    //    @ObservedObject var contentWarningViewModel
    let text: String
    
    var body: some View {
        Text(text)
    }
}

fileprivate struct MediaAttachmentView: View {
    let media: [Mastodon.Entity.Attachment]
    
    var body: some View {
        let description = {
            switch media.first?.type {
            case nil:
                return "no attachment!"
            case .image:
                return "\(media.count) images"
            case .gifv:
                return "a GIFV"
            case .video:
                return "a video"
            case .audio:
                return "an audio"
            default:
                return "unknown attachment"
            }
        }()
        Text(description)
            .lineLimit(nil)
    }
}

fileprivate struct LinkPreviewView: View {
    let linkPreview: Mastodon.Entity.Card
    
    var body: some View {
        Text("a link preview")
    }
}

fileprivate struct PollView: View {
    let poll: Mastodon.Entity.Poll
    
    var body: some View {
        Text("a poll")
    }
}

fileprivate struct HashtagRowView: View {
    let hashtags: [String]
    
    var body: some View {
        Text("#\(hashtags.first) and \(hashtags.count - 1) others")
    }
}

fileprivate struct ActionBar: View {
    
    @ObservedObject var replyModel = StatefulCountedActionViewModel(.reply)
    @ObservedObject var boostModel = StatefulCountedActionViewModel(.boost)
    @ObservedObject var favouriteModel = StatefulCountedActionViewModel(.favourite)
    @ObservedObject var bookmarkModel = StatefulCountedActionViewModel(.bookmark)
    
    init(reply: StatefulCountedActionViewModel, boost: StatefulCountedActionViewModel, favourite: StatefulCountedActionViewModel, bookmark: StatefulCountedActionViewModel) {
        replyModel = reply
        boostModel = boost
        favouriteModel = favourite
        bookmarkModel = bookmark
    }
    
    var body: some View {
        HStack() {
            StatefulCountedActionButton(viewModel: replyModel)
            Spacer()
            StatefulCountedActionButton(viewModel: boostModel)
            Spacer()
            StatefulCountedActionButton(viewModel: favouriteModel)
            Spacer()
            StatefulCountedActionButton(viewModel: bookmarkModel)
            Spacer()
            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

fileprivate enum PostViewComponent {
    case authorHeader(MastodonAccount)
    case content(String)
    case attachment(GenericMastodonPost.PostAttachment)
    case hashtags([String])
}

@MainActor
class MastodonPostViewModel: ObservableObject {
    let post: GenericMastodonPost
    
    private let replyModel = StatefulCountedActionViewModel(.reply)
    private let boostModel = StatefulCountedActionViewModel(.boost)
    private let favouriteModel = StatefulCountedActionViewModel(.favourite)
    private let bookmarkModel = StatefulCountedActionViewModel(.bookmark)
    
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
            return
        }
        
        let myActions = actionablePost.content.myActions
        let metrics = actionablePost.content.metrics
        replyModel.update(count: metrics.replyCount)
        boostModel.update(count: metrics.boostCount, isSelected: AsyncBool.fromBool(myActions.boosted))
        favouriteModel.update(count: metrics.favoriteCount, isSelected: AsyncBool.fromBool(myActions.favorited))
        bookmarkModel.update(isSelected: AsyncBool.fromBool(myActions.bookmarked))
    }
}

fileprivate extension MastodonPostViewModel {
    
    var socialContextHeader: SocialContextHeader? {

        if post is MastodonBoostPost {
            // BOOSTED BY
            return .boosted(by: post.metaData.author.displayInfo.displayName, emojis: post.metaData.author.displayInfo.emojis)
        } else if let basicPost = post as? MastodonBasicPost {
            // REPLIED and/or PRIVATE MENTION
            let isReply = basicPost.inReplyTo != nil
            let isPrivate = basicPost.metaData.privacyLevel == .mentionedOnly
            if isReply {
                return .reply(to: basicPost.inReplyTo?.accountID ?? "??", isPrivate: isPrivate, isNotification: false, emojis: [])
            } else if isPrivate {
                return .mention(isPrivate: true)
            }
        }
        return nil
    }
    
    var textContentView: TextViewWithCustomEmoji {
        let text: String
        let emojis: TextViewWithCustomEmoji.Emojis
        if let boost = post as? MastodonBoostPost {
            text = boost.boostedPost.content.htmlWithEntities?.html ?? boost.boostedPost.content.plainText ?? ""
            emojis = boost.boostedPost.content.htmlWithEntities?.emojis ?? TextViewWithCustomEmoji.Emojis()
        } else if let contentPost = post as? MastodonContentPost {
            text = contentPost.content.htmlWithEntities?.html ?? contentPost.content.plainText ?? ""
            emojis = contentPost.content.htmlWithEntities?.emojis ?? TextViewWithCustomEmoji.Emojis()
        } else {
            text = ""
            emojis = TextViewWithCustomEmoji.Emojis()
        }
        return .timelinePost(html: text, emojis: emojis)
    }
    
    var attachmentComponent: PostViewComponent? {
        if let boost = post as? MastodonBoostPost, let basicPost = boost.boostedPost as? MastodonBasicPost, let attachment = basicPost.attachment {
            return .attachment(attachment)
        } else if let basicPost = post as? MastodonBasicPost, let attachment = basicPost.attachment {
            return .attachment(attachment)
        }
        return nil
    }
    
    var hashtagComponent: PostViewComponent? {
        return .hashtags(["needs_implementation"])
    }
    
    var actionBar: ActionBar {
        return ActionBar(reply: replyModel, boost: boostModel, favourite: favouriteModel, bookmark: bookmarkModel)
    }
}
