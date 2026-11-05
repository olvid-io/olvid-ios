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
import AVKit
import UniformTypeIdentifiers
import ObvAppTypes
import ObvSystemIcon

struct VideoView: View {
    
    let media: SharedState.HardLink
    let mediaQuality: ObvMediaQuality
    @State private var isPlaying = false
    @State private var player: AVPlayer?
    @State private var duration: String?
    @State private var fileSize: String?
    @State private var playToEndObserver: NSObjectProtocol?

    /// Where the poster frame comes from. **This view no longer generates or holds one.**
    ///
    /// It used to, in a `@State` set from a `.task` and released by nothing at all — no `onDisappear`, no cache, no
    /// accounting — at a flat 2048×2048 cap, so up to 16 MB per video paged through, invisible to every budget in the
    /// module. A mixed share could therefore blow the limit with the photographs entirely blameless.
    @ObservedObject var store: PreviewImageStore

    @Environment(\.displayScale) private var displayScale

    /// The poster frame, or nil while the store has yet to build one.
    private var poster: CGImage? {
        store.picture(for: media.url)
    }

    /// The film's shape as the poster frame reports it, or nil until there is one. A video carries no `pixelSize` in
    /// its `HardLink`, so a poster frame is the first moment its proportions are known.
    private var shapeOfThePoster: CGFloat? {
        guard let poster, poster.height > 0 else { return nil }
        return CGFloat(poster.width) / CGFloat(poster.height)
    }

    /// The film's shape, **remembered**, so that giving the poster frame back cannot change the layout.
    ///
    /// It has to be latched rather than derived: the player is sized by this ratio, and the poster is released the
    /// moment playback starts — so a ratio read from the poster would go nil underneath a playing film and resize it
    /// mid-playback. Latched once and never cleared, a film's proportions not being something that changes.
    @State private var shapeOfTheFilm: CGFloat?

    var body: some View {
        ZStack {
            if media.fileType == .video {
                if isPlaying, let player {
                    // Video is playing
                    VideoPlayer(player: player)
                        .aspectRatio(shapeOfTheFilm, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .onDisappear {
                            stopVideo()
                        }
                } else {
                    // Show thumbnail
                    ZStack(alignment: .bottomTrailing) {
                        if let poster {
                            ZStack {
                                Image(poster, scale: displayScale, label: Text(verbatim: media.filename))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .horizontalOffsetScrollTransition()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        } else {
                            // Loading thumbnail
                            placeholderView(icon: .videoFill)
                        }
                        
                        // Duration and file size overlay
                        if duration != nil || fileSize != nil {
                            HStack(spacing: 4) {
                                if let duration {
                                    Text(duration)
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                }
                                if duration != nil && fileSize != nil {
                                    Text(verbatim: "•")
                                        .font(.caption2)
                                }
                                if let fileSize {
                                    Text(fileSize)
                                        .font(.caption2)
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(12)
                            .opacityScrollTransition()
                        }
                    }
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                    
                    // Play button overlay
                    Button {
                        playVideo()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 70, height: 70)
                                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                            
                            Image(systemIcon: .playFill)
                                .font(.system(size: 30))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        }
                    }
                    .opacityScrollTransition()
                }
            } else {
                // Not a video, display the placeholder
                placeholderView(icon: .videoFillSlash)
            }
        }
        .task(id: shapeOfThePoster) {
            // Latched, never cleared: see `shapeOfTheFilm`.
            if let shapeOfThePoster { shapeOfTheFilm = shapeOfThePoster }
        }
        .task(id: isPlaying) {
            // The player covers the poster frame completely, so holding it while a film plays is waste at exactly the
            // moment memory is tightest — an `AVPlayer` was measured taking the footprint from 45.5 to 95.7 MB, one
            // megabyte short of the warning. The store gives the bytes back and rebuilds the frame when playback ends.
            store.pictureIsCovered(isPlaying, forPageWith: media.url)
        }
        .onDisappear {
            // A safety net, and it is needed: `LazyHStack` can tear this view down while a film is still playing, and
            // a cancelled `.task` never runs its next iteration — so without this the page would stay marked covered
            // for the life of the share and its poster would never come back.
            store.pictureIsCovered(false, forPageWith: media.url)
        }
        .task {
            await loadVideoMetadata(mediaQuality: self.mediaQuality)
        }
        .onChange(of: mediaQuality) { newMediaQuality in
            // `.onChange` already fires only when the value actually changed. A `mediaQuality != newMediaQuality`
            // guard would be pointless here: `mediaQuality` is the injected `let`, already reconciled to the new
            // value by the time this closure runs, so the guard was always true and skipped every reload.
            Task {
                await loadVideoMetadata(mediaQuality: newMediaQuality)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopVideo)) { notification in
            if let hardlinkURL = notification.userInfo?["hardlinkURL"] as? URL,
               hardlinkURL == media.url {
                stopVideo()
            }
        }
    }
    
    private func stopVideo() {
        if let playToEndObserver {
            NotificationCenter.default.removeObserver(playToEndObserver)
            self.playToEndObserver = nil
        }
        player?.pause()
        player?.seek(to: .zero)
        isPlaying = false
        player = nil
    }
    
    private func playVideo() {
        let newPlayer = AVPlayer(url: media.url)
        player = newPlayer
        isPlaying = true
        newPlayer.play()

        // Remove any previous observer before adding a new one
        if let playToEndObserver {
            NotificationCenter.default.removeObserver(playToEndObserver)
        }

        // Listen for video end to show thumbnail again
        playToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newPlayer.currentItem,
            queue: .main
        ) { _ in
            Task { @MainActor in
                self.isPlaying = false
            }
        }
    }
    
    @ViewBuilder
    private func placeholderView(icon: SystemIcon) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                // The film's own shape once a poster frame has revealed it, and 16:9 only until then. It matters
                // because the poster is now given back while a film plays and rebuilt when it stops, so this
                // placeholder is shown *again* on a page whose proportions are already known — reserving 16:9 there
                // would make a portrait film's box jump on every play and stop.
                .aspectRatio(shapeOfTheFilm ?? PreviewImageStore.assumedAspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            
            Image(systemIcon: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
        }
    }
    
    private func loadVideoMetadata(mediaQuality: ObvMediaQuality) async {
        let asset = AVAsset(url: media.url)
        
        // Get duration
        do {
            let duration = try await asset.load(.duration)
            self.duration = formatDuration(duration)
        } catch {
            // Failed to get duration
        }
        
        // Get file size - estimate based on export preset if mediaQuality is standard
        do {
            if mediaQuality == .standard {
                // User selected standard quality, estimate the transcoded file size
                if let estimatedSize = await estimateExportedFileSize(asset: asset, preset: AVAssetExportPreset960x540) {
                    // Add "~" prefix to indicate this is an estimation
                    self.fileSize = "~" + formatFileSize(estimatedSize)
                } else {
                    // Fall back to original file size if estimation fails
                    let attributes = try FileManager.default.attributesOfItem(atPath: media.url.path)
                    if let fileSize = attributes[.size] as? Int64 {
                        self.fileSize = formatFileSize(fileSize)
                    }
                }
            } else {
                // HD quality selected, use original file size
                let attributes = try FileManager.default.attributesOfItem(atPath: media.url.path)
                if let fileSize = attributes[.size] as? Int64 {
                    self.fileSize = formatFileSize(fileSize)
                }
            }
        } catch {
            // Failed to get file size
        }
    }
    
    /// Estimates the file size after exporting with a specific preset
    /// - Parameters:
    ///   - asset: The video asset to estimate
    ///   - preset: The export preset (e.g., AVAssetExportPresetMediumQuality)
    /// - Returns: Estimated file size in bytes, or nil if estimation fails
    private func estimateExportedFileSize(asset: AVAsset, preset: String) async -> Int64? {
        // Get the duration
        guard let duration = try? await asset.load(.duration) else {
            return nil
        }
        
        let durationInSeconds = CMTimeGetSeconds(duration)
        
        // Estimate bitrate based on preset
        // These are approximate values - actual results may vary
        let estimatedBitrate: Double
        switch preset {
        case AVAssetExportPresetLowQuality:
            estimatedBitrate = 250_000 // 250 kbps
        case AVAssetExportPresetMediumQuality:
            estimatedBitrate = 1_000_000 // 1 Mbps
        case AVAssetExportPreset960x540:
            estimatedBitrate = 5_700_000 // 5.7 Mbps
        default:
            estimatedBitrate = 1_000_000 // Default to 1 Mbps
        }
        
        // Calculate estimated file size: (bitrate * duration) / 8 to convert bits to bytes
        let estimatedSizeInBytes = Int64((estimatedBitrate * durationInSeconds) / 8)
        
        return estimatedSizeInBytes
    }
    
    private func formatDuration(_ duration: CMTime) -> String {
        let totalSeconds = Int(CMTimeGetSeconds(duration))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#if DEBUG

#Preview {
    VideoView(media: [SharedState.HardLink].sampleData.first!, mediaQuality: .standard, store: .shared)
}

#endif
