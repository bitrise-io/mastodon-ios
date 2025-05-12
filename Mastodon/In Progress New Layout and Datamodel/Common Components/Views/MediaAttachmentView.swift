// Copyright © 2025 Mastodon gGmbH. All rights reserved.

import SwiftUI
import MastodonSDK
import MastodonCore
import MastodonLocalization

let buttonBackgroundColor = Color.black.opacity(0.6)
let maxHeightForHiddenMedia: CGFloat = 100

struct MastodonImageAttachment: Identifiable {
    let id: Mastodon.Entity.Attachment.ID
    let basicData: MastodonAttachmentBasicData
    let imageDetails: ImageAttachmentDetails
    
    init?(_ entity: Mastodon.Entity.Attachment) {
        id = entity.id
        switch entity.type {
        case .image:
            guard let meta = entity.meta else { return nil }
            basicData = MastodonAttachmentBasicData(entity)
            imageDetails = ImageAttachmentDetails(meta)
        default:
            return nil
        }
    }
}

struct MastodonAttachmentBasicData {
    let id: Mastodon.Entity.Attachment.ID
    let fullsizeUrl: URL?
    let previewUrl: URL?
    let remoteUrl: URL?  // null if the attachment is local
    let altText: String?
    let blurhash: String?
    
    init(_ entity: Mastodon.Entity.Attachment) {
        id = entity.id
        func url(nullableString: String?) -> URL? {
            guard let string = nullableString else { return nil }
            return URL(string: string)
        }
        fullsizeUrl = url(nullableString: entity.url)
        previewUrl = url(nullableString:entity.previewURL)
        remoteUrl = url(nullableString:entity.remoteURL)
        altText = entity.description
        blurhash = entity.blurhash
    }
}

extension CGSize {
    static func fromFormat(_ format: Mastodon.Entity.Attachment.Meta.Format) -> CGSize? {
        guard let width = format.width, let height = format.height else { return nil }
        return CGSize(width: Double(width), height: Double(height))
    }
    
    var aspectRatio: CGFloat {
        guard width > 0, height > 0 else { return 1 }
        return width / height
    }
}

struct ImageAttachmentDetails {
    
    let originalSize: CGSize?
    let smallSize: CGSize?
    let focusPercentOffCenterX: CGFloat?  // value between -1(left) and 1(right)
    let focusPercentOffCenterY: CGFloat?  // value between -1(bottom) and 1(top)
    
    init(_ meta: Mastodon.Entity.Attachment.Meta) {
        if let originalSizeFormat = meta.original {
            originalSize = CGSize.fromFormat(originalSizeFormat)
        } else {
            originalSize = nil
        }
        
        if let smallSizeFormat = meta.small {
            smallSize = CGSize.fromFormat(smallSizeFormat)
        } else {
            smallSize = nil
        }
        
        if let focus = meta.focus {
            focusPercentOffCenterX = focus.x
            focusPercentOffCenterY = focus.y
        } else {
            focusPercentOffCenterX = nil
            focusPercentOffCenterY = nil
        }
    }
}

enum MediaAttachmentView {
    case images([MastodonImageAttachment], altTextTranslations: [String : String]?)
    case notYetImplemented(String)
    case emptyAttachment
    
    init(_ media: [Mastodon.Entity.Attachment], altTextTranslations: [String : String]?) {
        switch media.first?.type {
        case .none:
            self = .emptyAttachment
        case .image:
            let images = media.map { attachment in
                MastodonImageAttachment(attachment)
            }.compactMap { $0 }
            self = .images(images, altTextTranslations: altTextTranslations)
        case .gifv:
            self = .notYetImplemented("gifv")
        case .video:
            self = .notYetImplemented("video")
        case .audio:
            self = .notYetImplemented("audio")
            
        case ._other(let string):
            self = .notYetImplemented(string)
        case .unknown:
            self = .notYetImplemented("UNKNOWN")
        }
    }
}

extension MediaAttachmentView {
    @ViewBuilder func view(withContentConcealModel contentConceal: ContentConcealViewModel, showAltText: @escaping(String)->()) -> some View {
        switch self {
        case .emptyAttachment:
            Image(systemName: "questionmark.square.dashed")
        case .images(let attachments, let altTextTranslations):
            ImageGridView(viewModel: ImageGridViewModel(imageAttachments: attachments, contentConcealViewModel: contentConceal, altTextTranslations: altTextTranslations, showAltText: showAltText))
        case .notYetImplemented(let string):
            Text("Needs Implementation (\(string))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct ImageGridView: View {
    @ObservedObject var viewModel: ImageGridViewModel
    
    var body: some View {
        ZStack(alignment: .topTrailing) { // places the Hide/Show button, if there is one
            
            // The images
            ProportionalImageGridLayout(spacing: 1, aspectRatios: viewModel.imageAttachments.compactMap(\.imageDetails.originalSize?.aspectRatio), canUseTwoRows: !viewModel.useRestrictedHeight) {
                ForEach(viewModel.imageAttachments) { img in
                    ZStack(alignment: .bottomLeading) { // places the ALT text button
                        BlurhashImageView(imageAttachment: img, viewModel: viewModel)
                            .clipped()
                            .accessibilityLabel(viewModel.altTextTranslations?[img.id] ?? img.basicData.altText ?? "")
                        
                        if let altText = img.basicData.altText, altText.isNotEmpty {
                            Button {
                                if let translation = viewModel.altTextTranslations?[img.id] {
                                    viewModel.showAltText(translation)
                                } else {
                                    viewModel.showAltText(altText)
                                }
                            } label: {
                                Text("ALT")
                                    .foregroundStyle(.white)
                                    .padding(EdgeInsets(top: ButtonPadding.vertical, leading: ButtonPadding.horizontal, bottom: ButtonPadding.vertical, trailing: ButtonPadding.horizontal))
                                    .background() {
                                        RoundedRectangle(cornerRadius: CornerRadius.small)
                                            .fill(buttonBackgroundColor)
                                    }
                            }
                            .fixedSize()
                            .padding(standardPadding)
                            .buttonStyle(.borderless)
                            .accessibilityHidden(true)
                        }
                    }
                    .frame(maxHeight: viewModel.useRestrictedHeight ? maxHeightForHiddenMedia : nil)
                }
            }
            .frame(maxHeight: viewModel.useRestrictedHeight ? maxHeightForHiddenMedia : nil)
            .cornerRadius(CornerRadius.standard)
            .animation(.easeInOut, value: viewModel.contentConcealViewModel.currentMode.isShowingMedia)
            
            // Hide/Show button
            switch viewModel.contentConcealViewModel.currentMode {
            case .neverConceal, .concealAll:
                EmptyView()
            case .concealMediaOnly(let showAnyway):
                Button {
                    if showAnyway {
                        viewModel.contentConcealViewModel.hide()
                    } else {
                        viewModel.contentConcealViewModel.showMore()
                    }
                } label: {
                    Text(showAnyway ? L10n.Common.Controls.Status.Actions.hide : L10n.Common.Controls.Status.Actions.show)
                        .foregroundStyle(.white)
                        .padding(EdgeInsets(top: ButtonPadding.vertical, leading: ButtonPadding.capsuleHorizontal, bottom: ButtonPadding.vertical, trailing: ButtonPadding.capsuleHorizontal))
                        .background() {
                            Capsule()
                                .fill(buttonBackgroundColor)
                        }
                }
                .fixedSize()
                .buttonStyle(.borderless)
                .padding(standardPadding)
            }
        }
    }
}

struct BlurhashImageView: View {
    let imageAttachment: MastodonImageAttachment
    @ObservedObject var viewModel: ImageGridViewModel
    
    var body: some View {
        ZStack {
            if let blurhash = viewModel.blurhashes[imageAttachment.id] {
                Image(uiImage: blurhash)
                    .resizable()
                    .scaledToFill()
            }
            
            if let url = imageAttachment.basicData.fullsizeUrl {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        EmptyView() // show blurhash behind
                    case .success(let image):
                        switch viewModel.contentConcealViewModel.currentMode {
                        case .neverConceal, .concealMediaOnly(showAnyway: true), .concealAll(_, showAnyway: true):
                            image
                                .resizable()
                                .scaledToFill()
                                .onAppear() {
                                    if !viewModel.atLeastOneImageLoaded {
                                        viewModel.atLeastOneImageLoaded = true
                                    }
                                }
                        default:
                            EmptyView()
                        }
                    case .failure:
                        Image(systemName: "photo.badge.exclamationmark")
                            .tint(.secondary)
                            .opacity(0.5)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
    }
}

class ImageGridViewModel: ObservableObject {
    let imageAttachments: [MastodonImageAttachment]
    let altTextTranslations: [String : String]?
    @Published var atLeastOneImageLoaded = false
    @Published var blurhashes = [ Mastodon.Entity.Attachment.ID : UIImage ]()
    @ObservedObject var contentConcealViewModel: ContentConcealViewModel
    let showAltText: (String)->()
    
    init(imageAttachments: [MastodonImageAttachment], contentConcealViewModel: ContentConcealViewModel, altTextTranslations: [String: String]?, showAltText: @escaping (String)->()) {
        self.imageAttachments = imageAttachments
        self.contentConcealViewModel = contentConcealViewModel
        self.altTextTranslations = altTextTranslations
        self.showAltText = showAltText
        loadBlurhashes()
    }
    
    private func loadBlurhashes() {
        Task {
            for imageData in imageAttachments {
                if let blurhash = imageData.basicData.blurhash, let url = imageData.basicData.fullsizeUrl, let size = imageData.imageDetails.originalSize {
                    blurhashes[imageData.id] = try? await BlurhashImageCacheService.shared.image(
                        blurhash: blurhash,
                        size: size,
                        url: url.absoluteString
                    ).singleOutput()
                }
            }
        }
    }
    
    var useRestrictedHeight: Bool {
        switch contentConcealViewModel.currentMode {
        case .neverConceal:
            return false
        case .concealAll(_, let showAnyway), .concealMediaOnly(let showAnyway):
            return !showAnyway
        }
    }
}
