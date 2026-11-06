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
import ObvSystemIcon
import ObvDesignSystem

struct FileView: View {
    
    let media: SharedState.HardLink
    @State private var fileSize: String?
    @State private var modificationDate: String?
    @State private var showQuickLook: URL?

    /// Where the rendered preview comes from. This view renders nothing and holds nothing — see `ImageView`, which
    /// was changed for the same reason, and `PreviewImageStore`, which is now the only thing that renders a preview.
    @ObservedObject var store: PreviewImageStore

    /// Opacity of the rendered preview, animated from 0 to 1 when it is first shown.
    @State private var thumbnailOpacity: Double = 0

    @Environment(\.displayScale) private var displayScale

    /// The preview to draw, or nil while the store has yet to render one.
    private var picture: CGImage? {
        store.picture(for: media.url)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Thumbnail or icon
            Button {
                showQuickLook = media.url
            } label: {
                // The icon placeholder stays mounted underneath and the rendered preview fades in on top of
                // it, the same arrangement `ImageView` uses: nothing is inserted or removed as the render
                // arrives, so the fade does not depend on SwiftUI's structural-transition machinery, which
                // fires only intermittently.
                ZStack {
                    // Display icon placeholder
                    Image(systemIcon: media.contentType.systemIcon)
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                        .padding(40)
                        .background {
                            RoundedRectangle(cornerRadius: 20.0)
                                .fill(Color.gray.opacity(0.2))
                                .aspectRatio(1, contentMode: .fit)
                        }

                    if let picture {
                        // Display thumbnail
                        ZStack {
                            Image(picture, scale: displayScale, label: Text(verbatim: media.filename))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .horizontalOffsetScrollTransition()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .opacity(thumbnailOpacity)
                        .onAppear {
                            // Driven from `onAppear`, inside SwiftUI's own update cycle, rather than from
                            // the async continuation that produced the render — a transaction started there
                            // is lost whenever the change is folded into an update already in flight.
                            withAnimation(.easeOut(duration: 0.2)) {
                                thumbnailOpacity = 1
                            }
                        }
                        .onDisappear {
                            thumbnailOpacity = 0
                        }
                    }
                }
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            
            // File information
            VStack(spacing: 4) {
                Text(media.filename)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 8) {
                    if let modificationDate {
                        Text(modificationDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if modificationDate != nil && fileSize != nil {
                        Text(verbatim: "•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let fileSize {
                        Text(fileSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .opacityScrollTransition()
        }
        .task(id: media.url) {
            await loadFileMetadata()
        }
        .quickLookPreviewBackedByUIKitOnCatalyst($showQuickLook)
    }
    
    private func loadFileMetadata() async {
        // Get file size and modification date
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: media.url.path)
            
            if let fileSize = attributes[.size] as? Int64 {
                self.fileSize = formatFileSize(fileSize)
            }
            
            if let modificationDate = attributes[.modificationDate] as? Date {
                self.modificationDate = formatDate(modificationDate)
            }
        } catch {
            // Failed to get file metadata
        }
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

#if DEBUG

#Preview {
    FileView(media: [SharedState.HardLink].sampleData.first!, store: .shared)
        .padding()
}

#endif
