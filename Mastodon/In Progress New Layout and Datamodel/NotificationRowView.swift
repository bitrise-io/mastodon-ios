// Copyright © 2025 Mastodon gGmbH. All rights reserved.
import Combine
import MastodonAsset
import MastodonCore
import MastodonLocalization
import MastodonMeta
import MastodonSDK
import MetaTextKit
import SwiftUI

// TODO: all strings need localization


enum AuthorName {
    case me
    case other(named: String)

    var string: String {
        switch self {
        case .me:
            return "You"
        case .other(let name):
            return name
        }
    }
}

extension GroupedNotificationType {
    
    enum MainIconStyle {
        case icon(name: String, color: Color)
        case avatar
    }
    
    func mainIconStyle(
        grouped: Bool
    ) -> MainIconStyle? {
        switch self {
        case .mention, .status:
            return .avatar
        default:
            if let iconName = iconSystemName(grouped: grouped) {
                return .icon(name: iconName, color: iconColor)
            }
        }
        return nil
    }

    func iconSystemName(
        grouped: Bool = false
    ) -> String? {
        switch self {
        case .favourite:
            return "star.fill"
        case .reblog:
            return "arrow.2.squarepath"
        case .follow:
            if grouped {
                return "person.2.badge.plus.fill"
            } else {
                return "person.fill.badge.plus"
            }
        case .poll:
            return "chart.bar.yaxis"
        case .adminReport:
            return "info.circle"
        case .severedRelationships:
            return "person.badge.minus"
        case .moderationWarning:
            return "exclamationmark.shield.fill"
        case ._other:
            return "questionmark.square.dashed"
        case .mention:
            return nil  // should show avatar
        case .status:
            return nil  // should show avatar
        case .followRequest:
            return "person.fill.badge.plus"
        case .update:
            return "pencil"
        case .adminSignUp:
            return nil
        }
    }

    var iconColor: Color {
        switch self {
        case .favourite:
            return .orange
        case .reblog:
            return .green
        case .follow, .followRequest, .status, .mention, .update:
            return Color(asset: Asset.Colors.accent)
        case .poll, .severedRelationships, .moderationWarning, .adminReport,
            .adminSignUp:
            return .secondary
        case ._other:
            return .gray
        }
    }
    
    var wantsFullStatusLayout: Bool {
        switch self {
        case .status, .mention:
            return true
        default:
            return false
        }
    }

    func actionSummaryLabel(_ sourceAccounts: NotificationSourceAccounts)
        -> AttributedString?
    {
        guard let authorName = sourceAccounts.authorName else { return nil }
        let totalAuthorCount = sourceAccounts.totalActorCount
        switch authorName {
        case .me:
            assert(totalAuthorCount == 1)
            //assert(self == .poll)
            return AttributedString(L10n.Scene.Notification.GroupedNotificationDescription.yourPollHasEnded)
        case .other(let firstAuthorName):
            var plainString: String
            if totalAuthorCount == 1 {
                switch self {
                case .favourite:
                    plainString = L10n.Scene.Notification.GroupedNotificationDescription.singleNameFavourited(firstAuthorName)
                case .follow:
                    plainString = L10n.Scene.Notification.GroupedNotificationDescription.singleNameFollowedYou(firstAuthorName)
                case .followRequest:
                    plainString = L10n.Scene.Notification.GroupedNotificationDescription.singleNameRequestedToFollowYou(firstAuthorName)
                case .reblog:
                    plainString = L10n.Scene.Notification.GroupedNotificationDescription.singleNameBoosted(firstAuthorName)
                case .mention:
                    plainString = L10n.Scene.Notification.GroupedNotificationDescription.singleNameMentionedYou(firstAuthorName)
                case .poll(let status):
                    let votersCount = status?.poll?.votersCount ?? 0
                    let pollDescription = L10n.Plural.Count.pollThatYouAndOthersVotedIn(votersCount)
                    plainString = L10n.Scene.Notification.GroupedNotificationDescription.singleNameRanPoll(firstAuthorName, pollDescription)
                case .status:
                    plainString = L10n.Scene.Notification.GroupedNotificationDescription.singleNamePosted(firstAuthorName)
                case .adminSignUp:
                    plainString = L10n.Scene.Notification.GroupedNotificationDescription.singleNameSignedUp(firstAuthorName)
                default:
                    plainString = "\(firstAuthorName) did something"
                }
            } else {
                let actorsList = sourceAccounts.authorsDescription ?? firstAuthorName
                switch self {
                case .favourite:
                    plainString = L10n.Scene.Notification.GroupedNotificationDescription.multiplePeopleFavourited(actorsList)
                case .follow:
                    plainString = L10n.Scene.Notification.GroupedNotificationDescription.multiplePeopleFollowedYou(actorsList)
                case .reblog:
                    plainString = L10n.Scene.Notification.GroupedNotificationDescription.multiplePeopleBoosted(actorsList)
                default:
                    plainString = "\(actorsList) did something"
                }
            }
            
            var composedString = AttributedString(plainString)
            if let range = composedString.range(of: firstAuthorName) {
                let authorNameComponent = stylableNameComponent(firstAuthorName)
                composedString.replaceSubrange(range, with: authorNameComponent)
                let nameStyling = AttributeContainer.font(
                    .system(.body, weight: .bold))
                let nameContainer = AttributeContainer.personNameComponent(
                    .givenName)
                composedString.replaceAttributes(nameContainer, with: nameStyling)
            }
            return composedString
        }
    }
}

extension Mastodon.Entity.Report {
    // TODO: localization (inc. plurals)
    // "Someone reported X posts from someone else for rule violation"
    var summary: AttributedString {
        if let targetedAccountName = targetAccount?.displayNameWithFallback {
            let boldedName = stylableNameComponent(targetedAccountName)
            if let postCount = flaggedStatusIDs?.count {
                return AttributedString(
                    "Someone reported \(postCount) posts from ") + boldedName
                    + AttributedString(" for rule violation.")
            } else {
                return AttributedString("Someone reported ") + boldedName
                    + AttributedString(" for rule violation.")
            }
        } else {
            return AttributedString("RULE VIOLATION REPORT")
        }
    }
    var displayableComment: AttributedString? {
        if let comment {
            return AttributedString(comment)
        } else {
            return nil
        }
    }
}

var listFormatter = ListFormatter()

extension Mastodon.Entity.RelationshipSeveranceEvent {
    // "An admin from <your.domain> has blocked <some other domain>, including x of your followers and y accounts you follow."

    func summary(myDomain: String) -> AttributedString? {
        let lostFollowersString =
            followersCount > 0
            ? L10n.Plural.Count.ofYourFollowers(followersCount) : nil
        let lostFollowingString =
            followingCount > 0
            ? L10n.Plural.Count.accountsThatYouFollow(followingCount) : nil

        guard
            let followersAndFollowingString = listFormatter.string(
                from: [lostFollowersString, lostFollowingString].compactMap {
                    $0
                })
        else {
            return nil
        }

        let string = L10n.Scene.Notification.NotificationDescription
            .relationshipSeveranceEvent(
                myDomain, targetName, followersAndFollowingString)

        var attributed = AttributedString(string)
        attributed.bold([myDomain, targetName])
        return attributed
    }
}

private let avatarShape = RoundedRectangle(cornerRadius: 8)


struct AvatarView: View {
    
    @State var isNavigating: Bool = false
    
    let author: AccountInfo
    let goToProfile: ((AccountInfo) async throws -> ())?
    
    var body: some View {
        ZStack {
            AsyncImage(
                url: author.avatarURL,
                content: { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(avatarShape)
                        .overlay {
                            avatarShape.stroke(.separator)
                        }
                },
                placeholder: {
                    avatarShape
                        .foregroundStyle(
                            Color(UIColor.secondarySystemFill))
                }
            )
            
            if isNavigating {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(width: 30)
            }
        }
        .onTapGesture {
            if let goToProfile, !isNavigating {
                Task {
                    do {
                        isNavigating = true
                        try await goToProfile(author)
                    } catch {
                    }
                    isNavigating = false
                }
            }
        }
    }
}

private let iconViewSize: CGFloat = 44

@ViewBuilder
func NotificationIconView(_ style: GroupedNotificationType.MainIconStyle) -> some View {
    HStack {
        switch style {
        case .icon(let name, let color):
            Image(systemName: name)
                .foregroundStyle(color)
        case .avatar:
            Image(systemName: "xmark")
                .foregroundStyle(.red)
        }
    }
    .font(.system(size: 25))
    .frame(width: iconViewSize)
    .fontWeight(.semibold)
}

@ViewBuilder
func NotificationIconView(systemName: String) -> some View {
    HStack {
        Image(
            systemName: systemName
        )
        .foregroundStyle(.secondary)
    }
    .font(.system(size: 25))
    .frame(width: iconViewSize)
    .fontWeight(.semibold)
}

enum RelationshipElement: Equatable {
    case noneNeeded
    case unfetched(GroupedNotificationType)
    case fetching
    case error(Error?)
    case iDoNotFollowThem(theirAccountIsLocked: Bool)
    case iFollowThem(theyFollowMe: Bool)
    case iHaveRequestedToFollowThem
    case theyHaveRequestedToFollowMe(iFollowThem: Bool)
    case iHaveAnsweredTheirRequestToFollowMe(didAccept: Bool)

    enum FollowAction {
        case follow
        case unfollow
        case noAction
    }

    var description: String {
        switch self {
        case .noneNeeded:
            return "noneNeeded"
        case .unfetched:
            return "unfetched"
        case .fetching:
            return "fetching"
        case .error:
            return "error"
        case .iDoNotFollowThem(let theirAccountIsLocked):
            if theirAccountIsLocked {
                return "iDoNotFollowThem+canRequestToFollow"
            } else {
                return "iDoNotFollowThem+canFollow"
            }
        case .theyHaveRequestedToFollowMe(let iFollowThem):
            if iFollowThem {
                return "theyHaveRequestedToFollowMe+iFollowThem"
            } else {
                return "theyHaveRequestedToFollowMe+iDoNotFollowThem"
            }
        case .iHaveAnsweredTheirRequestToFollowMe(let didAccept):
            if didAccept {
                return "iAcceptedTheirFollowRequest"
            } else {
                return "iRejectedTheirFollowRequest"
            }
        case .iFollowThem(let theyFollowMe):
            if theyFollowMe {
                return "iFollowThem+theyFollowMe"
            } else {
                return "iFollowThem+theyDoNotFollowMe"
            }
        case .iHaveRequestedToFollowThem:
            return "iHaveRequestedToFollowThem"
        }
    }

    static func == (lhs: RelationshipElement, rhs: RelationshipElement) -> Bool
    {
        return lhs.description == rhs.description
    }

    var followAction: FollowAction {
        switch self {
        case .iDoNotFollowThem:
            return .follow
        case .iFollowThem, .iHaveRequestedToFollowThem:
            return .unfollow
        default:
            return .noAction
        }
    }

    var buttonText: String? {
        switch self {
        case .iDoNotFollowThem(let theirAccountIsLocked):
            if theirAccountIsLocked {
                return L10n.Common.Controls.Friendship.request
            } else {
                return L10n.Common.Controls.Friendship.follow
            }
        case .iFollowThem(let theyFollowMe):
            if theyFollowMe {
                return L10n.Common.Controls.Friendship.mutual
            } else {
                return L10n.Common.Controls.Friendship.following
            }
        case .iHaveRequestedToFollowThem:
            return L10n.Common.Controls.Friendship.pending
        default:
            return nil
        }
    }
}

extension Mastodon.Entity.Relationship {
    @MainActor
    var relationshipElement: RelationshipElement? {
        switch (following, followedBy) {
        case (true, _):
            return .iFollowThem(theyFollowMe: followedBy)
        case (false, true):
            if let account: AccountInfo = MastodonFeedItemCacheManager
                .shared.fullAccount(id)
                ?? MastodonFeedItemCacheManager.shared.partialAccount(id),
                account.locked
            {
                if requested {
                    return .iHaveRequestedToFollowThem
                } else {
                    return .iDoNotFollowThem(theirAccountIsLocked: true)
                }
            }
            return .iDoNotFollowThem(theirAccountIsLocked: false)
        case (false, false):
            return nil
        }
    }
}


struct NotificationSourceAccounts {
    let accounts: [AccountInfo]
    let totalActorCount: Int
    let authorName: AuthorName?
    
    var primaryAuthorAccount: Mastodon.Entity.Account? {
        return accounts.first?.fullAccount
    }
    var firstAccountID: String? {
        return primaryAuthorAccount?.id
    }
    var avatarUrls: [URL] {
        return accounts.compactMap({ $0.avatarURL }).removingDuplicates()
    }

    init(
        myAccountID: String,
        accounts: [AccountInfo],
        totalActorCount: Int
    ) {
        self.accounts = accounts
        self.totalActorCount = totalActorCount
        self.authorName = accounts.first?.displayName(whenViewedBy: myAccountID)
    }
}

struct FilteredNotificationsRowView: View {
    class ViewModel: ObservableObject {
        var policy: Mastodon.Entity.NotificationPolicy? = nil {
            didSet {
                update(policy: policy)
            }
        }
        @Published var isPreparingToNavigate: Bool = false
        @Published var componentViews: [NotificationViewComponent] = []
        var shouldShow: Bool = false

        init(policy: Mastodon.Entity.NotificationPolicy?) {
            if let policy {
                self.policy = policy
            }
        }

        private func update(policy: Mastodon.Entity.NotificationPolicy?) {
            guard let policy else {
                shouldShow = false
                return
            }
            componentViews = [
                .weightedText(
                    L10n.Scene.Notification.FilteredNotification.title, .bold),
                .weightedText(
                    L10n.Plural.FilteredNotificationBanner.subtitle(
                        policy.summary.pendingRequestsCount), .regular),
            ]
            shouldShow = policy.summary.pendingRequestsCount > 0
        }
    }

    @ObservedObject var viewModel: ViewModel

    init(_ viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        HStack {
            // LEFT GUTTER WITH TOP-ALIGNED ICON
            VStack {
                Spacer()
                NotificationIconView(systemName: "archivebox")
                Spacer().frame(maxHeight: .infinity)
            }

            // TEXT COMPONENTS
            VStack {
                ForEach(viewModel.componentViews) { component in
                    switch component {
                    case .weightedText(let string, let weight):
                        textComponent(string, fontWeight: weight)
                    default:
                        textComponent(component.id, fontWeight: .light)
                    }
                }
            }

            // DISCLOSURE INDICATOR (OR SPINNER)
            VStack {
                Spacer()
                if viewModel.isPreparingToNavigate {
                    ProgressView().progressViewStyle(.circular)
                } else {
                    Image(systemName: "chevron.forward")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 20))
                        .fontWeight(.light)
                }
                Spacer().frame(maxHeight: .infinity)
            }
            .frame(width: 44)
        }
    }
}

let actionSuperheaderHeight: CGFloat = 20

struct NotificationRowView: View {
    @ObservedObject var viewModel: NotificationRowViewModel

    var body: some View {
        HStack(alignment: .top) {
            if let iconStyle = viewModel.iconStyle {
                // LEFT GUTTER WITH TOP-ALIGNED ICON or AVATAR
                VStack(spacing: 4) {
                    if let actionSuperheader = viewModel.actionSuperheader {
                        HStack {
                            Spacer()
                            Image(systemName: actionSuperheader.iconName)
                                .font(.subheadline)
                                .bold()
                                .foregroundStyle(actionSuperheader.color)
                                .frame(height: actionSuperheaderHeight)
                        }
                    }
                    
                    switch iconStyle {
                    case .icon:
                        NotificationIconView(iconStyle)
                    case .avatar:
                        if let author = viewModel.author {
                            AvatarView(author: author, goToProfile: viewModel.navigateToProfile(_:))
                                .frame(width: iconViewSize, height: iconViewSize)
                        }
                    }
                    Spacer().frame(maxHeight: .infinity)
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            // VSTACK OF HEADER AND CONTENT COMPONENT VIEWS
            VStack(spacing: 4) {
                if let actionSuperheader = viewModel.actionSuperheader {
                    componentView(.weightedText(actionSuperheader.text, .bold))
                        .font(.subheadline)
                        .foregroundColor(actionSuperheader.color)
                        .frame(height: actionSuperheaderHeight)
                }
                
                ForEach(viewModel.headerComponents) {
                    componentView($0)
                }

                if !viewModel.contentComponents.isEmpty {
                    Spacer().frame(height: 2)
                }

                ForEach(viewModel.contentComponents) {
                    componentView($0)
                }
            }
        }
    }

    @ViewBuilder
    func componentView(_ component: NotificationViewComponent) -> some View {
        switch component {
        case .avatarRow(let accountInfo, let addition):
            avatarRow(accountInfo: accountInfo, trailingElement: addition)
        case .text(let string):
            Text(string)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .weightedText(let string, let weight):
            textComponent(string, fontWeight: weight)
        case .status(let statusViewModel):
            InlinePostPreview(viewModel: statusViewModel, showAttributionHeader: !viewModel.type.wantsFullStatusLayout)
                .onTapGesture {
                    statusViewModel.navigateToStatus()
                }
        case .hyperlinkButton(let label, let url):
            Button(label) {
                if let url {
                    UIApplication.shared.open(url)
                }
            }
            .bold()
            .tint(Color(asset: Asset.Colors.accent))
        case ._other(let string):
            Text(string)
        }
    }

    func displayableAvatarCount(
        fittingWidth: CGFloat, totalAvatarCount: Int, totalActorCount: Int
    ) -> Int {
        let maxAvatarCount = Int(
            floor(fittingWidth / (smallAvatarSize + avatarSpacing)))
        return maxAvatarCount
    }

    @ScaledMetric private var smallAvatarSize: CGFloat = 32
    private let avatarSpacing: CGFloat = 8

    @ViewBuilder
    func avatarRow(
        accountInfo: NotificationSourceAccounts,
        trailingElement: RelationshipElement
    ) -> some View {
        GeometryReader { geom in
            let maxAvatarCount = displayableAvatarCount(
                fittingWidth: geom.size.width,
                totalAvatarCount: accountInfo.avatarUrls.count,
                totalActorCount: accountInfo.totalActorCount)
            HStack(alignment: .center) {
                ForEach(
                    accountInfo.accounts.prefix(maxAvatarCount), id: \.self.id
                ) { account in
                    AvatarView(author: account, goToProfile: viewModel.navigateToProfile(_:))
                    .frame(width: smallAvatarSize, height: smallAvatarSize)
                    .onTapGesture {
                        Task {
                            try await viewModel.navigateToProfile(account)
                        }
                    }
                }
                Spacer().frame(minWidth: 0, maxWidth: .infinity)
                avatarRowTrailingElement(
                    trailingElement, grouped: accountInfo.totalActorCount > 1)
            }
        }
        .frame(height: smallAvatarSize)  // this keeps GeometryReader from causing inconsistent visual spacing in the VStack
    }

    @ViewBuilder
    func avatarRowTrailingElement(
        _ elementType: RelationshipElement, grouped: Bool
    ) -> some View {
        switch (elementType, grouped) {
        case (.fetching, false):
            ProgressView().progressViewStyle(.circular)
        case (.iDoNotFollowThem, false), (.iFollowThem, false),
            (.iHaveRequestedToFollowThem, false):
            if let buttonText = elementType.buttonText {
                Button(buttonText) {
                    viewModel.doAvatarRowButtonAction()
                }
                .buttonStyle(FollowButton(elementType))
            }
        case (.theyHaveRequestedToFollowMe(let iFollowThem), false):
            HStack {

                if iFollowThem {
                    Button(L10n.Common.Controls.Friendship.following) {
                        // TODO: allow unfollow here?
                    }
                    .buttonStyle(
                        FollowButton(.iFollowThem(theyFollowMe: false))
                    )
                    .fixedSize()
                }

                Button(action: {
                    viewModel.doAvatarRowButtonAction(false)
                }) {
                    lightwieghtImageView("xmark.circle", size: smallAvatarSize)
                }
                .buttonStyle(
                    ImageButton(
                        foregroundColor: .secondary, backgroundColor: .clear))

                Button(action: {
                    viewModel.doAvatarRowButtonAction(true)
                }) {
                    lightwieghtImageView(
                        "checkmark.circle", size: smallAvatarSize)
                }
                .buttonStyle(
                    ImageButton(
                        foregroundColor: .secondary, backgroundColor: .clear))
            }
        case (.iHaveAnsweredTheirRequestToFollowMe(let didAccept), false):
            if didAccept {
                lightwieghtImageView("checkmark", size: smallAvatarSize)
            } else {
                lightwieghtImageView("xmark", size: smallAvatarSize)
            }
        case (.error(_), _):
            lightwieghtImageView(
                "exclamationmark.triangle", size: smallAvatarSize)
        default:
            Spacer().frame(width: 0)
        }
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

enum NotificationViewComponent: Identifiable {
    case avatarRow(NotificationSourceAccounts, RelationshipElement)
    case text(AttributedString)
    case weightedText(String, SwiftUICore.Font.Weight)
    case status(Mastodon.Entity.Status.ViewModel)
    case hyperlinkButton(String, URL?)
    case _other(String)

    var id: String {
        switch self {
        case .avatarRow:
            return "avatar_row"
        case .text(let string):
            return string.description
        case .weightedText(let string, _):
            return string
        case .status:
            return "status"
        case .hyperlinkButton(let text, _):
            return text
        case ._other(let string):
            return string
        }
    }
}

func stylableNameComponent(_ name: String) -> AttributedString {
    let nameComponent = PersonNameComponents(givenName: name).formatted(
        .name(style: .long).attributed)
    return nameComponent
}

let metaTextForHtmlToAttributedStringConversion = {
    let meta = MetaText()
    meta.textAttributes = [:]
    meta.linkAttributes = [:]
    return meta
}()
func attributedString(
    fromHtml html: String, emojis: [MastodonContent.Shortcode: String]
) -> AttributedString {
    let content = MastodonContent(content: html, emojis: emojis)
    metaTextForHtmlToAttributedStringConversion.reset()
    do {
        let metaContent = try MastodonMetaContent.convert(document: content)
        metaTextForHtmlToAttributedStringConversion.configure(
            content: metaContent)
        guard
            let nsAttributedString = metaTextForHtmlToAttributedStringConversion
                .textView.attributedText
        else {
            throw AppError.unexpected(
                "could not get attributed string from html")
        }
        return AttributedString(nsAttributedString)
    } catch {
        return AttributedString(html)
    }
}

extension Mastodon.Entity.Status {
    public enum AttachmentSummaryInfo {
        case image(Int)
        case gifv(Int)
        case video(Int)
        case audio(Int)
        case generic(Int)
        case poll

        var count: Int {
            switch self {
            case .image(let count), .gifv(let count), .video(let count),
                .audio(let count), .generic(let count):
                return count
            case .poll:
                return 1
            }
        }

        var iconName: String {
            switch self {
            case .image(1):
                return "photo"
            case .image(2):
                return "photo.on.rectangle"
            case .image:
                return "photo.stack"
            case .gifv, .video:
                return "play.tv"
            case .audio:
                return "speaker.wave.2"
            case .generic(1):
                return "rectangle"
            case .generic(2):
                return "rectangle.on.rectangle"
            case .generic:
                return "rectangle.stack"
            case .poll:
                return "chart.bar.yaxis"
            }
        }

        var labelText: String {
            switch self {
            case .image(let count):
                return L10n.Plural.Count.image(count)
            case .gifv(let count):
                return L10n.Plural.Count.gif(count)
            case .video(let count):
                return L10n.Plural.Count.video(count)
            case .audio(let count):
                return L10n.Plural.Count.audio(count)
            case .generic(let count):
                return L10n.Plural.Count.attachment(count)
            case .poll:
                return L10n.Plural.Count.poll(1)
            }
        }

        private func withUpdatedCount(_ newCount: Int) -> AttachmentSummaryInfo
        {
            switch self {
            case .image:
                return .image(newCount)
            case .gifv:
                return .gifv(newCount)
            case .video:
                return .video(newCount)
            case .audio:
                return .audio(newCount)
            case .generic:
                return .generic(newCount)
            case .poll:
                return .poll
            }
        }

        private func _adding(_ otherAttachmentInfo: AttachmentSummaryInfo)
            -> AttachmentSummaryInfo
        {
            switch (self, otherAttachmentInfo) {
            case (.poll, _), (_, .poll):
                assertionFailure(
                    "did not expect poll to co-occur with another attachment type"
                )
                return .poll
            case (.gifv, .gifv), (.image, .image), (.video, .video),
                (.audio, .audio):
                return withUpdatedCount(count + otherAttachmentInfo.count)
            default:
                return .generic(count + otherAttachmentInfo.count)
            }
        }

        func adding(attachment: Mastodon.Entity.Attachment)
            -> AttachmentSummaryInfo
        {
            return _adding(AttachmentSummaryInfo(attachment))
        }

        init(_ attachment: Mastodon.Entity.Attachment) {
            switch attachment.type {
            case .image:
                self = .image(1)
            case .gifv:
                self = .gifv(1)
            case .video:
                self = .video(1)
            case .audio:
                self = .audio(1)
            case .unknown, ._other:
                self = .generic(1)
            }
        }
    }
}

extension Mastodon.Entity.Status {
    public struct ViewModel {
        public let content: AttributedString?
        public let visibility: Mastodon.Entity.Status.Visibility?
        public let isReplyToMe: Bool
        public let isPinned: Bool
        public let accountDisplayName: String?
        public let accountFullName: String?
        public let accountAvatarUrl: URL?
        public var needsUserAttribution: Bool {
            return accountDisplayName != nil || accountFullName != nil
        }
        public let attachmentInfo: AttachmentSummaryInfo?
        public let navigateToStatus: () -> Void
    }

    public func viewModel(
        myAccountID: String, myDomain: String, navigateToStatus: @escaping () -> Void
    ) -> ViewModel {
        let displayableContent: AttributedString
        if let content {
            displayableContent = attributedString(
                fromHtml: content, emojis: account.emojis.asDictionary)
        } else {
            displayableContent = AttributedString()
        }
        let accountFullName =
            account.domain == myDomain ? account.acct : account.acctWithDomain
        let attachmentInfo = mediaAttachments?.reduce(
            nil,
            {
                (
                    partialResult: AttachmentSummaryInfo?,
                    attachment: Mastodon.Entity.Attachment
                ) in
                if let partialResult = partialResult {
                    return partialResult.adding(attachment: attachment)
                } else {
                    return AttachmentSummaryInfo(attachment)
                }
            })

        let pollInfo: AttachmentSummaryInfo? = poll != nil ? .poll : nil

        return ViewModel(
            content: displayableContent, visibility: visibility,
            isReplyToMe: inReplyToAccountID == myAccountID,
            isPinned: false,
            accountDisplayName: account.displayName,
            accountFullName: accountFullName,
            accountAvatarUrl: account.avatarImageURL(),
            attachmentInfo: attachmentInfo ?? pollInfo,
            navigateToStatus: navigateToStatus)
    }
}

struct FollowButton: ButtonStyle {
    private let followAction: RelationshipElement.FollowAction

    init(_ relationshipElement: RelationshipElement) {
        followAction = relationshipElement.followAction
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding([.horizontal], 12)
            .padding([.vertical], 4)
            .background(backgroundColor)
            .foregroundStyle(textColor)
            .controlSize(.small)
            .fontWeight(fontWeight)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch followAction {
        case .follow:
            return Color(uiColor: Asset.Colors.Button.userFollow.color)
        case .unfollow:
            return Color(uiColor: Asset.Colors.Button.userFollowing.color)
        case .noAction:
            assertionFailure()
            return .clear
        }
    }

    private var textColor: Color {
        switch followAction {
        case .follow:
            return .white
        case .unfollow:
            return Color(uiColor: Asset.Colors.Button.userFollowingTitle.color)
        case .noAction:
            assertionFailure()
            return .clear
        }
    }

    private var fontWeight: SwiftUICore.Font.Weight {
        switch followAction {
        case .follow:
            return .regular
        case .unfollow:
            return .light
        case .noAction:
            assertionFailure()
            return .regular
        }
    }
}

struct ImageButton: ButtonStyle {

    let foregroundColor: Color
    let backgroundColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .clipShape(Capsule())
    }
}

@ViewBuilder func lightwieghtImageView(_ systemName: String, size: CGFloat)
    -> some View
{
    Image(systemName: systemName)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .fontWeight(.light)
        .frame(width: size, height: size)
}

extension AttributedString {
    mutating func bold(_ substrings: [String]) {
        let boldedRanges = substrings.map {
            self.range(of: $0)
        }.compactMap { $0 }
        for range in boldedRanges {
            self[range].font = .system(.body).bold()
        }
    }
}
