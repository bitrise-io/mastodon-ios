// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import SwiftUI
import MastodonAsset
import MastodonCore
import MastodonLocalization
import MastodonSDK
import Combine
import MastodonUI
import Meta

class HomeTimelineListViewController: UIHostingController<HomeTimelineListView>
{
    private let viewModel = HomeTimelineListViewModel(timeline: .following)
    private let _mediaPreviewTransitionController = MediaPreviewTransitionController()
    
    init() {
        let root = HomeTimelineListView(viewModel: viewModel)
        super.init(rootView: root)
        viewModel.parentVcPresentScene = { (scene, transition) in
            self.sceneCoordinator?.present(scene: scene, transition: transition)
        }
        viewModel.hostingViewController = self
        
        setUpTimelineSelectorButton()
        showSettingsButton(true)
    }
    
    @objc private func settingBarButtonItemPressed(_ sender: UIBarButtonItem) {
        guard let setting = SettingService.shared.currentSetting.value else { return }
        
        _ = self.sceneCoordinator?.present(scene: .settings(setting: setting), from: self, transition: .none)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError(
            "init(coder:) not implemented for HomeTimelineListViewController")
    }
    
    lazy var settingBarButtonItem: UIBarButtonItem = {
        let barButtonItem = UIBarButtonItem()
        barButtonItem.tintColor = Asset.Colors.Brand.blurple.color
        barButtonItem.image = UIImage(systemName: "gear")
        barButtonItem.accessibilityLabel = L10n.Common.Controls.Actions.settings
        barButtonItem.target = self
        barButtonItem.action = #selector(Self.settingBarButtonItemPressed(_:))
        return barButtonItem
    }()
    
    func setUpTimelineSelectorButton() {
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(customView: timelineSelectorButton)
    }
    
    func showSettingsButton(_ show: Bool) {
        if show {
            self.navigationItem.rightBarButtonItem = settingBarButtonItem
        } else {
            self.navigationItem.rightBarButtonItem = nil
        }
    }
    
    lazy var timelineSelectorButton = {
        let button = UIButton(type: .custom)
        
        button.setAttributedTitle(
            .init(string: L10n.Scene.HomeTimeline.TimelineMenu.following, attributes: [
                .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 20, weight: .semibold))
            ]),
            for: .normal)
        
        let imageConfiguration = UIImage.SymbolConfiguration(paletteColors: [.secondaryLabel, .secondarySystemFill])
            .applying(UIImage.SymbolConfiguration(textStyle: .subheadline))
            .applying(UIImage.SymbolConfiguration(pointSize: 16, weight: .bold, scale: .medium))
        
        button.configuration = {
            var config = UIButton.Configuration.plain()
            config.contentInsets = .init(top: 0, leading: 0, bottom: 0, trailing: 0)
            config.imagePadding = 8
            config.image = UIImage(systemName: "chevron.down.circle.fill", withConfiguration: imageConfiguration)
            config.imagePlacement = .trailing
            return config
        }()
        
        button.showsMenuAsPrimaryAction = true
        button.menu = generateTimelineSelectorMenu()
        return button
    }()
    
    private func generateTimelineSelectorMenu() -> UIMenu {
        let showFollowingAction = UIAction(title: L10n.Scene.HomeTimeline.TimelineMenu.following, image: .init(systemName: "house")) { [weak self] _ in
            guard let self else { return }
            
            viewModel.timeline = .following
            self.timelineSelectorButton.setAttributedTitle(
                .init(string: L10n.Scene.HomeTimeline.TimelineMenu.following, attributes: [
                    .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 20, weight: .semibold))
                ]),
                for: .normal)
            
            self.timelineSelectorButton.sizeToFit()
            self.timelineSelectorButton.menu = self.generateTimelineSelectorMenu()
        }
        
        let showLocalTimelineAction = UIAction(title: L10n.Scene.HomeTimeline.TimelineMenu.localCommunity, image: .init(systemName: "building.2")) { [weak self] action in
            guard let self else { return }
            
            viewModel.timeline = .local
            timelineSelectorButton.setAttributedTitle(
                .init(string: L10n.Scene.HomeTimeline.TimelineMenu.localCommunity, attributes: [
                    .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 20, weight: .semibold))
                ]),
                for: .normal)
            timelineSelectorButton.sizeToFit()
            timelineSelectorButton.menu = generateTimelineSelectorMenu()
        }
        
        switch viewModel.timeline {
        case .following:
            showLocalTimelineAction.state = .off
            showFollowingAction.state = .on
        case .local:
            showLocalTimelineAction.state = .on
            showFollowingAction.state = .off
        case .list:
            showLocalTimelineAction.state = .off
            showFollowingAction.state = .off
        case .hashtag:
            showLocalTimelineAction.state = .off
            showFollowingAction.state = .off
        }
        
        let listsSubmenu = UIDeferredMenuElement.uncached { [weak self] callback in
            guard let self else { return callback([]) }
            
            Task { @MainActor in
                guard let currentUser = AuthenticationServiceProvider.shared.currentActiveUser.value else { return }
                
                let lists = (try? await Mastodon.API.Lists.getLists(
                    session: .shared,
                    domain: currentUser.domain,
                    authorization: currentUser.userAuthorization
                ).singleOutput().value) ?? []
                
                var listEntries = lists.map { entry in
                    return LabeledAction(title: entry.title, image: nil, handler: { [weak self] in
                        guard let self else { return }
                        viewModel.timeline = .list(entry.id)
                        timelineSelectorButton.setAttributedTitle(
                            .init(string: entry.title, attributes: [
                                .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 20, weight: .semibold))
                            ]),
                            for: .normal)
                        timelineSelectorButton.sizeToFit()
                        timelineSelectorButton.menu = generateTimelineSelectorMenu()
                    }).menuElement
                }
                
                if listEntries.isEmpty {
                    listEntries = [
                        UIAction(title: L10n.Scene.HomeTimeline.TimelineMenu.Lists.emptyMessage, attributes: [.disabled], handler: {_ in })
                    ]
                }
                
                callback(listEntries)
            }
        }
        
        let listsMenu = UIMenu(
            title: L10n.Scene.HomeTimeline.TimelineMenu.Lists.title,
            image: UIImage(systemName: "list.bullet.rectangle.portrait"),
            children: [listsSubmenu]
        )
        
        let hashtagsSubmenu = UIDeferredMenuElement.uncached { [weak self] callback in
            guard let self else { return callback([]) }
            
            Task { @MainActor in
                guard let currentUser = AuthenticationServiceProvider.shared.currentActiveUser.value else { return }
                
                let lists = (try? await Mastodon.API.Account.followedTags(
                    session: .shared,
                    domain: currentUser.domain,
                    query: .init(limit: nil),
                    authorization: currentUser.userAuthorization
                ).singleOutput().value) ?? []
                
                var listEntries = lists.map { entry in
                    let entryName = "#\(entry.name)"
                    return LabeledAction(title: entryName, image: nil, handler: { [weak self] in
                        guard let self else { return }
                        viewModel.timeline = .hashtag(entry.name)
                        timelineSelectorButton.setAttributedTitle(
                            .init(string: entryName, attributes: [
                                .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 20, weight: .semibold))
                            ]),
                            for: .normal)
                        timelineSelectorButton.sizeToFit()
                        timelineSelectorButton.menu = generateTimelineSelectorMenu()
                    }).menuElement
                }
                
                if listEntries.isEmpty {
                    listEntries = [
                        UIAction(title: L10n.Scene.HomeTimeline.TimelineMenu.Hashtags.emptyMessage, attributes: [.disabled], handler: {_ in })
                    ]
                }
                
                callback(listEntries)
            }
        }
        
        let hashtagsMenu = UIMenu(
            title: L10n.Scene.HomeTimeline.TimelineMenu.Hashtags.title,
            image: UIImage(systemName: "number"),
            children: [hashtagsSubmenu]
        )
        
        let listsDivider = UIMenu(title: "", options: .displayInline, children: [listsMenu, hashtagsMenu])
        
        return UIMenu(children: [showFollowingAction, showLocalTimelineAction, listsDivider])
    }
}

extension HomeTimelineListViewController: MediaPreviewableViewController {
    var mediaPreviewTransitionController: MediaPreviewTransitionController {
        return _mediaPreviewTransitionController
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
    var hostingViewController: MediaPreviewableViewController?
    
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
    private let displayPrepBatchSize = 10
    private var currentlyPreparingForDisplay: [Mastodon.Entity.Status.ID]?
    private var displayPrepRequested: [MastodonPostViewModel]? // only keep the latest batch requested, to avoid getting bogged down while fast scrolling
    
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
    
    func commitToCache() {
        Task {
            await feedLoader?.commitToCache()
        }
    }
    
    public var timeline: MastodonTimelineType {
        didSet {
            guard feedLoader?.timeline != timeline else { return }
            feedLoader = nil
            Task {
                try await doInitialLoad()
            }
        }
    }
    
    init(timeline: MastodonTimelineType) {
        self.timeline = timeline
        Task {
            try await doInitialLoad()
        }
    }
    
    func doInitialLoad() async throws {
        guard feedLoader == nil else { return }
        guard let currentUser = AuthenticationServiceProvider.shared.currentActiveUser.value else { assertionFailure("no active authenticated user, cannot create feed loader"); return }
        clearPendingActions()
        authenticatedUser = currentUser
        instanceConfiguration = currentUser.authentication.instanceConfiguration
        feedLoader = TimelineFeedLoader(currentUser: currentUser, timeline: timeline)
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
    
    func didAppear(_ postViewModel: MastodonPostViewModel, contentWidth: CGFloat) {
        guard feedLoader?.records.canLoadOlder == true else {
#if DEBUG
            print("nothing left to load")
#endif
            return
        }
        
        if tailItemIds.contains(postViewModel.initialDisplayInfo.id) {
            tailItemIds = []
            requestLoad(.older)
        }
        
        prepareForDisplay(including: postViewModel, withContentWidth: contentWidth)
    }

    func myRelationship(to account: MastodonAccount?)
        -> MastodonAccount.Relationship
    {
        guard let account else { return .isNotMe(nil)}
        return feedLoader?.myRelationship(to: account.id) ?? .isNotMe(nil)
    }
    
    
    func contentConcealModel(forActionablePost post: Mastodon.Entity.Status.ID) -> ContentConcealViewModel {
        return feedLoader?.contentConcealViewModel(forContentPost: post) ?? .alwaysShow
    }
}

extension HomeTimelineListViewModel {
    func prepareForDisplay(including anchorItem: MastodonPostViewModel, withContentWidth contentWidth: CGFloat) {
        let thisItemID = anchorItem.initialDisplayInfo.id
        
        let isCurrentlyPreparing = currentlyPreparingForDisplay?.contains(thisItemID) == true
        let isAlreadyRequested = displayPrepRequested?.contains(where: { $0.initialDisplayInfo.id == thisItemID}) == true
        guard !isCurrentlyPreparing && !isAlreadyRequested else { return }
        switch anchorItem.displayPrepStatus {
        case .unprepared:
            // prep a new batch (or request it)
            guard let anchorItemIndex = feedLoader?.records.allRecords.firstIndex(where: { $0.id == thisItemID }) else { return }
            guard let batch = createPrepBatch(anchoredAt: anchorItemIndex) else { return }
            if currentlyPreparingForDisplay == nil {
                doPrepareForDisplay(batch, contentWidth: contentWidth)
            } else {
                displayPrepRequested = batch
            }
        case .donePreparing:
            guard displayPrepRequested == nil else { return }
            guard let thisItemIndex = feedLoader?.records.allRecords.firstIndex(where: { $0.id == thisItemID }) else { return }
            // check if a neighboring batch could use preparing
            if let nextBatch = createPrepBatch(anchoredAt: thisItemIndex + displayPrepBatchSize) ?? createPrepBatch(anchoredAt: thisItemIndex - displayPrepBatchSize) {
                if currentlyPreparingForDisplay == nil {
                    doPrepareForDisplay(nextBatch, contentWidth: contentWidth)
                } else {
                    displayPrepRequested = nextBatch
                }
            }
        }
    }

    private func createPrepBatch(anchoredAt anchorIndex: Int) -> [MastodonPostViewModel]? {
        guard let feedLoaderRecords = feedLoader?.records.allRecords else { return nil }
        let batchStart = max(0, anchorIndex - displayPrepBatchSize / 2)
        guard batchStart < feedLoaderRecords.count else { return nil }
        let batchItems = feedLoaderRecords[batchStart...].prefix(displayPrepBatchSize).compactMap { item -> MastodonPostViewModel? in
            switch item {
            case .loadingIndicator, .missingPosts:
                return nil
            case .post(let postViewModel):
                // not donePreparing, not included in currently preparing (inclusion in requested does not matter, because this batch may replace the current requested batch)
                guard postViewModel.displayPrepStatus == .unprepared && currentlyPreparingForDisplay?.contains(postViewModel.initialDisplayInfo.id) != true else { return nil }
                return postViewModel
            }
        }
        
        guard !batchItems.isEmpty else { return nil }
        return batchItems
    }
    
    private func doPrepareForDisplay(_ batch: [MastodonPostViewModel], contentWidth: CGFloat) {
        guard let feedLoader else { return }
        guard currentlyPreparingForDisplay == nil else { assertionFailure(); return }
        currentlyPreparingForDisplay = batch.map { $0.initialDisplayInfo.id }
        
        Task {
            // make sure we have the full posts to work with (if we are working from a cached timeline)
            let needsCacheFetch = batch.compactMap { postModel in
                return postModel.fullPost == nil ? postModel.initialDisplayInfo.id : nil
            }
            let cachedPosts = await feedLoader.fetchCachedPosts(needsCacheFetch)
            
            var needsRelationshipFetch = [GenericMastodonPost]()
            var needsHtmlProcessing = [MastodonPostViewModel]()
            for postModel in batch {
                if let cachedPost = cachedPosts[postModel.initialDisplayInfo.id] {
                    postModel.fullPost = cachedPost
                }

                if let fullPost = postModel.fullPost, postModel.myRelationshipToAuthor == nil {
                    needsRelationshipFetch.append(fullPost)
                }
                
                if !postModel.hasCalculatedForWidth(contentWidth) {
                    needsHtmlProcessing.append(postModel)
                }

                let needsRelationshipFetch = needsRelationshipFetch
                async let relationshipFetchTask = {
                    try await feedLoader.fetchRelationships(needsRelationshipFetch)
                }
                async let htmlProcessingTask = {
                }
                
                let (_,_) = await(relationshipFetchTask, htmlProcessingTask)
                for postModel in batch {
                    if postModel.myRelationshipToAuthor == nil {
                        postModel.myRelationshipToAuthor = feedLoader.myRelationship(to: postModel.initialDisplayInfo.actionableAuthorId)
                    }
                    if postModel.actionHandler == nil {
                        postModel.actionHandler = self
                    }
                    postModel.displayPrepStatus = .donePreparing
                }
                
                currentlyPreparingForDisplay = nil
                if let displayPrepRequested = self.displayPrepRequested {
                    self.displayPrepRequested = nil
                    doPrepareForDisplay(displayPrepRequested, contentWidth: contentWidth)
                }
            }
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
            ZStack { // to show ALT text when needed
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack {
                            ForEach(viewModel.timelineItems, id: \.self) { item in
                                switch item {
                                case let .missingPosts(newerThan, olderThan):
                                    GapLoaderView(newerThan: newerThan, olderThan: olderThan, gapDescription: "",
                                                  loadFromTop: {
                                        viewModel.requestLoad(.olderThan(olderThan))
                                    }, loadFromBottom: {
                                        viewModel.requestLoad(.newerThan(newerThan))
                                    })
                                case .loadingIndicator:
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                        Spacer()
                                    }
                                case .post(let postViewModel):
                                    let usableWidth =
                                    geo.size.width - geo.safeAreaInsets.leading
                                    - geo.safeAreaInsets.trailing
                                    let contentWidth = max(1, usableWidth - (spacingBetweenGutterAndContent * 3) - avatarSize)
                                    
                                    HomeTimelinePostRowView(viewModel: postViewModel,
                                                            contentConcealModel: viewModel.contentConcealModel(forActionablePost: postViewModel.initialDisplayInfo.actionablePostID),
                                                            contentWidth: contentWidth)
                                    .padding(spacingBetweenGutterAndContent)
                                    .frame(width: usableWidth)
                                    .onAppear {
                                        viewModel.didAppear(postViewModel, contentWidth: contentWidth)
                                    }
#if DEBUG && false
                                    .background {
                                        if recentlyInsertedItemIds?.contains(postViewModel.initialDisplayInfo.id) == true {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(.blue.opacity(0.2))
                                        }
                                    }
#endif
                                }
                            }
                        }
                    }
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
            viewModel.clearPendingActions()
        }
        .onDisappear() {
            viewModel.commitToCache()
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

    @ObservedObject var viewModel: MastodonPostViewModel
    @ObservedObject var contentConcealModel: ContentConcealViewModel
    let contentWidth: CGFloat
    
    let distanceFromAvatarLeadingEdgeToContentLeadingEdge: CGFloat = spacingBetweenGutterAndContent + AvatarSize.large
    
    var body: some View {
        let actionablePost = viewModel.fullPost?.actionablePost
        let author = actionablePost?.metaData.author ?? viewModel.fullPost?.metaData.author
        
        VStack(alignment: .gutterAlign, spacing: spacingBetweenGutterAndContent) {
            
            viewModel.socialContextHeader
            
            HStack(alignment: .top) {
            
                AvatarView(size: .large, authorAvatarUrl: author?.avatarURL ?? viewModel.initialDisplayInfo.actionableAuthorStaticAvatar, goToProfile: {
                    goToProfile(author)
                })
                
                VStack(spacing: spacingBetweenGutterAndContent) {
                    AuthorHeaderView(postViewModel: viewModel, timestamper: viewModel.timestamper)
                    
                    contentConcealLozenge
                        .frame(width: contentWidth)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if contentConcealModel.currentMode.isShowingContent, let actionHandler = viewModel.actionHandler {
                        if viewModel.isShowingTranslation == true, let translatablePost = viewModel.fullPost?.actionablePost, let translation = actionHandler.translation(forContentPostId: translatablePost.id) {
                            TranslationInfoView(translationInfo: translation, showOriginal: { actionHandler.doAction(.showOriginalLanguage, forPost: translatablePost) }
                            )
                            .frame(width: contentWidth, alignment: .leading)
                        }
                        viewModel.textContentView()
                            .frame(width: contentWidth, alignment: .leading)
                        
                        if let attachment = viewModel.fullPost?.actionablePost?.content.attachment {
                            switch attachment {
                            case .media(let array):
                                MediaAttachment(array, altTextTranslations: viewModel.altTextTranslations).view(withContentConcealModel: contentConcealModel, actionHandler: actionHandler)
                                    .frame(width: contentWidth)
                            case .poll(let poll):
                                let emojis = viewModel.fullPost?.actionablePost?.content.htmlWithEntities?.emojis
                                PollView(viewModel: PollViewModel(pollEntity: poll, emojis: emojis, optionTranslations: viewModel.isShowingTranslation == true ? viewModel.pollOptionTranslations : nil, containingPostID: viewModel.initialDisplayInfo.actionablePostID, actionHandler: actionHandler), contentWidth: contentWidth)
                                    .frame(width: contentWidth)
                            case .linkPreviewCard(let card):
                                LinkPreviewCard(cardEntity: card, fittingWidth: contentWidth, navigateToScene: { (scene, transition) in
                                    actionHandler.presentScene(scene, transition: transition)
                                })
                                .frame(width: contentWidth)
                            }
                        }
                    }
                    
#if DEBUG && false
                    VStack {
                        Text(viewModel.post.id)
                        if let actionableID = viewModel.post.actionablePost?.id, actionableID != viewModel.post.id {
                            Text("(content: \(actionableID))")
                        }
                    }
                    .foregroundStyle(.red)
                    .font(.footnote)
#endif
                    
                    if let actionablePost = viewModel.fullPost?.actionablePost, let actionHandler = viewModel.actionHandler, let actionBarViewModel = actionBarViewModel(forActionablePost: actionablePost, actionHandler: actionHandler) {
                        ActionBar(viewModel: actionBarViewModel)
                            .frame(width: contentWidth, alignment: .leading)
                    }
                }
            }
        }
    }
    
    func actionBarViewModel(forActionablePost actionablePost: MastodonContentPost?, actionHandler: MastodonPostMenuActionHandler?) -> ActionBar.ViewModel? {
        guard let actionablePost, let actionHandler, let relationship = viewModel.myRelationshipToAuthor else { return nil }
        return .init(post: actionablePost,
                     actionHandler: actionHandler,
                     replies: actionButtonViewModel(forPost: actionablePost, action: .reply),
                     boosts: actionButtonViewModel(forPost: actionablePost, action: .boost),
                     favourites: actionButtonViewModel(forPost: actionablePost, action: .favourite),
                     bookmark: actionButtonViewModel(forPost: actionablePost, action: .bookmark),
                     isShowingTranslation: viewModel.isShowingTranslation,
                     isDoingAction: viewModel.isDoingAction,
                     myRelationshipToAuthor: relationship)
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
                    viewModel.actionHandler?.doAction(.reply, forPost: actionablePost)
                default:
                    break
                }
            })
        case .boost:
            let state = overrideState ?? AsyncBool.fromBool(myActions.boosted)
            return StatefulCountedActionViewModel(type: .boost, displayDetails: .init(count: metrics.boostCount, isSelected: state), doAction: {
                switch state {
                case .isFalse:
                    viewModel.actionHandler?.doAction(.boost, forPost: actionablePost)
                case .isTrue:
                    viewModel.actionHandler?.doAction(.unboost, forPost: actionablePost)
                default:
                    break
                }
            })
        case .favourite:
            let state = overrideState ?? AsyncBool.fromBool(myActions.favorited)
            return StatefulCountedActionViewModel(type: .favourite, displayDetails: .init(count: metrics.favoriteCount, isSelected: state), doAction: {
                switch state {
                case .isFalse:
                    viewModel.actionHandler?.doAction(.favourite, forPost: actionablePost)
                case .isTrue:
                    viewModel.actionHandler?.doAction(.unfavourite, forPost: actionablePost)
                default:
                    break
                }
            })
        case .bookmark:
            let state = overrideState ?? AsyncBool.fromBool(myActions.bookmarked)
            return StatefulCountedActionViewModel(type: .bookmark, displayDetails: .init(count: nil, isSelected: state), doAction: {
                switch state {
                case .isFalse:
                    viewModel.actionHandler?.doAction(.bookmark, forPost: actionablePost)
                case .isTrue:
                    viewModel.actionHandler?.doAction(.unbookmark, forPost: actionablePost)
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
    
    func goToProfile(_ account: MastodonAccount?) {
        guard let account else { return }
        viewModel.goToProfile(account)
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

struct AttributedStringDisplayInfo {
    let attributedString: AttributedString
    let layoutSizes: [CGSize]
    
    func hasCalculatedForWidth(_ width: CGFloat) -> Bool {
        return layoutSizes.contains(where: { $0.width == floor(width)})
    }
}

@MainActor
class MastodonPostViewModel: ObservableObject {
    
    enum DisplayPrepStatus {
        case unprepared
        case donePreparing
    }
    
    nonisolated let initialDisplayInfo: GenericMastodonPost.InitialDisplayInfo
    
    @Published var fullPost: GenericMastodonPost? = nil
    @Published var myRelationshipToAuthor: MastodonAccount.Relationship? = nil
    @Published var originalContentDisplayInfo: AttributedStringDisplayInfo?
    @Published var translatedContentDisplayInfo: AttributedStringDisplayInfo?

    @Published var displayPrepStatus: DisplayPrepStatus = .unprepared
    @Published var isShowingTranslation: Bool? = nil
    @Published var isDoingAction: MastodonPostMenuAction? = nil
    
    var actionHandler: MastodonPostMenuActionHandler? = nil
    let timestamper: TimestampUpdater = TimestampUpdater.timestamper(withInterval: 30)
    
    private(set) var translation: Mastodon.Entity.Translation? = nil
    
    nonisolated
    init(_ initialDisplay: GenericMastodonPost.InitialDisplayInfo) {
        self.initialDisplayInfo = initialDisplay
    }
    
    private init(_ initialDisplay: GenericMastodonPost.InitialDisplayInfo, fullPost: GenericMastodonPost? = nil, isShowingTranslation: Bool? = nil, isDoingAction: MastodonPostMenuAction? = nil, myRelationshipToAuthor: MastodonAccount.Relationship? = nil, actionHandler: MastodonPostMenuActionHandler? = nil, translation: Mastodon.Entity.Translation? = nil) {
        self.initialDisplayInfo = initialDisplay
    }
    
    func byReplacingActionablePost(with actionablePost: GenericMastodonPost) -> MastodonPostViewModel {
        if let updatedFullPost = try? fullPost?.byReplacingActionablePost(with: actionablePost) {
            return MastodonPostViewModel(initialDisplayInfo, fullPost: updatedFullPost, isShowingTranslation: isShowingTranslation, isDoingAction: isDoingAction, myRelationshipToAuthor: myRelationshipToAuthor, actionHandler: actionHandler, translation: translation)
        } else {
            return self
        }
    }
    
    func hasCalculatedForWidth(_ width: CGFloat) -> Bool {
        if (isShowingTranslation != true) {
         return originalContentDisplayInfo?.hasCalculatedForWidth(width) == true
        }
        return translatedContentDisplayInfo?.hasCalculatedForWidth(width) == true
    }
    
    var altTextTranslations: [String : String]? {
        guard isShowingTranslation == true else { return nil }
        guard let attachmentTranslations = translation?.mediaAttachments else { return nil }
        
        let dictionary = attachmentTranslations.reduce(into: [ String : String]()) { partialResult, attachment in
            partialResult[attachment.id] = attachment.description
        }
        return dictionary
    }
    
    var pollOptionTranslations: [String]? {
        guard isShowingTranslation == true else { return nil }
        guard let pollTranslation = translation?.poll else { return nil }
        return pollTranslation.options.map { $0.title }
    }
    
    func didSelect(meta: Meta?) {
        switch meta {
        case .none:
            guard let actionablePost = fullPost?.actionablePost, let currentUser = AuthenticationServiceProvider.shared.currentActiveUser.value else { return }
            actionHandler?.presentScene(
                .thread(
                    viewModel: ThreadViewModel(
                        authenticationBox: currentUser,
                        optionalRoot: .root(
                            context: .init(
                                status: MastodonStatus(
                                    entity: actionablePost._legacyEntity,
                                    showDespiteContentWarning:
                                        false))))), transition: .show)

 
        case .url(_, _, let url, _),
                .mention(_, let url, _) where url.lowercased().hasPrefix("http"):
            // note:
            // some server mark the normal url as "u-url" class. highlighted content is a URL
            
            // fix non-ascii character URL link can not open issue
            guard let url = URL(string: url) ?? URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url) else {
                assertionFailure()
                return
            }
            actionHandler?.presentScene(.safari(url: url), transition: .safariPresent(animated: true, completion: nil))
            
        case .hashtag(_, let hashtag, _):
            guard let currentUser = AuthenticationServiceProvider.shared.currentActiveUser.value else { return }
            let hashtagTimelineViewModel = HashtagTimelineViewModel(authenticationBox: currentUser, hashtag: hashtag)
            actionHandler?.presentScene(.hashtagTimeline(viewModel: hashtagTimelineViewModel), transition: .show)
            
        case .mention(_, let mention, let userInfo):
            guard
                let href = userInfo?["href"] as? String,
                let url = URL(string: href)
            else {
                return
            }
            let mentions = fullPost?.actionablePost?.content.htmlWithEntities?.mentions
            guard let mention = mentions?.first(where: { $0.url == href }) else {
                actionHandler?.presentScene(.safari(url: url), transition: .safariPresent(animated: true, completion: nil))
                return
            }
            goToProfile(mention)
        default:
            assertionFailure()
            break
        }
    }
    
    func goToProfile(_ account: MastodonAccount) {
        guard let myRelationshipToAuthor else { return }
        switch myRelationshipToAuthor {
        case .isMe:
            let profile: ProfileViewController.ProfileType = .me(account._legacyEntity)
            actionHandler?.presentScene(.profile(profile), transition: .show)
        case .isNotMe(let info):
            if let info, let me = AuthenticationServiceProvider.shared.currentActiveUser.value?.cachedAccount {
                let profile: ProfileViewController.ProfileType = .notMe(me: me, displayAccount: account._legacyEntity, relationship: info._legacyEntity)
                actionHandler?.presentScene(.profile(profile), transition: .show)
            }
        }
    }
    
    func goToProfile(_ mention: Mastodon.Entity.Mention) {
        Task {
            guard let currentUser = AuthenticationServiceProvider.shared.currentActiveUser.value else { return }
            let account = try await APIService.shared.accountInfo(
                domain: currentUser.domain,
                userID:
                    mention.id,
                authorization: currentUser.userAuthorization
            )
            goToProfile(MastodonAccount.fromEntity(account))
        }
    }
}

fileprivate extension MastodonPostViewModel {
    
    var socialContextHeader: SocialContextHeader? {
        guard let fullPost else { return nil }
        if fullPost is MastodonBoostPost {
            // BOOSTED BY
            return .boosted(by: fullPost.metaData.author.displayInfo.displayName, emojis: fullPost.metaData.author.displayInfo.emojis)
        } else if let basicPost = fullPost as? MastodonBasicPost {
            // REPLIED and/or PRIVATE MENTION
            let isPrivate = basicPost.metaData.privacyLevel == .mentionedOnly
            let replyInfo = basicPost.inReplyTo
            if let replyInfo {
                let replyToAccount = actionHandler?.account(replyInfo.accountID)
                return .reply(to: replyToAccount?.displayInfo.displayName ?? "unknown", isPrivate: isPrivate, isNotification: false, emojis: replyToAccount?.displayInfo.emojis ?? [])
            } else if isPrivate {
                return .mention(isPrivate: true)
            }
        }
        return nil
    }

    func textContentView() -> TextViewWithCustomEmoji {
        let emptyTextContent: TextViewWithCustomEmoji = .timelinePost(heightCacheID: "empty", html: "", emojis: TextViewWithCustomEmoji.Emojis(), didSelect: { [weak self] meta in self?.didSelect(meta: meta) })
        
        guard let actionablePost = fullPost?.actionablePost, let untranslatedContent = actionablePost.content.htmlWithEntities?.html else { return emptyTextContent }
        let emojis = actionablePost.content.htmlWithEntities?.emojis ?? TextViewWithCustomEmoji.Emojis()
        
        if isShowingTranslation == true, let translation = actionHandler?.translation(forContentPostId: actionablePost.id)?.content {
            return .timelinePost(heightCacheID: actionablePost.id+"translated", html: translation, emojis: emojis, didSelect: { [weak self] meta in self?.didSelect(meta: meta) })
        } else {
            return .timelinePost(heightCacheID: actionablePost.id, html: untranslatedContent, emojis: emojis, didSelect: { [weak self] meta in self?.didSelect(meta: meta) })
        }
    }

    var hashtagComponent: PostViewComponent? {
        return .hashtags(["needs_implementation"])
    }
}

extension HomeTimelineListViewModel: MastodonPostMenuActionHandler {
    var mediaPreviewableViewController: (any MediaPreviewableViewController)? {
        return hostingViewController
    }
    
    func vote(poll: MastodonSDK.Mastodon.Entity.Poll, choices: [Int], containingPostID: Mastodon.Entity.Status.ID) async throws -> Mastodon.Entity.Poll {
        guard let authenticatedUser else { throw APIService.APIError.explicit(.authenticationMissing) }
        let updatedPoll = try await APIService.shared.vote(poll: poll, choices: choices, authenticationBox: authenticatedUser).value
        let updatedContainingStatus = try await APIService.shared.status(statusID: containingPostID, authenticationBox: authenticatedUser).value
        feedLoader?.updatePost(post: GenericMastodonPost.fromStatus(updatedContainingStatus))
        return updatedPoll
    }
    
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
                    await deletePost(postID, askFirst: UserDefaults.shared.askBeforeDeletingAPost)
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
        
        if translations[post.id] != nil {
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
                let updated = try await APIService.shared.boost(boostableStatusId: actionablePostId, authenticationBox: authenticatedUser) // this returns a new post, which is the boost action
                let updatedActionable = updated.reblog ?? updated // when updating the existing records, we only care about the original post
                feedLoader?.updatePost(post: GenericMastodonPost.fromStatus(updatedActionable))
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
        let activityItems: [Any] = {
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

struct GapLoaderView: View {
    let newerThan: String
    let olderThan: String
    let gapDescription: String
    let loadFromTop: ()->()
    let loadFromBottom: ()->()
    
    var body: some View {
        HStack {
            
            VStack {
                Button {
                    loadFromTop()
                } label: {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.title2)
                        .foregroundStyle(Asset.Colors.accent.swiftUIColor)
                }
                .buttonStyle(.borderless)
                
                Spacer()
                    .frame(minHeight: standardPadding, maxHeight: .infinity)
            }
            
            Spacer()
                .frame(maxWidth: .infinity)
            
            VStack {
                Text(L10n.Common.Controls.Timeline.Loader.loadMissingPosts)
                    .lineLimit(1)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("older than: \(olderThan)")
                    .lineLimit(1)
                    .fixedSize()
                    .font(.footnote)
                Text("newer than: \(newerThan)")
                    .lineLimit(1)
                    .fixedSize()
                    .font(.footnote)
                Text(gapDescription)
                    .font(.subheadline)
                    .fontWeight(.regular)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
                .frame(maxWidth: .infinity)
            
            VStack {
                Spacer()
                    .frame(minHeight: standardPadding, maxHeight: .infinity)
                
                Button {
                    loadFromBottom()
                } label: {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.title2)
                        .foregroundStyle(Asset.Colors.accent.swiftUIColor)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
