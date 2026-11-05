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
import OSLog
import ObvAppTypes
import ObvAppCoreConstants

/// A horizontal scrollable view that displays full-sized attachment content.
///
/// This view presents hardlinked attachments in a paginated horizontal scroll view,
/// where each attachment takes up the full width of the screen. Different file types
/// are rendered with specialized views:
/// - Images are displayed with `ImageView`
/// - Videos are displayed with `VideoView` (with automatic playback management)
/// - Other files are displayed with `FileView`
///
/// On iOS 17+, the view uses the modern scroll target behavior for smooth paging.
/// The view automatically stops video playback when scrolling away from a video attachment.
struct HorizontalShareableItemsView: View {
    
    /// The shared state object that manages hardlinks and current selection
    @ObservedObject var sharedState: SharedState

    /// The one thing in the module that builds a preview, and the only thing that holds one.
    @ObservedObject private var store = PreviewImageStore.shared

    /// The **container's** size, in points — the frame the pager itself occupies.
    ///
    /// Read from the container and from nothing else, and that is the whole of what went wrong the first time. This
    /// used to be read from a `.background` on the page view, which is `Group { picture }.padding()` — a view whose
    /// height is decided by *its own picture's* aspect ratio. So nine pages wrote one `@State`, portrait and landscape
    /// pages reported different heights, and the value then chose the decode size, which produced the picture, which
    /// decided the page's height. A measurement that is an input to the thing it measures, and it span: a portrait
    /// photograph beside a landscape one decoded each other for ever, one picture per turn, `resident` never once
    /// reaching 3.
    ///
    /// The lesson is not that a `.background` disturbs layout — it does not, and the old comment said so correctly.
    /// It is that **a geometry reading is only stable if nothing downstream of it can change what is being read**, so
    /// read the frame that is imposed from outside rather than the one a subview negotiated.
    @State private var containerBox: CGSize = .zero

    /// What one page is actually drawn in: the container, less the padding each page carries.
    ///
    /// `containerRelativeFrame(.horizontal, count: 1)` gives every page the container's width, so this is the same for
    /// every page and both the centre and its neighbours are sized by identical arithmetic. Computed here and handed to
    /// the store as a plain value; no page view reads geometry of its own.
    private var pageBox: CGSize {
        guard containerBox.width > 0, containerBox.height > 0 else { return .zero }
        return CGSize(width: max(0, containerBox.width - 2 * Self.pageInset),
                      height: max(0, containerBox.height - 2 * Self.pageInset))
    }

    /// The inset each page carries. Named once, because ``pageBox`` subtracts exactly what ``shareableItemView`` adds
    /// and two literals that must agree are a bug waiting to be introduced.
    private static let pageInset: CGFloat = 16

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        theScrollingPages
            // **Both branches need these, and forgetting that broke iOS 16 completely.** They lived on the iOS 17
            // branch alone, where `scrollPosition` re-asks often enough to paper over it. On iOS 16 the only driver is
            // a page's own `onAppear`, which fires while `containerBox` is still `.zero` — so the store rightly
            // declines, having nothing to size against, and nothing ever asked again. Scrolling brought new pages, and
            // *their* `onAppear` fired once the box was known, which is why previews appeared only after moving a few
            // points; with a single shared photograph there is no second page to appear and it never loaded at all.
            //
            // `.task(id:)` rather than `onChange`: the two-argument `onChange` is iOS 17+, and unlike `onChange` this
            // also fires for the *initial* value, which is the case that was missing. Firing more often is free —
            // `readerIsLookingAt` does nothing when the window is unchanged.
            .task(id: containerBox) {
                theReaderIsLookingAgain(because: "containerResized")
            }
            // Deleting an item from the thumbnail strip renumbers every page after it, so a window remembered by index
            // would hold the picture of something no longer shared and fail to build the page that took its place.
            .task(id: sharedState.shareableItems) {
                theReaderIsLookingAgain(because: "itemsChanged")
            }
    }

    @ViewBuilder
    private var theScrollingPages: some View {
        if #available(iOS 17.0, *) {
            // Modern iOS 17+ implementation with enhanced scrolling behavior.
            // LazyHStack so only the on-screen attachment views are instantiated: in the memory-constrained
            // share extension, eagerly building every full-size image/video preview at once risks a jetsam kill.
            ScrollView(.horizontal) {
                LazyHStack {
                    // `id: \.self` is safe because `ShareableItem`'s `Hashable` is defined over `id` alone;
                    // it must stay that way or these rows get rebuilt whenever any part of the payload
                    // changes. `\.self` rather than `\.id` because `scrollPosition` below binds a
                    // `ShareableItem?`, so the row id has to be the item itself.
                    ForEach(sharedState.shareableItems, id: \.self) { shareableItem in
                        shareableItemView(for: shareableItem)
                    }
                    .containerRelativeFrame(.horizontal, count: 1, spacing: 0)
                }
                .scrollTargetLayout()
            }
            .background {
                // The container's frame, which the caller imposes with `maxWidth/maxHeight: .infinity` — so nothing a
                // page does can change it. Contrast the per-page reading this replaced; see `containerBox`.
                GeometryReader { proxy in
                    Color.clear
                        .task(id: proxy.size) { containerBox = proxy.size }
                }
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $sharedState.currentShareableItem)
            .scrollIndicators(.never)
            .onChange(of: sharedState.currentShareableItem) { oldValue, newValue in
                reportThePage(from: oldValue, to: newValue)
                // Stop the previous video if it was a video
                if let old = oldValue?.hardlink, old.fileType == .video {
                    stopVideo(for: old)
                }
                theReaderIsLooking(at: newValue, because: "pageChanged")
            }
            .onAppear {
                reportThePage(from: nil, to: sharedState.currentShareableItem)
                theReaderIsLooking(at: sharedState.currentShareableItem, because: "appeared")
            }
        } else {
            // Fallback implementation for iOS versions prior to 17.
            //
            // `containerRelativeFrame` is iOS 17+, so pin each page to the container width by hand. Without
            // a width a page sizes to its content, and a `resizable()` image inside an unbounded horizontal
            // `ScrollView` takes its ideal size — for a full-resolution decode, far wider than the screen,
            // which is exactly how this looked on iOS 16. The `GeometryReader` is safe here because the
            // caller already hands this view a definite frame.
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(sharedState.shareableItems.enumerated()), id: \.element) { index, shareableItem in
                            shareableItemView(for: shareableItem)
                                .frame(width: geometry.size.width)
                                // There is no `scrollPosition` before iOS 17, so nothing here knows which page the
                                // reader is on. A page appearing is the only signal available, and on this branch it
                                // is the driver — imprecise during a fast flick, which is acceptable on a path that
                                // already goes without the thumbnail strip.
                                .onAppear { theReaderIsLooking(atIndexOf: index, because: "pageAppeared") }
                        }
                    }
                }
                // The same reading as the iOS 17 branch, from the geometry this branch already has.
                .task(id: geometry.size) { containerBox = geometry.size }
            }
        }
    }
 
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "PreviewMemory")

    /// Says which page the reader is on and what is resident at that instant. **Instrumentation only.**
    ///
    /// Written *before* the store is told, so the log reads in the order things happen: the page change, then what was
    /// held when it happened, then the evictions it caused, then the one decode it started. That sequence is what this
    /// whole change is answerable to — the picture leaving the screen must give its bytes back before the picture
    /// arriving asks for its own — so it has to be readable straight down the log, which is why nothing here hops
    /// between threads.
    private func reportThePage(from oldValue: SharedState.ShareableItem?, to newValue: SharedState.ShareableItem?) {
        let indexOf: (SharedState.ShareableItem?) -> String = { item in
            guard let item, let index = sharedState.shareableItems.firstIndex(of: item) else { return "?" }
            return "\(index)"
        }
        Self.logger.notice("📤🧠 page \(indexOf(oldValue), privacy: .public)→\(indexOf(newValue), privacy: .public) of \(sharedState.shareableItems.count, privacy: .public) \(store.residentDescription(), privacy: .public) \(PreviewMemory.description(), privacy: .public)")
    }

    /// Tells the store where the reader is, so it can hold the page on screen and the one either side and give up
    /// everything else.
    ///
    /// **This replaced `prefetchNeighbours`, which was measured doing harm.** It fired two fire-and-forget,
    /// uncancellable decodes on every page change, beside the decode the appearing page started for itself — three at
    /// once, structurally, which is the case the kernel killed. And every one of them was wasted: the cache they filled
    /// was evicting each entry in the millisecond it arrived, so the same file was decoded four times in ten seconds.
    /// The store does the same anticipation with a bound: one decode at a time, and eviction before allocation.
    private func theReaderIsLooking(at item: SharedState.ShareableItem?, because trigger: String) {
        // `currentShareableItem` is nil until the first item has loaded, and nil again whenever the list empties, so a
        // bare `guard let` would leave the first page undrawn on any path where the binding has not caught up.
        //
        // **But the fallback must not invent a centre.** It used to fall back to page 0, which is a *different* centre
        // from the one in use — so any trigger that could not locate the item moved the window somewhere else, and the
        // next trigger moved it back. That is a loop with no natural end, and one was observed decoding two
        // photographs against each other indefinitely. Reusing the last known centre cannot oscillate: it is either
        // the answer already in force, or, on the very first call, page 0 because there is nothing else it could be.
        guard !sharedState.shareableItems.isEmpty else { return }
        let candidate = item.flatMap { sharedState.shareableItems.firstIndex(of: $0) } ?? lastKnownCentre
        // Clamped, because a remembered centre outlives the list it was an index into: delete the last two items from
        // the strip and it points past the end, whereupon `windowOfIndices` answers with nothing at all — which reads
        // as "the reader wants no pictures" and evicts the lot.
        let index = min(max(0, candidate), sharedState.shareableItems.count - 1)
        theReaderIsLooking(atIndexOf: index, because: trigger)
    }


    /// The centre last acted on, so a trigger that cannot locate the reader's page leaves the window where it is.
    @State private var lastKnownCentre = 0


    /// Asks again for the window already in force, because something other than the reader's position changed.
    ///
    /// It deliberately does **not** consult `currentShareableItem`: on iOS 16 nothing keeps that binding in step with
    /// the reader — there is no `scrollPosition` — so re-asking from it would drag the window back to the first page
    /// every time the container resized or the item list changed. That is the centre oscillation that once had two
    /// photographs decoding each other indefinitely, and this is the shape it would have come back in.
    ///
    /// `lastKnownCentre` is recorded even when the store declines, which is what makes this work at startup: page 0's
    /// `onAppear` fires too early to be acted on, but it still says where the reader is, so the box arriving is enough
    /// to finish the job.
    private func theReaderIsLookingAgain(because trigger: String) {
        guard !sharedState.shareableItems.isEmpty else { return }
        theReaderIsLooking(atIndexOf: min(max(0, lastKnownCentre), sharedState.shareableItems.count - 1),
                           because: trigger)
    }


    private func theReaderIsLooking(atIndexOf index: Int, because trigger: String) {
        lastKnownCentre = index
        store.readerIsLookingAt(index: index,
                                pages: pagesToPreview,
                                pageBox: pageBox,
                                displayScale: displayScale,
                                because: trigger)
    }


    // Every one of the five call sites above names itself, and that is not decoration. They are all otherwise silent,
    // so an infinite loop between two of them had to be deduced from the *absence* of `page` lines in a log — and a
    // trigger that fires without saying so cannot be told from one that never fired.


    /// Every page of the pager as the store sees it, **index-aligned with what is on screen** and nil where there is
    /// nothing to render: a link card draws its own metadata, an audio file has no picture, an item still loading has
    /// no file yet. Keeping the alignment means an index means the same thing in both places.
    private var pagesToPreview: [PreviewImageStore.Page?] {
        sharedState.shareableItems.map { item -> PreviewImageStore.Page? in
            guard let hardlink = item.hardlink else { return nil }
            switch hardlink.fileType {
            case .image:
                return .init(url: hardlink.url, kind: .photo, sourcePixelSize: hardlink.pixelSize)
            case .video:
                return .init(url: hardlink.url, kind: .video, sourcePixelSize: nil)
            case .audio:
                return nil
            case .other:
                return .init(url: hardlink.url, kind: .document, sourcePixelSize: nil)
            }
        }
    }


    /// Stops video playback for a specific hardlink.
    ///
    /// Posts a notification to stop video playback when the user scrolls away
    /// from a video attachment. This ensures only one video plays at a time
    /// and conserves resources.
    ///
    /// - Parameter hardlink: The hardlink containing the video to stop
    private func stopVideo(for hardlink: SharedState.HardLink) {
        NotificationCenter.default.post(
            name: .stopVideo,
            object: nil,
            userInfo: ["hardlinkURL": hardlink.url]
        )
    }
    
    /// Creates a view for displaying a specific hardlink based on its file type.
    ///
    /// Routes the hardlink to the appropriate specialized view:
    /// - `.image` files are displayed using `ImageView` for interactive image viewing
    /// - `.video` files are displayed using `VideoView` with playback controls
    /// - Other file types use `FileView` to show file information and preview
    ///
    /// - Parameter hardlink: The hardlink to display
    /// - Returns: A view configured to display the specific file type
    @ViewBuilder
    func shareableItemView(for shareableItem: SharedState.ShareableItem) -> some View {
        Group {
            switch shareableItem {
            case .hardlink(let hardlink):
                switch hardlink.fileType {
                case .image:
                    // Display for images
                    ImageView(media: hardlink, store: store)
                case .video:
                    // Display for videos
                    VideoView(media: hardlink, mediaQuality: sharedState.mediaQuality, store: store)
                default:
                    // Display for other files
                    FileView(media: hardlink, store: store)
                }
            case .linkMetadata(url: let url, metadata: let linkMetadata):
                LinkMetadataView(url: url, metadata: linkMetadata)
            case .loading:
                // A bare spinner reads as "something is stuck", which is misleading when the wait is a
                // network round trip for a link preview. The caption says what is happening; it stays
                // generic because this same placeholder also covers hardlinking shared files.
                VStack(spacing: 12.0) {
                    ProgressView()
                    Text("SHARE_EXTENSION_PROGRESS_PREPARING")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Self.pageInset)
      }
}

/// Notification name used to communicate video playback control across the app.
///
/// This notification is posted when a video should stop playing, typically when
/// the user scrolls away from a video attachment. Observers (like `VideoView`)
/// should listen for this notification and pause/stop playback accordingly.
///
/// The notification's userInfo dictionary contains:
/// - `"hardlinkURL"`: The URL of the hardlink whose video should be stopped
extension Notification.Name {
    static let stopVideo = Notification.Name("com.olvid.stopVideo")
}

// MARK: - Previews

#if DEBUG

/// Creates a SharedState instance populated with sample data for preview purposes.
///
/// - Returns: A SharedState with sample hardlinks for testing and preview
@MainActor
private func makeSharedStateForPreviews() -> SharedState {
    let sharedState = SharedState(initialMediaQuality: .standard)
    
    let linkMetadata = [ObvLinkMetadata].sampleData[safe: 0]!
    sharedState.addLinkMetadata(linkMetadata: linkMetadata, for: linkMetadata.url!)

    sharedState.setHardlinks([SharedState.HardLink].sampleData)
    
    return sharedState
}

/// Pre-configured SharedState instance for use in SwiftUI previews
@MainActor
private let sharedStateForPreviews = makeSharedStateForPreviews()

#Preview {
    HorizontalShareableItemsView(sharedState: sharedStateForPreviews)
}

#endif
