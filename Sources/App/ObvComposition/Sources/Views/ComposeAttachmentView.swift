/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
 *
 *  This file is part of Olvid for iOS.
 *
 *  Olvid is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License, version 3,
 *  as published by the Free Software Foundation.
 *
 *  Olvid is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import ObvDesignSystem
import UniformTypeIdentifiers
import CoreData
import ObvSystemIcon


/// ComposeAttachmentsView contains a list of ComposeAttachmentView
/// 
public struct ComposeAttachmentsView: View {
    
    private var attachments: [ComposeAttachmentView.AttachmentIdentifier]

    /// Not observed: the only thing this body reads off it is `globalCornerRadius`, which is a constant. Anything of the state that decides what
    /// is drawn here is passed in as a value, so that a change to it makes this view differ from the one SwiftUI already has.
    private var sharedState: ComposeView.SharedState
    private let attachmentDataSource: any ComposeAttachmentViewDataSource
    
    /// Actions
    private let actions: any ComposeViewActions
    
    /// Passed in rather than read from ``sharedState``: a stored value SwiftUI can compare is what makes this view differ from the previous one,
    /// and so what makes its body run when the flag flips. Observing the state instead would re-run this body on every publish it makes — a
    /// keystroke among them — and each run rebuilds every ``ComposeAttachmentView``, whose `init` fetches from Core Data and touches the disk.
    private let isCurrentlySendingMessage: Bool

    /// Whether an export of the draft's videos is running. A Bool rather than the fraction, for the reason given for
    /// ``isCurrentlySendingMessage``: the fraction changes several times a second.
    private let videosAreBeingPrepared: Bool

    /// Whether a send has ended and the model still lists what it sent. See `SharedState.theSentAttachmentsAreStillListed`.
    private let theSentAttachmentsAreStillListed: Bool

    init(viewModel: ComposeView.SharedState,
         isCurrentlySendingMessage: Bool,
         videosAreBeingPrepared: Bool,
         theSentAttachmentsAreStillListed: Bool,
         attachments: [ComposeAttachmentView.AttachmentIdentifier],
         attachmentDataSource: any ComposeAttachmentViewDataSource,
         actions: any ComposeViewActions) {
        self.attachments = attachments
        self.sharedState = viewModel
        self.isCurrentlySendingMessage = isCurrentlySendingMessage
        self.videosAreBeingPrepared = videosAreBeingPrepared
        self.theSentAttachmentsAreStillListed = theSentAttachmentsAreStillListed
        self.attachmentDataSource = attachmentDataSource
        self.actions = actions
    }
    
    /// During the sending of a message, we hide the attachments to prevent an animation glitch.
    ///
    /// **And until the model no longer lists them.** The send ends before the model saying the draft is empty arrives, and hiding them
    /// only while sending drew the sent attachments again for about three frames in between, measured on a recording.
    ///
    /// **It asks whether a message is being sent, and not `isPreventingEdition`, which is a wider question than the one this needs answering.**
    /// That property is the disjunction of three unrelated flags, and two of them are raised precisely while an attachment is on its way *into*
    /// the draft — `isLocallyAddingAttachment` for a paste, a drop, a sticker or a Genmoji, and `isDiscussionViewPreventingEdition` for the photo
    /// picker, the camera, the scanner and the file browser. Blanking the panel there hides the attachments the reader already has for as long as
    /// the copy takes, which is not an animation glitch being avoided but the panel refusing to show what it is for.
    ///
    /// **Shown while the send waits for the videos**, and hidden when that wait ends, just before the message is created. A send can wait
    /// for exports of tens of seconds, and the rings on the tiles are then the only thing saying which clip is being prepared. The row
    /// keeps its height either way.
    private var attachmentsToShow: [ComposeAttachmentView.AttachmentIdentifier] {
        if (isCurrentlySendingMessage && !videosAreBeingPrepared) || theSentAttachmentsAreStillListed {
            return []
        } else {
            return attachments
        }
    }
    
    /// The attachments a clip is being, or is about to be, encoded for.
    ///
    /// Held here rather than in the tile, because the tap is handled here: the tile is the `Button`'s label, and `disabled` inside a label
    /// does not reach the button. Opening a clip is refused while its export runs, since it would show a file that is not what will be
    /// sent. The refusal is a guard in the action, not `disabled`, which would also disable the ✕ in the same label.
    @State private var attachmentsBeingEncoded = Set<ComposeAttachmentView.AttachmentIdentifier>()

    public var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .bottom, spacing: 6.0) {
                ForEach(Array(attachmentsToShow.enumerated()), id: \.element) { index, attachmentIdentifier in
                    Button(action: {
                        // **Refused here rather than with `disabled`, and that is the whole of the fix.** `disabled` is an *environment* value: put
                        // on this button it reaches every view in its label, and the label is the whole tile — including the ✕ that removes the
                        // attachment. So a clip could not be removed for as long as its export ran, which is tens of seconds apiece and, every video
                        // in a draft being reported as waiting before the first export starts, applies to all of them at once. It also made the
                        // coordinator's own handling of *an attachment removed while its clip was being encoded* unreachable. Guarding the action
                        // refuses exactly the one thing that must be refused. What says the tile is busy is the ring drawn over it, which is what
                        // the reader is looking at anyway.
                        guard !attachmentsBeingEncoded.contains(attachmentIdentifier) else { return }
                        try? actions.userDidTapOnDraftFyleJoinWithHardLink(self, at: index)
                    }) {
                        ComposeAttachmentView(viewModel: sharedState,
                                              attachmentIdentifier: attachmentIdentifier,
                                              dataSource: attachmentDataSource,
                                              actions: actions,
                                              isBeingEncodedDidChange: { identifier, isBeingEncoded in
                                                  if isBeingEncoded {
                                                      attachmentsBeingEncoded.insert(identifier)
                                                  } else {
                                                      attachmentsBeingEncoded.remove(identifier)
                                                  }
                                              })
                    }
                }
            }
            .padding(6.0)
        }
        // An attachment removed while its clip was being encoded leaves its tile with no chance to say it has stopped, so the set would
        // keep a name nothing answers to. Harmless — there is no button under that name any more — but a set that only ever grows is a
        // leak waiting for somebody to read it for something else.
        .onChange(of: attachments) { attachments in
            attachmentsBeingEncoded.formIntersection(attachments)
        }
        .scrollIndicators(.hidden)
        .clipShape(UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: sharedState.globalCornerRadius, topTrailing: sharedState.globalCornerRadius), style: .continuous))
    }
    
}


// MARK: - ComposeAttachmentView

public struct ComposeAttachmentView: View {
    
    private let viewModel: ComposeView.SharedState
    private let attachmentIdentifier: AttachmentIdentifier
    private let dataSource: ComposeAttachmentViewDataSource
    private let actions: any ComposeViewActions
    
    public enum AttachmentIdentifier: Equatable, Sendable, Hashable {
        case persistedDraftFyleJoinObjectID(NSManagedObjectID)
    }
    
    /// Says whether an export is running, or about to run, for this attachment. See `ComposeAttachmentsView`, which is where the tap
    /// that has to be refused lives.
    private let isBeingEncodedDidChange: (AttachmentIdentifier, Bool) -> Void

    private let initialDataSourceViewModel: ComposeViewDataSourceFyleModel?
    @State private var streamedDataSourceViewModel: ComposeViewDataSourceFyleModel?
    private var dataSourceViewModel: ComposeViewDataSourceFyleModel? {
        streamedDataSourceViewModel ?? initialDataSourceViewModel
    }
    
    /// How far the export of this clip has got, or nil when nothing is being exported for it. Seeded in `init`, so that a tile scrolled back
    /// into the row draws its ring on its first frame, then set from the data source's stream.
    @State private var transcodingProgress: Double?

    init(viewModel: ComposeView.SharedState,
         attachmentIdentifier: AttachmentIdentifier,
         dataSource: ComposeAttachmentViewDataSource,
         actions: any ComposeViewActions,
         isBeingEncodedDidChange: @escaping (AttachmentIdentifier, Bool) -> Void = { _, _ in }) {
        self.viewModel = viewModel
        self.attachmentIdentifier = attachmentIdentifier
        self.dataSource = dataSource
        self.actions = actions
        self.isBeingEncodedDidChange = isBeingEncodedDidChange
        
        if let initialDataSourceModel = dataSource.getInitialComposeViewDataSourceFyleModel(attachmentIdentifier: attachmentIdentifier) {
            self.initialDataSourceViewModel = initialDataSourceModel
        } else {
            self.initialDataSourceViewModel = nil
        }
        self._transcodingProgress = State(initialValue: dataSource.getProgressOfTheVideoBeingPrepared(attachmentIdentifier: attachmentIdentifier))
    }
    
    @ViewBuilder
    public var content: some View {
        if let dataSourceViewModel {
            AnimatedImagePlaybackSetting { animatesByItself in
                ImageForAttachment(contentTypeAndImage: dataSourceViewModel.contentTypeAndImage,
                                   attachmentType: dataSourceViewModel.attachmentType,
                                   globalCornerRadius: viewModel.globalCornerRadius,
                                   attachmentIdentifier: attachmentIdentifier,
                                   animatesByItself: animatesByItself,
                                   dataSource: dataSource)
            }
                // **An overlay and not a replacement.** The reader has to go on recognising which clip is being prepared, so the poster
                // frame stays and the ring is drawn over it. `overlay` also takes no part in sizing, which matters here more than it
                // looks: the attachments row is pinned at 125pt and an animated change of this bar's height makes `safeAreaInset`
                // reparameterise the scroll view underneath it, which is a fault no scroll offset can repair.
                .overlay {
                    if let transcodingProgress {
                        VideoExportProgressRing(fractionCompleted: transcodingProgress)
                    }
                }
        } else {
            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: viewModel.globalCornerRadius / 2.0, style: .continuous)
                    .fill(Color(uiColor: .systemGroupedBackground))
                
                ProgressView()
            }
            .frame(width: 80)
        }
    }
    
    public var body: some View {
        ZStack(alignment: .topTrailing) {
            
            content

            AsyncButton(action: {
                do {
                    try await actions.userWantsToDeleteDraftAttachment(self, attachmentIdentifier: attachmentIdentifier)
                } catch {
                    assertionFailure()
                }
            }) {
                Image(systemIcon: .xmark)
                    .font(.system(size: 10, weight: .bold))
                    .padding(2.0)
                    .animation(nil, value: streamedDataSourceViewModel)
                    .clipShape(Circle())
            }
            .buttonBorderShapeObv(.circle)
            .buttonStyleObv(style: .glassOrBorderedProminent)
            .padding(.top, 4)
            .padding(.trailing, 2)
        }
        .task(onTaskForAsyncStreamOfComposeViewDataSourceFyleModel)
        .task(onTaskForTheProgressOfTheVideoBeingPrepared)
        // Said once on the way in as well as on every change: these tiles live in a `LazyHStack`, so a tile scrolled back into the row is a
        // new view whose progress comes from the seed, and `onChange` does not fire for a value that was there from the start.
        .onAppear {
            isBeingEncodedDidChange(attachmentIdentifier, transcodingProgress != nil)
        }
        .onChange(of: transcodingProgress) { fractionCompleted in
            isBeingEncodedDidChange(attachmentIdentifier, fractionCompleted != nil)
        }
    }
    
}


/// Drawn over the poster frame of a clip that is queued for, or undergoing, an export.
///
/// An overlay, so the clip stays recognisable. The ring is `ObvProgressRing`, the one the discussion screen draws over an attachment being
/// uploaded. It brings its own dark disc, so the tile gets no veil and is not dimmed; its tap is refused in ``ComposeAttachmentsView``.
///
/// A queued clip shows a turning ring rather than 0%, which would read as stuck.
private struct VideoExportProgressRing: View {

    let fractionCompleted: Double

    var body: some View {
        ObvProgressRing(fractionCompleted: fractionCompleted, diameter: 34, lineWidth: 3)
            .accessibilityElement()
            .accessibilityLabel(Text("VIDEO_EXPORT_IN_PROGRESS_ACCESSIBILITY_LABEL"))
            .accessibilityValue(Text(verbatim: fractionCompleted.formatted(.percent.precision(.fractionLength(0)))))
    }

}


private struct ImageForAttachment: View {

    let contentTypeAndImage: ComposeViewDataSourceFyleModel.ContentTypeAndImage
    let attachmentType: ComposeViewDataSourceFyleModel.FyleMessageJoinType
    let globalCornerRadius: CGFloat
    let attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier
    let animatesByItself: Bool
    let dataSource: ComposeAttachmentViewDataSource

    /// The frame a GIF's animation has reached, drawn in place of the still thumbnail. Nil until the first frame arrives, and for anything that does not animate.
    @State private var currentFrame: CGImage?

    private static func iconForType(_ type: UTType) -> ObvSystemIcon.SystemIcon {
        switch type {
        case .zip: return .rectangleCompressVertical
        default: return .paperclip
        }
    }

    /// Only a GIF animates, as in the discussion. A HEIC or a PNG holding several frames is not an animation, and a still photo is never decoded again.
    private var animates: Bool {
        animatesByItself && contentTypeAndImage.contentType.conforms(to: .gif)
    }

    private func picture(_ uiImage: UIImage) -> Image {
        if let currentFrame {
            Image(decorative: currentFrame, scale: uiImage.scale)
        } else {
            Image(uiImage: uiImage)
        }
    }

    var body: some View {
        if let uiImage = contentTypeAndImage.image {

            ZStack {

                picture(uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: globalCornerRadius / 2.0, style: .continuous))

                // **Asked of `attachmentType` and not of the content type**, which is what the badge that stood here did — and a
                // `switch` over a `UTType` is an equality test, so `case .video` asked whether the attachment was literally
                // `public.video`. A real clip is `com.apple.quicktime-movie` or `public.mpeg-4`, neither of which *equals* it (measured:
                // `UTType.quickTimeMovie == .video` is `false`, and the switch fell to `default`), so no video has ever carried a badge
                // here. `attachmentType` is computed from the UTI lists on `PersistedDraftFyleJoin` and does answer.
                if attachmentType == .video {
                    VideoBadge()
                }

            }
            // Cancelled by SwiftUI when the tile goes, which stops the decoding: a tile scrolled off the row, or removed, animates nothing. The frames are asked
            // for at the still thumbnail's pixel size, which is already made to fit the tile.
            .task(id: FramesRequest(attachmentIdentifier: attachmentIdentifier, animates: animates, maxPixelSize: Self.maxPixelSize(of: uiImage))) {
                await animate(maxPixelSize: Self.maxPixelSize(of: uiImage))
            }

        } else {
            
            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: globalCornerRadius / 2.0, style: .continuous)
                    .fill(Color.primary.opacity(0.1))
                Image(systemIcon: Self.iconForType(contentTypeAndImage.contentType))
            }
            .frame(width: 80)

        }
    }


    private static func maxPixelSize(of uiImage: UIImage) -> Int {
        Int((max(uiImage.size.width, uiImage.size.height) * uiImage.scale).rounded())
    }


    private func animate(maxPixelSize: Int) async {
        guard animates else {
            currentFrame = nil
            return
        }
        for await frame in dataSource.getAsyncStreamOfFramesForAnimatedImage(attachmentIdentifier: attachmentIdentifier, maxPixelSize: maxPixelSize) {
            currentFrame = frame
        }
    }


    private struct FramesRequest: Hashable {
        let attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier
        let animates: Bool
        let maxPixelSize: Int
    }

}


/// Reads whether the reader lets animated images play by themselves (**Settings → Accessibility → Motion → Auto-Play Animated Images**, iOS 17 and later), and
/// hands the answer to what it wraps. On iOS 16 there is no such setting, and animations play.
///
/// A view of its own because an `@Environment` property reading an iOS 17 key cannot be declared conditionally. The discussion has the same pair.
private struct AnimatedImagePlaybackSetting<Content: View>: View {

    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        VStack(spacing: 0) {
            if #available(iOS 17.0, *) {
                AnimatedImagePlaybackSettingReader(content: content)
            } else {
                content(true)
            }
        }
    }

}


@available(iOS 17.0, *)
private struct AnimatedImagePlaybackSettingReader<Content: View>: View {

    @Environment(\.accessibilityPlayAnimatedImages) private var accessibilityPlayAnimatedImages

    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(accessibilityPlayAnimatedImages)
    }

}


/// What marks a tile of the composition bar as a clip rather than a still: a play glyph over the thumbnail.
private struct VideoBadge: View {

    /// `.system(size:)` and not a text style. The tile is 80pt wide and does not grow with Dynamic Type, so a glyph that did would walk
    /// out of it. Acceptable here because it says nothing the tile does not already show.
    private static let fontOfThePlayGlyph: Font = .system(size: 15, weight: .bold)

    var body: some View {
        // The glyph sits on a disc of its own rather than straight on the picture: a white triangle over a pale photograph is
        // invisible, and a shadow under it would be one more thing to tune per appearance.
        Circle()
            .fill(.black.opacity(0.45))
            .frame(width: 30, height: 30)
            .overlay {
                Image(systemIcon: .playFill)
                    .font(Self.fontOfThePlayGlyph)
                    .foregroundStyle(.white)
                    // A play triangle is visually off-centre in its own box, its bounding box being square and its mass to the left.
                    // A point to the right is what makes it look centred in the disc.
                    .offset(x: 1)
            }
            // The badge says what the tile *is*; it is not a control, and the tap belongs to the tile beneath it.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

}


extension ComposeAttachmentView {

    private func onTaskForAsyncStreamOfComposeViewDataSourceFyleModel() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfComposeViewDataSourceFyleModel(attachmentIdentifier: attachmentIdentifier)
            for await receivedDataSourceViewModel in stream {
                withAnimation {
                    self.streamedDataSourceViewModel = receivedDataSourceViewModel
                }
            }
            dataSource.finishAsyncStreamOfComposeViewDataSourceFyleModel(streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }


    private func onTaskForTheProgressOfTheVideoBeingPrepared() async {
        let stream = dataSource.getAsyncStreamOfTheProgressOfTheVideoBeingPrepared(attachmentIdentifier: attachmentIdentifier)
        for await fractionCompleted in stream {
            withAnimation {
                self.transcodingProgress = fractionCompleted
            }
        }
    }
    
}

