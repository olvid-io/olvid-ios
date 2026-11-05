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
import ImageIO
import QuickLook
import ObvAppCoreConstants
import ObvOwnedIdentityChooser
import ObvTypes
import ObvAppTypes
import ObvDesignSystem
import ObvSystemIcon
import UniformTypeIdentifiers
import ObvUI

/// SharedState manages the state for sharing content within Olvid.
/// This class handles the user's selection of identity, discussions, text body,
/// and shareable items (files and links) to be shared.
@MainActor
public final class SharedState: ObservableObject {
    
    // MARK: - Properties
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: SharedState.self))
    
    // MARK: - Initialization
    
    /// Initializes the shared state with optional initial values
    /// - Parameters:
    ///   - initialOwnedCryptoId: The initial owned crypto identity to select
    ///   - initialSelectedDiscussionIdentifiers: Identifiers of the pre-selected discussions to share with
    ///   - initialMediaQuality: The quality to send photos and videos at, i.e. the choice the user made the
    ///     last time they shared. Injected rather than read here so this module needs no dependency on the
    ///     settings; the extension reads `ObvMessengerSettings` and hands the answer over.
    public init(initialOwnedCryptoId: ObvCryptoId? = nil,
                initialSelectedDiscussionIdentifiers: [ObvDiscussionIdentifier] = [],
                initialMediaQuality: ObvMediaQuality
    ) {
        if let initialOwnedCryptoId {
            selectedOwnedCryptoId = initialOwnedCryptoId
        }

        self.selectedDiscussionIdentifiers = initialSelectedDiscussionIdentifiers

        self.mediaQuality = initialMediaQuality

        self.isLoading = false

        self.isSending = false
    }
    
    // MARK: - Published Properties
    
    /// The text message body to be shared
    @Published public var textBody: String = ""
    
    /// The currently selected owned crypto identity for sending
    @Published public var selectedOwnedCryptoId: ObvCryptoId?
    
    /// The identifiers of the discussions selected as recipients. Only identifiers are stored: each place
    /// that needs a discussion's avatar/title resolves it on demand through the discussion item data source.
    @Published public var selectedDiscussionIdentifiers: [ObvDiscussionIdentifier] = []
    
    /// Combined array of all shareable items (hardlinks and link metadatas)
    @Published private(set) var shareableItems: [ShareableItem] = []
    
    /// Currently selected shareable item being previewed
    @Published var currentShareableItem: ShareableItem?
    
    /// Indicates whether content is currently being loaded
    /// When set to true, displays a loading placeholder item
    @Published public var isLoading: Bool {
        didSet {
            // Only react to an actual change. `didSet` fires on every assignment, so without this a
            // redundant `isLoading = false` (while already false) would run the `else` branch and wipe
            // `shareableItems`/`currentShareableItem` — clobbering items that were already loaded.
            guard isLoading != oldValue else { return }
            if isLoading {
                let loading = ShareableItem.loading

                shareableItems = [loading]

                currentShareableItem = loading
            } else {
                shareableItems = []
                currentShareableItem = nil
            }
        }
    }
    
    @Published public var isSending: Bool {
        didSet {
            // Keep `sendingProgress` from outliving the send it describes. Every path that gives up on a
            // send resets `isSending`; clearing here means none of them has to remember to also clear the
            // progress, which would otherwise leave a stale caption behind if the user sends again.
            guard isSending != oldValue else { return }
            if !isSending {
                sendingProgress = nil
            }
        }
    }

    /// Where the send pipeline currently is, so the compose bar can show a determinate indicator instead of
    /// a bare spinner. `nil` whenever `isSending` is false, and while the send is in a phase short enough
    /// that reporting it would only flicker.
    @Published public var sendingProgress: SendingProgress?

    /// Quality setting for media attachments (photos and videos)
    /// Applies to every photo and video of the share, whatever else it carries
    @Published public var mediaQuality: ObvMediaQuality
    
    /// Determines if the current state allows sharing
    /// Returns true if an owned identity is selected, at least one discussion is selected,
    /// and there is either text to share OR at least one shareable item
    var canShare: Bool {
        selectedOwnedCryptoId != nil
        && !selectedDiscussionIdentifiers.isEmpty
        && (!textBody.isEmpty || !shareableItems.isEmpty)
        && !isSending
    }
    
    /// Whether the share carries at least one photo or video (excluding loading items), i.e. whether the
    /// HD/SD control has anything to act on.
    ///
    /// **At least one, not all of them.** The send path transcodes whatever media the batch holds whenever
    /// the quality is standard, without asking what else is in it — so a test of *all* would have hidden the
    /// control on a batch of a photo and a document while still downscaling the photo.
    var atLeastOneShareableItemIsAPhotoOrVideo: Bool {
        shareableItems.contains { item in
            guard case .hardlink(let hardlink) = item else { return false }
            let fileType = hardlink.fileType
            return fileType == .image || fileType == .video
        }
    }
    
    public var hardlinks: [SharedState.HardLink] {
        // Get the hardlinks for accessing the actual file URLs
        shareableItems.compactMap { item -> SharedState.HardLink? in
            guard case .hardlink(let hardlink) = item else { return nil }
            return hardlink
        }
    }
    
    
    // MARK: - ShareableItem
    
    /// Enum representing items that can be shared: either a hardlink or a link metadata
    public enum ShareableItem: Hashable, Identifiable {
        case loading
        case hardlink(HardLink)
        case linkMetadata(url: URL, metadata: ObvLinkMetadata)
        
        /// Unique identifier for each shareable item
        public var id: String {
            switch self {
            case .hardlink(let hardlink):
                return "hardlink_\(hardlink.index)_\(hardlink.url.absoluteString)"
            case .linkMetadata(let url, _):
                return "linkMetadata_\(url.absoluteString)"
            case .loading:
                return "loading"
            }
        }
        
        // Identity is `id` and nothing else. The synthesized conformance would derive it from the whole
        // payload, so a `HardLink` whose `thumbnail` changed from `.loading` to `.image` would count as a
        // *different* item — and `HorizontalShareableItemsView` identifies its `ForEach` rows by
        // `id: \.self`. SwiftUI would then tear down the row and rebuild it: the full-size `ImageView` would
        // lose its `@State` and restart its decode (the photo visibly blinks out and back), and a `VideoView`
        // would lose its `AVPlayer` mid-playback. The thumbnail is only consumed by the thumbnail strip, so
        // it must not affect identity here.
        public static func == (lhs: ShareableItem, rhs: ShareableItem) -> Bool {
            lhs.id == rhs.id
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        /// Returns the underlying hardlink if this is a hardlink item
        var hardlink: HardLink? {
            if case .hardlink(let hardlink) = self {
                return hardlink
            }
            return nil
        }
        
        /// Returns the underlying link metadata if this is a link metadata item
        var linkMetadata: (url: URL, metadata: ObvLinkMetadata)? {
            if case .linkMetadata(let url, let metadata) = self {
                return (url, metadata)
            }
            return nil
        }
    }
    
    // MARK: - Thumbnail
    
    /// Represents different types of thumbnails for shareable items
    public enum Thumbnail: Hashable, Equatable {
        case loading
        case symbol(_ symbol: SystemIcon)
        case image(_ image: UIImage)
        
        public static func == (lhs: Thumbnail, rhs: Thumbnail) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading):
                return true
            case (.symbol(let lhsSymbol), .symbol(let rhsSymbol)):
                return lhsSymbol == rhsSymbol
            case (.image(let lhsImage), .image(let rhsImage)):
                // Using identity comparison for UIImage since pixel-by-pixel comparison would be expensive
                return lhsImage === rhsImage
            default:
                return false
            }
        }
        
        public func hash(into hasher: inout Hasher) {
            switch self {
            case .loading:
                hasher.combine(0)
            case .symbol(let symbol):
                hasher.combine(1)
                hasher.combine(symbol)
            case .image(let image):
                hasher.combine(2)
                // Using object identity for UIImage
                hasher.combine(ObjectIdentifier(image))
            }
        }
    }
    
    // MARK: - HardLink
    
    /// Represents a file to be shared via a hardlink reference
    public struct HardLink: Hashable {
        /// Index of this hardlink in the collection
        public let index: Int
        /// The Uniform Type Identifier for this file
        let contentType: UTType
        /// Local file URL pointing to the hardlinked file
        public let url: URL
        /// Display name of the file
        let filename: String
        /// When the file was created
        let creationDate: Date
        /// Visual representation of the file (icon or thumbnail image)
        let thumbnail: Thumbnail
        /// Pixel dimensions of the image, EXIF orientation already applied, or nil when the file is not an
        /// image or its header could not be read. See ``pixelSizeOfImage(at:)``.
        public let pixelSize: CGSize?

        public init(index: Int,
                    contentType: UTType,
                    url: URL,
                    filename: String,
                    creationDate: Date,
                    thumbnail: Thumbnail,
                    pixelSize: CGSize? = nil) {
            self.index = index
            self.contentType = contentType
            self.url = url
            self.filename = filename
            self.creationDate = creationDate
            self.thumbnail = thumbnail
            self.pixelSize = pixelSize
        }

        /// The image's width/height ratio, or nil when unknown.
        var aspectRatio: CGFloat? {
            guard let pixelSize, pixelSize.width > 0, pixelSize.height > 0 else { return nil }
            return pixelSize.width / pixelSize.height
        }

        /// Reads an image's dimensions from its **header only**.
        ///
        /// `CGImageSourceCopyPropertiesAtIndex` parses metadata without decoding any pixels, so this reads
        /// a few KB and allocates no bitmap — cheap enough to run over every shared file up front. Knowing
        /// the shape in advance lets a placeholder reserve the right box, instead of every page starting as
        /// a fixed 16:9 rectangle and resizing when its decode lands.
        public static func pixelSizeOfImage(at url: URL) -> CGSize? {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
            guard let width = properties[kCGImagePropertyPixelWidth] as? Double,
                  let height = properties[kCGImagePropertyPixelHeight] as? Double else { return nil }
            // The preview decode bakes in EXIF orientation (`kCGImageSourceCreateThumbnailWithTransform`),
            // so for the quarter-turned orientations the displayed image has these dimensions swapped.
            let orientation = (properties[kCGImagePropertyOrientation] as? UInt32) ?? 1
            let isQuarterTurned = (5...8).contains(orientation)
            return isQuarterTurned ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        }
    }
    
    // MARK: - ImageOrIcon
    
    /// Represents either an avatar or a system icon for display
    public enum ImageOrIcon {
        case avatarModel(ObvAvatarViewModel)
        case icon(Image)
    }
    
    // MARK: - Public Methods
    
    /// Adds a link metadata item to the shareable items list
    /// - Parameters:
    ///   - linkMetadata: The metadata containing preview information for the link
    ///   - url: The URL of the link
    public func addLinkMetadata(linkMetadata: ObvLinkMetadata, for url: URL) {
        
        if isLoading {
            isLoading = false
        }
        
        // Check if this URL is already in shareable items to avoid duplicates
        let alreadyExists = shareableItems.contains { item in
            if case .linkMetadata(let existingURL, _) = item, existingURL == url {
                return true
            }
            return false
        }
        
        // Only add if not already present
        if !alreadyExists {
            let item = ShareableItem.linkMetadata(url: url, metadata: linkMetadata)
            shareableItems.append(item)
            
            // Set as current if it's the first item
            if currentShareableItem == nil {
                currentShareableItem = item
            }
        }
    }
    
    /// Sets the collection of hardlinks to be shared
    /// This will preserve existing link metadata items and asynchronously generate thumbnails
    /// - Parameter hardlinks: Array of hardlinks to add to shareable items
    public func setHardlinks(_ hardlinks: [HardLink]) {
        
        if isLoading {
            isLoading = false
        }
        
        // Update shareable items - keep existing link metadatas and add hardlinks
        let linkMetadataItems = shareableItems.compactMap { item -> ShareableItem? in
            if case .linkMetadata = item {
                return item
            }
            return nil
        }
        
        let hardlinkItems = hardlinks.map { ShareableItem.hardlink($0) }
        shareableItems = linkMetadataItems + hardlinkItems
        
        // Set current shareable item to first hardlink if no current item
        if let firstHardlink = hardlinks.first {
            if currentShareableItem == nil {
                currentShareableItem = .hardlink(firstHardlink)
            }
        }
        
        // Asynchronously generate thumbnails for each hardlink
        Task {
            for index in 0..<hardlinks.count {
                let hardlink = hardlinks[index]
                let thumbnail = await createThumbnail(hardlink: hardlink)
                
                // Update the hardlink with the generated thumbnail on the main actor
                DispatchQueue.main.async {
                    let updatedHardlink = HardLink(
                        index: hardlink.index,
                        contentType: hardlink.contentType,
                        url: hardlink.url,
                        filename: hardlink.filename,
                        creationDate: hardlink.creationDate,
                        thumbnail: thumbnail,
                        // Carried over rather than re-read: the header was already parsed when this
                        // hardlink was built, and only the thumbnail is changing here.
                        pixelSize: hardlink.pixelSize
                    )
                    
                    // Update shareableItems to reflect the thumbnail update
                    if let itemIndex = self.shareableItems.firstIndex(where: { item in
                        if case .hardlink(let hl) = item, hl == hardlink {
                            return true
                        }
                        return false
                    }) {
                        self.shareableItems[itemIndex] = .hardlink(updatedHardlink)
                        
                        // Update currentShareableItem if this is the item being replaced
                        if case .hardlink(let currentHL) = self.currentShareableItem, currentHL == hardlink {
                            self.currentShareableItem = .hardlink(updatedHardlink)
                        }
                    }
                }
            }
        }
    }
    
    /// Deletes a shareable item from the list and updates the current selection
    ///
    /// **iOS 17 and later, because there is nowhere else it can be called from.** The one caller is
    /// `HorizontalThumbnailsView`, which is itself `@available(iOS 17.0, *)` and built only inside an
    /// `if #available(iOS 17.0, *)` — so on iOS 16 there is no thumbnail strip and no way to remove a single item.
    /// This annotation says that, where the `else` branch it replaces implied a fallback that had never run and could
    /// not: a delay of 0.3s standing in for the animation's completion, matching no release's `.default` (`easeInOut`
    /// at 0.35s before iOS 17, a spring after), unaffected by Slow Animations, and impossible to cancel — so a second
    /// deletion inside the window would have selected an item that had itself just been removed.
    ///
    /// - Parameter item: The shareable item to delete
    @available(iOS 17.0, *)
    public func deleteShareableItem(_ item: ShareableItem) {
        // Find the index of the item to delete
        guard let index = shareableItems.firstIndex(of: item) else { return }
        
        // Determine the next current item before deletion
        let nextItem: ShareableItem?
        if shareableItems.count > 1 {
            // If there's a next item, select it; otherwise select the previous one
            if index < shareableItems.count - 1 {
                nextItem = shareableItems[index + 1]
            } else if index > 0 {
                nextItem = shareableItems[index - 1]
            } else {
                nextItem = nil
            }
        } else {
            nextItem = nil
        }
        
        // Remove the item, and change the selection when the *animation* says it is finished rather than when a
        // clock does.
        //
        // `.removed` rather than the default `.logicallyComplete`, because what is being waited for here is that the
        // row has stopped moving: `currentShareableItem` is bound to the pager's `scrollPosition`, so assigning it
        // while the removal is still settling moves the page mid-flight.
        withAnimation(.default, completionCriteria: .removed) {
            _ = self.shareableItems.remove(at: index)
        } completion: {
            self.currentShareableItem = nextItem
        }
    }
    
    // MARK: - Private Methods
    
    /// Creates a thumbnail for a hardlink using QuickLook
    /// Falls back to a system icon if thumbnail generation fails
    /// - Parameter hardlink: The hardlink to create a thumbnail for
    /// - Returns: A Thumbnail enum value containing either an image or a symbol
    private func createThumbnail(hardlink: HardLink?) async -> Thumbnail {
        guard let hardlink else { return .symbol(SystemIcon.paperclip) }
        
        let scale = UIScreen.main.scale
        let size = CGSize(width: 40, height: 40)
        let request = QLThumbnailGenerator.Request(fileAt: hardlink.url, size: size, scale: scale, representationTypes: .thumbnail)
        let generator = QLThumbnailGenerator.shared
        
        do {
            let thumbnail = try await generator.generateBestRepresentation(for: request)
            return .image(thumbnail.uiImage)
        } catch {
            // If thumbnail generation fails, fall back to a system icon based on content type
            return .symbol(hardlink.contentType.systemIcon)
        }
    }
}

// MARK: - SendingProgress

extension SharedState {

    /// The phase the send pipeline is in, with a fraction whenever we can report a truthful one.
    ///
    /// Only the two genuinely slow phases carry a fraction: transcoding to SD (which can take minutes for a
    /// 4K clip) and the upload wait (unbounded on a poor network, since the extension deliberately stays
    /// alive until the engine reports the attachments as sent). The phases in between are fast enough that
    /// a bar would only flash.
    public enum SendingProgress: Equatable {

        /// Media is being downscaled/re-encoded to SD before being sent. `fractionCompleted` spans *all*
        /// media items, weighted by file size, so one large video does not share the bar equally with a
        /// handful of small photos. The counts are for display ("Compressing 2 of 5").
        case transcoding(fractionCompleted: Double, completedItemCount: Int, totalItemCount: Int)

        /// Messages are being created in the app database and handed to the engine.
        case preparing

        /// The engine is uploading the attachments. `fractionCompleted` is nil until the engine reports its
        /// first chunk progress, and stays nil for a message with no attachment (where there is nothing to
        /// measure and the wait is short).
        case uploading(fractionCompleted: Double?)

        /// Which phase this is, without how far through it we are.
        ///
        /// Lets the UI tell "further along in the same phase" from "moved on to the next phase". The two need
        /// to look different: within a phase the fraction grows and animating it reads as progress, but
        /// across phases it restarts from zero, and animating *that* would read as progress being lost.
        public enum Phase: Hashable {
            case transcoding
            case preparing
            case uploading
        }

        public var phase: Phase {
            switch self {
            case .transcoding: return .transcoding
            case .preparing: return .preparing
            case .uploading: return .uploading
            }
        }

        /// The fraction to drive a determinate progress view with, or nil to fall back to an indeterminate one.
        public var fractionCompleted: Double? {
            switch self {
            case .transcoding(let fractionCompleted, _, _):
                return fractionCompleted
            case .preparing:
                return nil
            case .uploading(let fractionCompleted):
                return fractionCompleted
            }
        }
    }

}

// MARK: - ObvMediaQuality

extension ObvMediaQuality {

    /// The quality's name in the reader's language. Lives here rather than beside the enum because the
    /// strings belong to this module's catalog.
    public var displayName: String {
        switch self {
        case .high:
            return String(localizedInThisBundle: "MEDIA_QUALITY_HIGH")
        case .standard:
            return String(localizedInThisBundle: "MEDIA_QUALITY_STANDARD")
        }
    }

}

// MARK: - SharedState.HardLink Extensions

extension SharedState.HardLink {
    
    /// Categorizes the file into broad media types
    enum FileType {
        case image
        case video
        case audio
        case other
    }
    
    /// Determines the file type category based on UTType conformance
    var fileType: FileType {
        if contentType.conforms(to: .image) {
            return .image
        } else if contentType.conforms(to: .movie) || contentType.conforms(to: .video) {
            return .video
        } else if contentType.conforms(to: .audio) {
            return .audio
        } else {
            return .other
        }
    }
    
}
