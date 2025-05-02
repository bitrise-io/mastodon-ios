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
                        case .post(let post):
                            let usableWidth = geo.size.width - geo.safeAreaInsets.leading - geo.safeAreaInsets.trailing
                            HomeTimelinePostRowView(viewModel: MastodonPostViewModel(post: post), contentWidth: usableWidth - (spacingBetweenGutterAndContent * 3) - avatarSize)
                                .padding(spacingBetweenGutterAndContent)
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                .frame(width: usableWidth)
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
        VStack(alignment: .gutterAlign) {
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
            componentView(.actionBar)
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
        case .actionBar:
            ActionBar()
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
    var body: some View {
        Text("ACTION BAR")
    }
}

fileprivate enum PostViewComponent {
    case authorHeader(MastodonAccount)
    case content(String)
    case attachment(GenericMastodonPost.PostAttachment)
    case hashtags([String])
    case actionBar
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
