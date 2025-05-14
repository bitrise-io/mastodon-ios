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
        let viewModel = HomeTimelineListViewModel()
        let root = HomeTimelineListView(viewModel: viewModel)
        super.init(rootView: root)
        viewModel.parentVcPresentScene = { (scene, transition) in
            self.sceneCoordinator?.present(scene: scene, transition: transition)
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError(
            "init(coder:) not implemented for HomeTimelineListViewController")
    }
}

extension MastodonPostMenuAction {
    enum AlertType {
        case noAlert
        case confirmBoostOfPost(didConfirm: ()->())
        case confirmDeleteOfPost(didConfirm: ()->())
        case confirmUnfollow(username: String, didConfirm: ()->())
        case confirmMute(username: String, didConfirm: ()->())
        case confirmUnmute(username: String, didConfirm: ()->())
        case confirmBlock(username: String, didConfirm: ()->())
        case confirmUnblock(username: String, didConfirm: ()->())
        
        var title: String {
            switch self {
            case .noAlert:
                ""
                
            case .confirmBoostOfPost:
                L10n.Common.Alerts.BoostAPost.titleBoost
                
            case .confirmDeleteOfPost:
                L10n.Common.Alerts.DeletePost.title
                
            case .confirmUnfollow(let username, _):
                L10n.Common.Alerts.UnfollowUser.title("\(username)")
                
            case .confirmMute:
                L10n.Scene.Profile.RelationshipActionAlert.ConfirmMuteUser.title
            case .confirmUnmute:
                L10n.Scene.Profile.RelationshipActionAlert.ConfirmUnmuteUser.title
                
            case .confirmBlock:
                L10n.Scene.Profile.RelationshipActionAlert.ConfirmBlockUser.title
            case .confirmUnblock:
                L10n.Scene.Profile.RelationshipActionAlert.ConfirmUnblockUser.title
            }
        }
        
        var messageText: String? {
            switch self {
            case .noAlert, .confirmUnfollow, .confirmBoostOfPost:
                nil
                
            case .confirmMute(let username, _):
                L10n.Scene.Profile.RelationshipActionAlert.ConfirmMuteUser.message(username)
            case .confirmUnmute(let username, _):
                L10n.Scene.Profile.RelationshipActionAlert.ConfirmUnmuteUser.message(username)
                
            case .confirmBlock(let username, _):
                L10n.Scene.Profile.RelationshipActionAlert.ConfirmBlockUser.message(username)
            case .confirmUnblock(let username, _):
                L10n.Scene.Profile.RelationshipActionAlert.ConfirmUnblockUser.message(username)
                
            case .confirmDeleteOfPost:
                L10n.Common.Alerts.DeletePost.message
            }
        }
        
        var shouldBePresented: Bool {
            switch self {
            case .noAlert:
                return false
            default:
                return true
            }
        }
    }
}

enum MastodonTimelineOverlayView {
    case images(focusedImage: Mastodon.Entity.Attachment.ID, ImageGalleryViewModel)
    case altText(String)
}

@MainActor
private class HomeTimelineListViewModel: ObservableObject {
    public var parentVcPresentScene: ((SceneCoordinator.Scene, SceneCoordinator.Transition) -> ())?
    private var authenticatedUser: MastodonAuthenticationBox?
    private var instanceConfiguration: MastodonAuthentication.InstanceConfiguration?
    
    var activeAlert: MastodonPostMenuAction.AlertType = .noAlert {
        didSet {
            if !isPresentingAlert && activeAlert.shouldBePresented {
                isPresentingAlert = true
            }
        }
    }
    var activeOverlay: MastodonTimelineOverlayView? = nil {
        didSet {
            if !isShowingOverlay && activeOverlay != nil {
                isShowingOverlay = true
            } else if isShowingOverlay && activeOverlay == nil {
                isShowingOverlay = false
            }
        }
    }
    
    @Published var isShowingOverlay: Bool = false
    @Published var isPresentingAlert: Bool = false
    
    @Published var isPerformingPostAction: (action: MastodonPostMenuAction, post: MastodonContentPost)? = nil
    @Published var isPerformingAccountAction: (action: MastodonPostMenuAction, account: MastodonAccount)? = nil
    
    @Published var timelineItems = [TimelineItem]()
    private var feedLoader: TimelineFeedLoader?
    private var feedLoaderResultsSubscription: AnyCancellable?
    private var feedLoaderErrorSubscription: AnyCancellable?
    private var tailItemIds = [String]()
    
    // Translations
    private var translations = [ Mastodon.Entity.Status.ID : Mastodon.Entity.Translation]()
    @Published var translationsShowing = Set<Mastodon.Entity.Status.ID>()
    
    func clearPendingActions() {
        if isPerformingPostAction != nil {
            isPerformingPostAction = nil
        }
        if isPerformingAccountAction != nil {
            isPerformingAccountAction = nil
        }
    }
    
    func doInitialLoad() async throws {
        guard feedLoader == nil else { return }
        guard let currentUser = AuthenticationServiceProvider.shared.currentActiveUser.value else { assertionFailure("no active authenticated user, cannot create feed loader"); return }
        authenticatedUser = currentUser
        instanceConfiguration = currentUser.authentication.instanceConfiguration
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

    func myRelationship(to account: MastodonAccount?)
        -> MastodonAccount.Relationship
    {
        guard let account else { return .isNotMe(nil)}
        return feedLoader?.myRelationship(to: account.id) ?? .isNotMe(nil)
    }
    
    func rowViewModel(for post: GenericMastodonPost, translationsToShow: Set<Mastodon.Entity.Status.ID>, isPerformingAction: MastodonPostMenuAction?) -> MastodonPostViewModel {
        let actionablePost = post.actionablePost
        let actionableAuthor = actionablePost?.metaData.author
        let relationship = myRelationship(to: actionableAuthor)
        let isDoingAction: MastodonPostMenuAction? = {
            if let isPerformingPostAction {
                guard actionablePost?.id == isPerformingPostAction.post.id else { return nil }
                return isPerformingPostAction.action
            } else if let isPerformingAccountAction {
                guard actionableAuthor?.id == isPerformingAccountAction.account.id else { return nil }
                return isPerformingAccountAction.action
            } else {
                return nil
            }
        }()
        let isShowingTranslation: Bool? = { () -> Bool? in
            guard let actionablePost else { return nil }
            guard canTranslate(post: actionablePost) else { return nil }
            return translationsToShow.contains(actionablePost.id)
        }()
        let translation: Mastodon.Entity.Translation? = {
            guard let actionablePost else { return nil }
            return translations[actionablePost.id]
        }()
        let rowViewModel = MastodonPostViewModel(post: post,
                                                 isShowingTranslation: isShowingTranslation, translation: translation,
                                                 myRelationshipToAuthor: relationship,
                                                 isDoingAction: isDoingAction,
                                                 actionHandler: self)
        return rowViewModel
    }
    
    func contentConcelModel(forPost post: GenericMastodonPost) -> ContentConcealViewModel {
        
        guard let actionablePost = post.actionablePost else { return .alwaysShow }
        return feedLoader?.contentConcealViewModel(forContentPost: actionablePost)
        ?? .alwaysShow
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
            ZStack { // to show ALT text when needed
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
                                let usableWidth =
                                geo.size.width - geo.safeAreaInsets.leading
                                - geo.safeAreaInsets.trailing
                                let contentWidth = max(1, usableWidth - (spacingBetweenGutterAndContent * 3) - avatarSize)
                                
                                let currentAction = viewModel.isPerformingPostAction?.action ?? viewModel.isPerformingAccountAction?.action
                                HomeTimelinePostRowView(viewModel: viewModel.rowViewModel(for: post, translationsToShow: viewModel.translationsShowing, isPerformingAction: currentAction),
                                                        contentConcealModel: viewModel.contentConcelModel(forPost: post),
                                                        contentWidth: contentWidth)
                                .padding(spacingBetweenGutterAndContent)
                                .listRowInsets(
                                    EdgeInsets(
                                        top: 0, leading: 0, bottom: 0, trailing: 0)
                                )
                                .frame(width: usableWidth)
                                .onAppear {
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
        }
        .onAppear() {
            Task {
                viewModel.clearPendingActions()
                try await viewModel.doInitialLoad()
            }
        }
        .alert(viewModel.activeAlert.title, isPresented: $viewModel.isPresentingAlert, presenting: viewModel.activeAlert) { alert in
            alertContents(alert)
        } message: { alert in
            if let messageText = alert.messageText {
                Text(messageText)
            }
        }
        .overlay {
            if viewModel.isShowingOverlay, let activeOverlay = viewModel.activeOverlay {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        ZStack {
                            Color.black.opacity(0.6)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    viewModel.activeOverlay = nil
                                }
                            
                            activeOverlay.view(sizedForFrame: geo.size)
                        }
                        
                        Button {
                            viewModel.activeOverlay = nil
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.title)
                                .foregroundStyle(.white)
                        }
                        .padding(standardPadding)
                    }
                }
            }
        }
    }
    
    @ViewBuilder func alertContents(_ alert: MastodonPostMenuAction.AlertType) -> some View {
        switch alert {
        case .noAlert:
            Text("no alert")
        case .confirmBoostOfPost(let didConfirm):
            cancelButton()
            Button {
                didConfirm()
            } label: {
                Text(L10n.Common.Alerts.BoostAPost.boost)
            }
            
        case .confirmDeleteOfPost(let didConfirm):
            cancelButton()
            Button(role: .destructive) {
                didConfirm()
            } label: {
                Text(L10n.Common.Controls.Actions.delete)
            }
            
        case .confirmUnfollow(_, let didConfirm):
            cancelButton()
            Button(role: .destructive) {
                didConfirm()
            } label: {
                Text(L10n.Common.Alerts.UnfollowUser.unfollow)
            }
            
        case .confirmMute(username: let username, didConfirm: let didConfirm):
            cancelButton()
            Button(role: .destructive) {
                didConfirm()
            } label: {
                Text(L10n.Common.Controls.Friendship.muteUser(username))
            }
        case .confirmUnmute(username: let username, didConfirm: let didConfirm):
            cancelButton()
            Button {
                didConfirm()
            } label: {
                Text(L10n.Common.Controls.Friendship.unmuteUser(username))
            }
            
        case .confirmBlock(username: let username, didConfirm: let didConfirm):
            cancelButton()
            Button(role: .destructive) {
                didConfirm()
            } label: {
                Text(L10n.Common.Controls.Friendship.blockUser(username))
            }
        case .confirmUnblock(username: let username, didConfirm: let didConfirm):
            cancelButton()
            Button {
                didConfirm()
            } label: {
                Text(L10n.Common.Controls.Friendship.unblockUser(username))
            }
        }
    }
    
    @ViewBuilder func cancelButton() -> some View {
        Button(role: .cancel) {
            print("cancelling")
            viewModel.clearPendingActions()
        }
        label: {
            Text(L10n.Common.Controls.Actions.cancel)
        }
    }
}

extension MastodonTimelineOverlayView {
    @ViewBuilder func view(sizedForFrame frameSize: CGSize) -> some View {
        switch self {
        case .altText(let altTextString):
            AltTextView(altTextString: altTextString, frameSize: frameSize)
        case .images(let focusedImage, let viewModel):
            if let img = viewModel.imageAttachments.first(where: { $0.id == focusedImage }) {
                ZoomableBlurhashImageView(image: img, viewModel: viewModel, frameSize: frameSize)
            }
        }
    }
}

private struct HomeTimelinePostRowView: View {

    let viewModel: MastodonPostViewModel
    @ObservedObject var contentConcealModel: ContentConcealViewModel
    let contentWidth: CGFloat
    
    let distanceFromAvatarLeadingEdgeToContentLeadingEdge: CGFloat = spacingBetweenGutterAndContent + AvatarSize.large
    
    var body: some View {
        let author = viewModel.post.actionablePost?.metaData.author ?? viewModel.post.metaData.author
        
        VStack(alignment: .gutterAlign, spacing: spacingBetweenGutterAndContent) {
            
            viewModel.socialContextHeader
            
            HStack(alignment: .top) {
            
                AvatarView(size: .large, author: author, goToProfile: { _ in
                    goToProfile(author)
                })
                
                VStack(spacing: spacingBetweenGutterAndContent) {
                    AuthorHeaderView(author: author)
                    
                    contentConcealLozenge
                        .frame(width: contentWidth)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if contentConcealModel.currentMode.isShowingContent {
                        if viewModel.isShowingTranslation == true, let translatablePost = viewModel.post.actionablePost, let translation = viewModel.actionHandler.translation(forContentPostId: translatablePost.id) {
                            TranslationInfoView(translationInfo: translation, showOriginal: { viewModel.actionHandler.doAction(.showOriginalLanguage, forPost: translatablePost) }
                            )
                            .frame(width: contentWidth + distanceFromAvatarLeadingEdgeToContentLeadingEdge, alignment: .leading)
                            .alignmentGuide(.gutterAlign) { d in
                                return d[.leading] + distanceFromAvatarLeadingEdgeToContentLeadingEdge
                            }
                        }
                        viewModel.textContentView
                            .frame(width: contentWidth, alignment: .leading)
                            .onTapGesture {
                                guard let actionablePost = viewModel.post.actionablePost, let currentUser = AuthenticationServiceProvider.shared.currentActiveUser.value else { return }
                                viewModel.actionHandler.presentScene(
                                .thread(
                                    viewModel: ThreadViewModel(
                                        authenticationBox: currentUser,
                                        optionalRoot: .root(
                                            context: .init(
                                                status: MastodonStatus(
                                                    entity: actionablePost._legacyEntity,
                                                    showDespiteContentWarning:
                                                        false))))), transition: .show)
                            }
                        
                        if let attachment = viewModel.post.actionablePost?.content.attachment {
                            switch attachment {
                            case .media(let array):
                                if contentConcealModel.currentMode.isShowingContent {
                                    MediaAttachmentView(array, altTextTranslations: viewModel.altTextTranslations).view(withContentConcealModel: contentConcealModel, actionHandler: viewModel.actionHandler)
                                        .frame(width: contentWidth)
                                }
                            case .poll(let poll):
                                HStack {
                                    Image(systemName: "checklist")
                                    Text("a poll")
                                }
                                .frame(width: contentWidth)
                            case .linkPreviewCard(let card):
                                LinkPreviewCard(cardEntity: card, fittingWidth: contentWidth)
                                .frame(width: contentWidth)
                            }
                        }
                    }
                    
                    if let actionablePost = viewModel.post.actionablePost {
                        ActionBar(viewModel: actionBarViewModel(forActionablePost: actionablePost))
                            .frame(width: contentWidth, alignment: .leading)
                    }
                }
            }
        }
    }
    
    func actionBarViewModel(forActionablePost actionablePost: MastodonContentPost) -> ActionBar.ViewModel {
        return .init(post: actionablePost,
                     actionHandler: viewModel.actionHandler,
                     replies: actionButtonViewModel(forPost: actionablePost, action: .reply),
                     boosts: actionButtonViewModel(forPost: actionablePost, action: .boost),
                     favourites: actionButtonViewModel(forPost: actionablePost, action: .favourite),
                     bookmark: actionButtonViewModel(forPost: actionablePost, action: .bookmark),
                     isShowingTranslation: viewModel.isShowingTranslation,
                     isDoingAction: viewModel.isDoingAction,
                     myRelationshipToAuthor: viewModel.myRelationshipToAuthor)
    }
    
    func overrideState(for postAction: PostAction, of actionablePost: MastodonContentPost) -> AsyncBool? {
        switch (viewModel.isDoingAction, postAction) {
        case (nil, _):
             return nil
        case (.boost, .boost), (.favourite, .favourite), (.bookmark, .bookmark):
            return .settingToTrue
        case (.unboost, .boost), (.unfavourite, .favourite), (.unbookmark, .bookmark):
            return .settingToFalse
        default:
            return nil
        }
    }
    
    func actionButtonViewModel(forPost actionablePost: MastodonContentPost, action: PostAction) -> StatefulCountedActionViewModel {
        let metrics = actionablePost.content.metrics
        let myActions = actionablePost.content.myActions
        let overrideState = overrideState(for: .reply, of: actionablePost)
        switch action {
        case .reply:
            let state = overrideState ?? AsyncBool.fromBool(myActions.boosted)
            return StatefulCountedActionViewModel(type: .reply, displayDetails: .init(count: metrics.replyCount, isSelected: state), doAction: {
                switch state {
                case .isFalse:
                    viewModel.actionHandler.doAction(.reply, forPost: actionablePost)
                default:
                    break
                }
            })
        case .boost:
            let state = overrideState ?? AsyncBool.fromBool(myActions.boosted)
            return StatefulCountedActionViewModel(type: .boost, displayDetails: .init(count: metrics.boostCount, isSelected: state), doAction: {
                switch state {
                case .isFalse:
                    viewModel.actionHandler.doAction(.boost, forPost: actionablePost)
                case .isTrue:
                    viewModel.actionHandler.doAction(.unboost, forPost: actionablePost)
                default:
                    break
                }
            })
        case .favourite:
            let state = overrideState ?? AsyncBool.fromBool(myActions.favorited)
            return StatefulCountedActionViewModel(type: .favourite, displayDetails: .init(count: metrics.favoriteCount, isSelected: state), doAction: {
                switch state {
                case .isFalse:
                    viewModel.actionHandler.doAction(.favourite, forPost: actionablePost)
                case .isTrue:
                    viewModel.actionHandler.doAction(.unfavourite, forPost: actionablePost)
                default:
                    break
                }
            })
        case .bookmark:
            let state = overrideState ?? AsyncBool.fromBool(myActions.bookmarked)
            return StatefulCountedActionViewModel(type: .bookmark, displayDetails: .init(count: nil, isSelected: state), doAction: {
                switch state {
                case .isFalse:
                    viewModel.actionHandler.doAction(.bookmark, forPost: actionablePost)
                case .isTrue:
                    viewModel.actionHandler.doAction(.unbookmark, forPost: actionablePost)
                default:
                    break
                }
            })
        }
    }
    
    @ViewBuilder func componentView(_ component: PostViewComponent) -> some View {
        switch component {
        case .content(let string):
            PostContentView(text: string)
        case .hashtags(let tags):
            HashtagRowView(hashtags: tags)
        }
    }
    
    func goToProfile(_ account: MastodonAccount) {
        switch viewModel.myRelationshipToAuthor {
        case .isMe:
            let profile: ProfileViewController.ProfileType = .me(account._legacyEntity)
            viewModel.actionHandler.presentScene(.profile(profile), transition: .show)
        case .isNotMe(let info):
            if let info, let me = AuthenticationServiceProvider.shared.currentActiveUser.value?.cachedAccount {
                let profile: ProfileViewController.ProfileType = .notMe(me: me, displayAccount: account._legacyEntity, relationship: info._legacyEntity)
                viewModel.actionHandler.presentScene(.profile(profile), transition: .show)
            }
        }
    }
}

extension HomeTimelinePostRowView {
    @ViewBuilder var contentConcealLozenge: some View {
        if let whenHiding = contentConcealModel.buttonText(whenHiding: true), let whenShowing = contentConcealModel.buttonText(whenHiding: false) {
            ShowMoreLozenge(buttonTextWhenHiding: whenHiding, buttonTextWhenShowing: whenShowing, viewModel: ShowMoreViewModel(isShowing: contentConcealModel.currentMode.isShowingContent, isFilter: contentConcealModel.currentModeIsFilter, reasons: contentConcealModel.currentMode.reasons ?? [], showMore: {
                show in
                if show {
                    contentConcealModel.showMore()
                } else {
                    contentConcealModel.hide()
                }
            }))
        }
    }
}

private struct PostContentView: View {
    //    @ObservedObject var contentWarningViewModel
    let text: String
    
    var body: some View {
        Text(text)
    }
}

private struct LinkPreviewView: View {
    let linkPreview: Mastodon.Entity.Card
    
    var body: some View {
        Text("a link preview")
    }
}

private struct PollView: View {
    let poll: Mastodon.Entity.Poll
    
    var body: some View {
        Text("a poll")
    }
}

private struct HashtagRowView: View {
    let hashtags: [String]
    
    var body: some View {
        Text("#\(hashtags.first) and \(hashtags.count - 1) others")
    }
}

private struct ActionBar: View {
    
    struct ViewModel {
        let post: MastodonContentPost
        let actionHandler: MastodonPostMenuActionHandler
        let replies: StatefulCountedActionViewModel
        let boosts: StatefulCountedActionViewModel
        let favourites: StatefulCountedActionViewModel
        let bookmark: StatefulCountedActionViewModel
        let isShowingTranslation: Bool?
        let isDoingAction: MastodonPostMenuAction?
        let myRelationshipToAuthor: MastodonAccount.Relationship
    }
    
    let viewModel: ActionBar.ViewModel

    var body: some View {
        HStack() {
            StatefulCountedActionButton(viewModel: viewModel.replies)
            Spacer()
            StatefulCountedActionButton(viewModel: viewModel.boosts)
            Spacer()
            StatefulCountedActionButton(viewModel: viewModel.favourites)
            Spacer()
            StatefulCountedActionButton(viewModel: viewModel.bookmark)
            Spacer()
            ActionBarMenuButton(viewModel: viewModel)
            Spacer()
        }
    }
    
    struct ActionBarMenuButton: View {
        let viewModel: ActionBar.ViewModel
        
        var body: some View {
            Menu {
                ForEach(submenus(), id: \.self.id) { submenu in
                    ForEach(submenu.items, id: \.self) { menuAction in
                        Button(role: menuAction.isDestructive ? .destructive : nil) {
                            viewModel.actionHandler.doAction(menuAction, forPost: viewModel.post)
                        }
                        label: {
                            Label(menuAction.labelText(username: viewModel.post.actionablePost?.metaData.author.displayInfo.displayName, postLanguage: viewModel.post.actionablePost?.content.language), systemImage: menuAction.iconSystemName)
                        }
                    }
                    Divider()
                }
            } label: {
                Label("", systemImage: "ellipsis")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        
        func submenus() -> [MastodonPostMenuAction.Submenu] {
            return MastodonPostMenuAction.menuItems(forPostBy: viewModel.myRelationshipToAuthor, isShowingTranslation: viewModel.isShowingTranslation)
        }
    }
}

private enum PostViewComponent {
    case content(String)
    case hashtags([String])
}

@MainActor
struct MastodonPostViewModel {
    
    let actionHandler: MastodonPostMenuActionHandler
    let post: GenericMastodonPost
    let isShowingTranslation: Bool?
    let translation: Mastodon.Entity.Translation?
    let isDoingAction: MastodonPostMenuAction?
    let myRelationshipToAuthor: MastodonAccount.Relationship

    init(
        post: GenericMastodonPost,
        isShowingTranslation: Bool?,
        translation: Mastodon.Entity.Translation?,
        myRelationshipToAuthor: MastodonAccount.Relationship,
        isDoingAction: MastodonPostMenuAction?,
        actionHandler: MastodonPostMenuActionHandler
    ) {
        self.post = post
        self.isShowingTranslation = isShowingTranslation
        self.translation = translation
        self.myRelationshipToAuthor = myRelationshipToAuthor
        self.isDoingAction = isDoingAction
        self.actionHandler = actionHandler
        
        assert(post.actionablePost != nil, "unexpected post type")
    }
    
    var altTextTranslations: [String : String]? {
        guard isShowingTranslation == true else { return nil }
        guard let attachmentTranslations = translation?.mediaAttachments else { return nil }
        
        let dictionary = attachmentTranslations.reduce(into: [ String : String]()) { partialResult, attachment in
            partialResult[attachment.id] = attachment.description
        }
        return dictionary
    }
}

fileprivate extension MastodonPostViewModel {
    
    var socialContextHeader: SocialContextHeader? {

        if post is MastodonBoostPost {
            // BOOSTED BY
            return .boosted(by: post.metaData.author.displayInfo.displayName, emojis: post.metaData.author.displayInfo.emojis)
        } else if let basicPost = post as? MastodonBasicPost {
            // REPLIED and/or PRIVATE MENTION
            let isPrivate = basicPost.metaData.privacyLevel == .mentionedOnly
            let replyInfo = basicPost.inReplyTo
            if let replyInfo {
                let replyToAccount = actionHandler.account(replyInfo.accountID)
                return .reply(to: replyToAccount?.displayInfo.displayName ?? "unknown", isPrivate: isPrivate, isNotification: false, emojis: replyToAccount?.displayInfo.emojis ?? [])
            } else if isPrivate {
                return .mention(isPrivate: true)
            }
        }
        return nil
    }

    var textContentView: TextViewWithCustomEmoji {
        let emptyTextContent: TextViewWithCustomEmoji = .timelinePost(html: "", emojis: TextViewWithCustomEmoji.Emojis())
        
        guard let actionablePost = post.actionablePost, let untranslatedContent = actionablePost.content.htmlWithEntities?.html else { return emptyTextContent }
        let emojis = actionablePost.content.htmlWithEntities?.emojis ?? TextViewWithCustomEmoji.Emojis()
        
        if isShowingTranslation == true, let translation = actionHandler.translation(forContentPostId: actionablePost.id)?.content {
            return .timelinePost(html: translation, emojis: emojis)
        } else {
            return .timelinePost(html: untranslatedContent, emojis: emojis)
        }
    }

    var hashtagComponent: PostViewComponent? {
        return .hashtags(["needs_implementation"])
    }
}

extension HomeTimelineListViewModel: MastodonPostMenuActionHandler {
    func showOverlay(_ overlay: MastodonTimelineOverlayView?) {
        activeOverlay = overlay
    }
    
    func presentScene(_ scene: SceneCoordinator.Scene, transition: SceneCoordinator.Transition) {
        parentVcPresentScene?(scene, transition)
    }
    
    func account(_ id: Mastodon.Entity.Account.ID) -> MastodonAccount? {
        return feedLoader?.account(id)
    }
    
    func doAction(_ action: MastodonPostMenuAction, forPost post: MastodonContentPost) {
        
        // Check not currently performing an action.
        guard isPerformingPostAction == nil && isPerformingAccountAction == nil else { return }
        
        guard let authenticatedUser, let actionablePost = post.actionablePost else { return }

        let author = actionablePost.metaData.author
        let relationshipInfo = myRelationship(to: author).info
        
        // Inform of what action is being done. These are cleared upon success or error, and in onAppear() of the view.
        if action.updatesMyActionsOnPost {
            self.isPerformingPostAction = (action, actionablePost)
        } else if action.updatesMyRelationshipToAuthor {
            self.isPerformingAccountAction = (action, author)
        }
        
        Task {
            do {
                switch action {
            
            // MARK: ACTION BAR
                case .reply:
                    guard let actionablePost = post.actionablePost else { throw PostActionFailure.noActionablePostId }
                    let statusEntityToReplyTo = try await APIService.shared.status(statusID: actionablePost.id, authenticationBox: authenticatedUser).value
                    let composeViewModel = ComposeViewModel(
                        authenticationBox: authenticatedUser,
                        composeContext: .composeStatus,
                        destination: .reply(parent: MastodonStatus(entity: statusEntityToReplyTo, showDespiteContentWarning: true))
                    )
                    presentScene(.compose(viewModel: composeViewModel), transition: .modal(animated: true, completion: nil))
                case .boost:
                    Task {
                        await boost(actionablePost.id, askFirst: UserDefaults.standard.askBeforeBoostingAPost)
                    }
                case .unboost, .favourite, .unfavourite, .bookmark, .unbookmark:
                    let updated: Mastodon.Entity.Status?
                    switch action {
                    case .unboost:
                        updated = try await APIService.shared.unboost(boostableStatusId: actionablePost.id, authenticationBox: authenticatedUser)
                    case .favourite:
                        updated = try await APIService.shared.favourite(actionableStatusID: actionablePost.id, authenticationBox: authenticatedUser)
                    case .unfavourite:
                        updated = try await APIService.shared.unfavourite(actionableStatusId: actionablePost.id, authenticationBox: authenticatedUser)
                    case .bookmark:
                        updated = try await APIService.shared.bookmark(actionableStatusId: actionablePost.id, authenticationBox: authenticatedUser)
                    case .unbookmark:
                        updated = try await APIService.shared.unbookmark(actionableStatusId: actionablePost.id, authenticationBox: authenticatedUser)
                    default:
                        assertionFailure("not implemented")
                        updated = nil
                    }
                    if let updated {
                        feedLoader?.updatePost(post: GenericMastodonPost.fromStatus(updated))
                    }
                    clearPendingActions()
                    
            // MARK: TRANSLATE
                case .translatePost:
                    try await showTranslation(forPost: actionablePost)
                case .showOriginalLanguage:
                    translationsShowing.remove(actionablePost.id)
                    
            // MARK: EDIT
                case .editPost:
                    guard let actionablePost = post.actionablePost else { throw PostActionFailure.noActionablePostId }
                    let statusEntityToEdit = try await APIService.shared.status(statusID: actionablePost.id, authenticationBox: authenticatedUser).value
                    let statusSourceToEdit = try await APIService.shared.getStatusSource(
                        forStatusID: actionablePost.id,
                        authenticationBox: authenticatedUser
                    ).value
                    
                    let editStatusViewModel = ComposeViewModel(
                        authenticationBox: authenticatedUser,
                        composeContext: .editStatus(status: MastodonStatus(entity: statusEntityToEdit, showDespiteContentWarning: true), statusSource: statusSourceToEdit),
                        destination: .topLevel)
                    presentScene(.editStatus(viewModel: editStatusViewModel), transition: .modal(animated: true))
                    
            // MARK: POST ACTIONS
                case .copyLinkToPost:
                    guard let urlString = post.actionablePost?.metaData.url else { throw PostActionFailure.noActionablePostId }
                    UIPasteboard.general.string = urlString
                    
                case .openPostInBrowser:
                    guard let urlString = post.actionablePost?.metaData.url, let url = URL(string: urlString) else { throw PostActionFailure.noActionablePostId }
                    presentScene(.safari(url: url), transition: .safariPresent(animated: true))
                    
                case .sharePost:
                    sharePost(actionablePost)

            // MARK: RELATIONSHIP ACTIONS
                    
                case .follow:
                    guard relationshipInfo?.canFollow == true else { throw PostActionFailure.noRelationshipInfo }
                    Task {
                        await commitFollow(author.id)
                    }
                    
                case .unfollow:
                    await doUnfollow(author, askFirst: UserDefaults.standard.askBeforeUnfollowingSomeone)

                case .mute:
                    activeAlert = .confirmMute(username: author.displayInfo.displayName, didConfirm: { [weak self] in
                        Task {
                            await self?.commitMute(author.id)
                        }
                    })
                    
                case .unmute:
                    activeAlert = .confirmUnmute(username: author.displayInfo.displayName, didConfirm: { [weak self] in
                        Task {
                            await self?.commitUnmute(author.id)
                        }
                    })
                    
            // MARK: DEFENSIVE ACTIONS
                case .blockUser:
                    activeAlert = .confirmBlock(username: author.displayInfo.displayName, didConfirm: { [weak self] in
                        Task {
                            await self?.commitBlock(author.id)
                        }
                    })
                    
                case .unblockUser:
                    activeAlert = .confirmUnblock(username: author.displayInfo.displayName, didConfirm: { [weak self] in
                        Task {
                            await self?.commitUnblock(author.id)
                        }
                    })
                    
                case .reportUser:
                    guard let relationship = try await APIService.shared.relationship(forAccountIds: [author.id], authenticationBox: authenticatedUser).value.first else { throw PostActionFailure.noRelationshipInfo }
                    let accountToReport = try await APIService.shared.accountInfo(domain: authenticatedUser.domain, userID: author.id, authorization: authenticatedUser.userAuthorization)
                    
                    let statusEntity: Mastodon.Entity.Status?
                    if let postIdToReport = post.actionablePost?.id {
                        statusEntity = try? await APIService.shared.status(statusID: postIdToReport, authenticationBox: authenticatedUser).value
                    } else {
                        statusEntity = nil
                    }
                    
                    let reportViewModel = ReportViewModel(
                        context: AppContext.shared,
                        authenticationBox: authenticatedUser,
                        account: accountToReport,
                        relationship: relationship,
                        status: statusEntity == nil ? nil : MastodonStatus(entity: statusEntity!, showDespiteContentWarning: true),
                        contentDisplayMode: .neverConceal
                    )
                    presentScene(.report(viewModel: reportViewModel), transition: .modal(animated: true, completion: nil))
                    
            // MARK: DELETE
                case .deletePost:
                    guard let postID = post.actionablePost?.id else { throw PostActionFailure.noActionablePostId }
                    try await deletePost(postID, askFirst: UserDefaults.shared.askBeforeDeletingAPost)
                }
            } catch {
                // TODO: handle error in a way the user can see it
                assertionFailure()
                clearPendingActions()
            }
        }
    }

    func canTranslate(post: MastodonContentPost) -> Bool {
        guard let postLanguage = post.content.language else { return false }
        guard let deviceLanguage = Bundle.main.preferredLocalizations.first else { return false }
        guard deviceLanguage != postLanguage else { return false }
    
        return instanceConfiguration?.canTranslateFrom(
            postLanguage,
            to: deviceLanguage
        ) ?? false
    }
    
    func translation(forContentPostId postId: MastodonSDK.Mastodon.Entity.Status.ID) -> MastodonSDK.Mastodon.Entity.Translation? {
        return translations[postId]
    }
    
    // TRANSLATION
    private func showTranslation(forPost post: MastodonContentPost) async throws {
        
        if let availableTranslation = translations[post.id] {
            translationsShowing.insert(post.id)
            return
        } else {
            guard let authenticatedUser else { throw APIService.APIError.explicit(.authenticationMissing) }
            
            let translation = try await APIService.shared
                .translateStatus(
                    statusID: post.id,
                    authenticationBox: authenticatedUser
                ).value
            
            guard let translationContent = translation.content, translationContent.isNotEmpty else { throw PostActionFailure.translationEmptyOrInvalid }
            
            translations[post.id] = translation
            translationsShowing.insert(post.id)
        }
    }
    
    // BOOST with optional confirmation dialog
    func boost(_ actionablePostId: Mastodon.Entity.Status.ID, askFirst: Bool) async {
        do {
            guard let authenticatedUser else { throw APIService.APIError.explicit(.authenticationMissing) }
            
            if askFirst {
                activeAlert = .confirmBoostOfPost(didConfirm: {
                    Task {
                        await self.boost(actionablePostId, askFirst: false)
                    }
                })
            } else {
                let updated = try await APIService.shared.boost(boostableStatusId: actionablePostId, authenticationBox: authenticatedUser)
                feedLoader?.updatePost(post: GenericMastodonPost.fromStatus(updated))
                clearPendingActions()
            }
        } catch {
            // TODO: make visible to user
            clearPendingActions()
        }
    }
    
    // RELATIONSHIP ACTIONS
    
    func doUnfollow(_ author: MastodonAccount, askFirst: Bool) async {
        do {
            if askFirst {
                activeAlert = .confirmUnfollow(username: author.displayInfo.displayName, didConfirm: { [weak self] in
                    Task {
                        await self?.doUnfollow(author, askFirst: false)
                    }
                })
            } else {
                guard let authenticatedUser else { throw APIService.APIError.explicit(.authenticationMissing) }
                let response = try await APIService.shared.unfollow(author.id, authenticationBox: authenticatedUser)
                let newRelationshipInfo = MastodonAccount.RelationshipInfo(response, fetchedAt: .now)
                feedLoader?.updateMyRelationship(.isNotMe(newRelationshipInfo), to: author.id)
                AuthenticationServiceProvider.shared.fetchFollowingAndBlockedAsync()
            }
        } catch {
            // TODO: make visible to user
            assert(false)
        }
        isPerformingAccountAction = nil
    }
    
    func commitFollow(_ accountID: Mastodon.Entity.Account.ID) async {
        do {
            guard let authenticatedUser else { throw APIService.APIError.explicit(.authenticationMissing) }
            let response = try await APIService.shared.follow(accountID, authenticationBox: authenticatedUser)
            let newRelationshipInfo = MastodonAccount.RelationshipInfo(response, fetchedAt: .now)
            feedLoader?.updateMyRelationship(.isNotMe(newRelationshipInfo), to: accountID)
            AuthenticationServiceProvider.shared.fetchFollowingAndBlockedAsync()
        } catch {
            // TODO: make visible to user
        }
        isPerformingAccountAction = nil
    }
    
    func commitMute(_ accountID: Mastodon.Entity.Account.ID) async {
        do {
            guard let authenticatedUser else { throw APIService.APIError.explicit(.authenticationMissing) }
            let response = try await APIService.shared.mute(accountID, authenticationBox: authenticatedUser)
            let newRelationshipInfo = MastodonAccount.RelationshipInfo(response, fetchedAt: .now)
            feedLoader?.updateMyRelationship(.isNotMe(newRelationshipInfo), to: accountID)
            AuthenticationServiceProvider.shared.fetchFollowingAndBlockedAsync()
        } catch {
            // TODO: make visible to user
        }
        isPerformingAccountAction = nil
    }
    
    func commitUnmute(_ accountID: Mastodon.Entity.Account.ID) async {
        do {
            guard let authenticatedUser else { throw APIService.APIError.explicit(.authenticationMissing) }
            let response = try await APIService.shared.unmute(accountID, authenticationBox: authenticatedUser)
            let newRelationshipInfo = MastodonAccount.RelationshipInfo(response, fetchedAt: .now)
            feedLoader?.updateMyRelationship(.isNotMe(newRelationshipInfo), to: accountID)
            AuthenticationServiceProvider.shared.fetchFollowingAndBlockedAsync()
        } catch {
            // TODO: make visible to user
        }
        isPerformingAccountAction = nil
    }
     
    // DEFENSIVE ACTIONS
    
    func commitBlock(_ accountID: Mastodon.Entity.Account.ID) async {
        do {
            guard let authenticatedUser else { throw APIService.APIError.explicit(.authenticationMissing) }
            let response = try await APIService.shared.block(accountID, authenticationBox: authenticatedUser)
            let newRelationshipInfo = MastodonAccount.RelationshipInfo(response, fetchedAt: .now)
            feedLoader?.updateMyRelationship(.isNotMe(newRelationshipInfo), to: accountID)
            AuthenticationServiceProvider.shared.fetchFollowingAndBlockedAsync()
        } catch {
            // TODO: make visible to user
        }
        isPerformingAccountAction = nil
    }
    
    func commitUnblock(_ accountID: Mastodon.Entity.Account.ID) async {
        do {
            guard let authenticatedUser else { throw APIService.APIError.explicit(.authenticationMissing) }
            let response = try await APIService.shared.unblock(accountID, authenticationBox: authenticatedUser)
            let newRelationshipInfo = MastodonAccount.RelationshipInfo(response, fetchedAt: .now)
            feedLoader?.updateMyRelationship(.isNotMe(newRelationshipInfo), to: accountID)
            AuthenticationServiceProvider.shared.fetchFollowingAndBlockedAsync()
        } catch {
            // TODO: make visible to user
        }
        isPerformingAccountAction = nil
    }
    
    func deletePost(_ postID: Mastodon.Entity.Status.ID, askFirst: Bool) async {
        do {
            if askFirst {
                activeAlert = .confirmDeleteOfPost(didConfirm: {
                    Task {
                        await self.deletePost(postID, askFirst: false)
                    }
                })
            } else {
                guard let authenticatedUser else { throw APIService.APIError.explicit(.authenticationMissing) }
                let deletedStatus = try await APIService.shared.deleteContentPost(postID, authenticationBox: authenticatedUser)
                feedLoader?.didDeletePost(deletedStatus.id)
                self.clearPendingActions()
            }
        } catch {
            self.clearPendingActions()
            // TODO: make visible to user
        }
    }
    
    func sharePost(_ actionablePost: MastodonContentPost) {
        var activityItems: [Any] = {
            guard let url = URL(string: actionablePost.metaData.url ?? actionablePost.metaData.uriForFediverse) else { return [] }
            return [
                URLActivityItem(url: url)
            ]
        }()

        let activityViewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        
        presentScene(
            .activityViewController(
                activityViewController: activityViewController,
                sourceView: nil,
                barButtonItem: nil
            ),
            transition: .activityViewControllerPresent(animated: true, completion: nil)
        )
    }
    
}

extension GenericMastodonPost {
    var actionablePost: MastodonContentPost? {
        let actionablePost: MastodonContentPost?
        if let contentPost = self as? MastodonContentPost {
            actionablePost = contentPost
        } else if let boost = self as? MastodonBoostPost {
            actionablePost = boost.boostedPost
        } else {
            assertionFailure("not implemented")
            actionablePost = nil
        }
        return actionablePost
    }
}

struct TranslationInfoView: View {
    let translationInfo: Mastodon.Entity.Translation
    let showOriginal: ()->()
    
    var body: some View {
        HStack(alignment: .top) {
            Text(translatedFromLanguageByProvider)
                .lineLimit(1)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                showOriginal()
            } label: {
                Text(L10n.Common.Controls.Status.Translation.showOriginal)
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundStyle(Asset.Colors.Brand.blurple.swiftUIColor)
            }
            .fixedSize()
        }
    }
    
    var translatedFromLanguageByProvider: String {
        let languageName = languageName(translationInfo.sourceLanguage) ?? L10n.Common.Controls.Status.Translation.unknownLanguage
        return L10n.Common.Controls.Status.Translation.translatedFrom(languageName, translationInfo.provider ?? L10n.Common.Controls.Status.Translation.unknownProvider)
    }
}

extension ContentConcealViewModel {
    func buttonText(whenHiding: Bool) -> String? {
        switch currentMode {
        case .neverConceal, .concealMediaOnly:
            return nil
        case .concealAll:
            if currentModeIsFilter {
                return whenHiding ? L10n.Common.Controls.Status.showAnyway : L10n.Common.Controls.Status.Actions.hide
            } else {
                return whenHiding ? L10n.Common.Controls.Status.showMore : L10n.Common.Controls.Status.Actions.hide
            }
        }
    }
}
