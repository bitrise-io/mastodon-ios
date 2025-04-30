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
                        HomeTimelinePostRowView(viewModel: MastodonPostViewModel(post: post))
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

fileprivate struct HomeTimelinePostRowView: View {
    
    @ObservedObject var viewModel: MastodonPostViewModel
    
    var body: some View {
        VStack {
            if let superheader = viewModel.superheader {
                componentView(superheader)
            }
            componentView(.authorHeader(viewModel.post.metaData.author))
            componentView(.content(viewModel.contentString))
            if let attachment = viewModel.attachmentComponent {
                componentView(attachment)
            }
            if let hashtags = viewModel.hashtagComponent {
                componentView(hashtags)
            }
            componentView(.actionBar)
        }
    }
    
    @ViewBuilder func componentView(_ component: PostViewComponent) -> some View {
        switch component {
        case let .superHeader(iconName, text, color):
            SuperheaderView(iconName: iconName, text: text, color: color)
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

struct SuperheaderView: View {
    let iconName: String?
    let text: String
    let color: Color
    
    var body: some View {
        HStack {
            Spacer()
            if let iconName = iconName {
                Image(systemName: iconName)
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(color)
                    .frame(height: actionSuperheaderHeight)
            } else {
                Spacer()
                    .frame(height: actionSuperheaderHeight)
            }
            textComponent(text, fontWeight: .bold)
                .font(.subheadline)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(color)
                .frame(height: actionSuperheaderHeight)
            Spacer()
                .frame(height: actionSuperheaderHeight)
        }
    }
    
    @ViewBuilder
    func textComponent(_ string: String, fontWeight: SwiftUICore.Font.Weight?)
    -> some View
    {
        Text(string)
            .fontWeight(fontWeight)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

let avatarSize: CGFloat = 50

fileprivate struct AuthorHeaderView: View {
    let author: MastodonAccount
    
    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.secondary)
                .frame(width: avatarSize, height: avatarSize)
            VStack(alignment: .leading) {
                textComponent("\(author.displayInfo.displayName)", fontWeight: .semibold)
                    .fixedSize()
                textComponent("@\(author.displayInfo.handle)", fontWeight: .light)
                    .fixedSize()
            }
            Spacer()
                .frame(maxWidth: .infinity)
        }
    }
}

fileprivate struct PostContentView: View {
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
    case superHeader(iconName: String?, text: String, color: Color)
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
    
    var superheader: PostViewComponent? {

        if post is MastodonBoostPost {
            // BOOSTED BY
            return .superHeader(iconName: "arrow.2.squarepath", text: "\(post.metaData.author.displayInfo.displayName) boosted", color: .secondary)
        } else if let basicPost = post as? MastodonBasicPost {
            // IS REPLY and/or IS DIRECT MESSAGE
            let isReply = basicPost.inReplyTo != nil
            let isPrivate = basicPost.metaData.privacyLevel == .mentionedOnly
            let color = isPrivate ? Asset.Colors.accent.swiftUIColor : .secondary
            switch (isReply, isPrivate) {
            case (true, false):
                return .superHeader(iconName: "arrow.turn.up.left", text: L10n.Common.Controls.Status.reply, color: color)
            case (true, true):
                return .superHeader(iconName: "arrow.turn.up.left", text: L10n.Common.Controls.Status.privateReply, color: color)
            case (false, false):
                return nil
            case (false, true):
                return .superHeader(iconName: "at", text: L10n.Common.Controls.Status.privateMention, color: color)
            }
        } else {
            return nil
        }
    }
    
    var contentString: String {
        if let boost = post as? MastodonBoostPost {
            return boost.boostedPost.content.plainText ?? "CONTENT"
        } else if let contentPost = post as? MastodonContentPost {
            return contentPost.content.plainText ?? "CONTENT"
        } else {
            return "no text content available"
        }
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
