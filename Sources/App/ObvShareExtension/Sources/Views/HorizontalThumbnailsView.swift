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
import ObvSystemIcon
import ObvAppTypes


/// A horizontal scrollable view that displays thumbnails of hardlinked files.
///
/// This view provides a thumbnail gallery where users can:
/// - Browse through multiple file attachments horizontally
/// - Select a thumbnail to view the full content
/// - Delete a hardlink by tapping on the currently selected thumbnail
///
/// The view automatically scrolls to the currently selected hardlink and provides
/// visual feedback for the active item with an overlay and delete icon.
@available(iOS 17.0, *)
struct HorizontalThumbnailsView: View {
    
    /// The shared state object that manages hardlinks and current selection
    @ObservedObject var sharedState: SharedState
    
    /// Local scroll position - used only for programmatic scrolling, not for tracking user scroll
    @State private var scrollPosition: SharedState.ShareableItem?
    
    /// Tracks whether deletion is allowed for the current hardlink
    @State private var canDelete = false
    
    /// Task used to delay deletion availability
    @State private var deletionDelayTask: Task<Void, Never>?
    
    var body: some View {
        ScrollView(.horizontal) {
            ZStack {
                Spacer()
                    .containerRelativeFrame([.horizontal])
                    .frame(height: 40.0)
                
                HStack(spacing: 4.0) {
                    ForEach(sharedState.shareableItems, id: \.self) { shareableItem in
                        thumbnailView(for: shareableItem)
                    }
                }
                .padding(.vertical)
            }
        }
        .scrollIndicators(.never)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollPosition(id: $scrollPosition)
        .onChange(of: sharedState.currentShareableItem) { _, newValue in
            // Only update scroll position when currentHardLink changes programmatically
            withAnimation {
                scrollPosition = newValue
            }
            
            // Reset deletion availability and start delay timer
            canDelete = false
            deletionDelayTask?.cancel()
            deletionDelayTask = Task {
                try? await Task.sleep(for: .seconds(0.5))
                if !Task.isCancelled {
                    canDelete = true
                }
            }
        }
        .onAppear {
            // Initialize scroll position with current hardlink
            scrollPosition = sharedState.currentShareableItem
            
            // Allow deletion immediately on first appear
            canDelete = true
        }
        .onDisappear {
            // Clean up task when view disappears
            deletionDelayTask?.cancel()
        }
    }
    
    /// Determines if the given hardlink is the currently selected one.
    ///
    /// - Parameter hardlink: The hardlink to check against the current selection
    /// - Returns: `true` if the hardlink matches the current selection, `false` otherwise
    private func isShearableItemTheCurrentOne(shareableItem: SharedState.ShareableItem) -> Bool {
        sharedState.currentShareableItem == shareableItem
    }
    
    /// Creates a thumbnail view for a specific hardlink.
    ///
    /// This view displays the thumbnail content (loading indicator, icon, or image)
    /// and handles user interactions:
    /// - If the hardlink is currently selected, tapping it will delete the hardlink
    /// - If the hardlink is not selected, tapping it will make it the current selection
    /// - Deletion is only allowed when there are multiple hardlinks
    ///
    /// The currently selected thumbnail displays a semi-transparent overlay with a trash icon.
    ///
    /// - Parameter hardlink: The hardlink whose thumbnail should be displayed
    /// - Returns: A view representing the thumbnail with appropriate styling and interaction handling
    @ViewBuilder
    func thumbnailView(for shareableItem: SharedState.ShareableItem) -> some View {
        Button(action: {
            if sharedState.shareableItems.count > 1 {
                if isShearableItemTheCurrentOne(shareableItem: shareableItem) {
                    // Only allow deletion if enough time has passed
                    if canDelete {
                        canDelete = false
                        sharedState.deleteShareableItem(shareableItem)
                    }
                } else {
                    withAnimation {
                        sharedState.currentShareableItem = shareableItem
                    }
                }
            }
        }) {
            Group {
                switch shareableItem {
                case .hardlink(let hardlink):
                    switch hardlink.thumbnail {
                    case .loading:
                        loadingView(isSelected: isShearableItemTheCurrentOne(shareableItem: shareableItem))
                    case .symbol(let icon):
                        iconView(icon: icon,
                                 isSelected: isShearableItemTheCurrentOne(shareableItem: shareableItem))
                    case .image(let image):
                        imageView(image: image,
                                  isSelected: isShearableItemTheCurrentOne(shareableItem: shareableItem),
                                  isVideo: hardlink.fileType == .video)
                    }
                case .linkMetadata:
                    iconView(icon: .link,
                             isSelected: isShearableItemTheCurrentOne(shareableItem: shareableItem))
                case .loading:
                    ProgressView()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8.0))
        .buttonStyle(.plain)
        .frame(height: 40.0)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        .disabled(sharedState.isSending)
    }
    
    /// Creates a loading state view for a thumbnail.
    ///
    /// Displays a gray square background with a centered progress indicator,
    /// shown while the actual thumbnail is being generated.
    ///
    /// - Returns: A view showing a loading indicator in a square container
    private func loadingView(isSelected: Bool) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
            
            ProgressView()
                .foregroundStyle(.secondary)
            
            if isSelected {
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                
                Image(systemIcon: .trashFill)
                    .font(.system(size: 16.0))
                    .foregroundStyle(Color.white)
                    .opacity(canDelete ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.3), value: canDelete)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    /// Creates a thumbnail view displaying a system icon.
    ///
    /// Used for file types that cannot have image thumbnails generated (e.g., documents, PDFs).
    /// Shows a representative system icon centered in a gray square background.
    ///
    /// - Parameter icon: The system icon to display
    /// - Returns: A view with the icon centered in a square container
    private func iconView(icon: SystemIcon, isSelected: Bool) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
            
            Image(systemIcon: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            if isSelected {
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                
                Image(systemIcon: .trashFill)
                    .font(.system(size: 16.0))
                    .foregroundStyle(Color.white)
                    .opacity(canDelete ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.3), value: canDelete)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    /// Creates a thumbnail view displaying an actual image.
    ///
    /// This view ensures that portrait images (where width < height) maintain
    /// a minimum aspect ratio of 1:1 (square) to prevent thumbnails from becoming
    /// too narrow in the horizontal scroll view. Landscape and square images
    /// preserve their original aspect ratio.
    ///
    /// - Parameter image: The UIImage to display as a thumbnail
    /// - Returns: A resizable image view with constrained aspect ratio
    private func imageView(image: UIImage, isSelected: Bool, isVideo: Bool) -> some View {
        let imageAspectRatio = image.size.width / image.size.height
        let constrainedAspectRatio = max(imageAspectRatio, 1.0)
        
        return GeometryReader { geometry in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.height * constrainedAspectRatio, height: geometry.size.height)
                    .clipped()
                
                if isVideo {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 20, height: 20)
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        
                        Image(systemIcon: .playFill)
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    }
                }
                
                if isSelected {
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                    
                    Image(systemIcon: .trashFill)
                        .font(.system(size: 16.0))
                        .foregroundStyle(Color.white)
                        .opacity(canDelete ? 1.0 : 0.3)
                        .animation(.easeInOut(duration: 0.3), value: canDelete)
                }
            }
        }
        .aspectRatio(constrainedAspectRatio, contentMode: .fit)
    }
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
    if #available(iOS 17.0, *) {
        HorizontalThumbnailsView(sharedState: sharedStateForPreviews)
    }
}

#endif
