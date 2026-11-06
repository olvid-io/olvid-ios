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
import UniformTypeIdentifiers
import ObvSystemIcon
import ImageIO

struct ImageView: View {

    let media: SharedState.HardLink

    /// Where the picture comes from. **This view decodes nothing and holds nothing.**
    ///
    /// It used to own a `loadState`, an `isVisible` flag and a `.task` that decoded, and consult a cache as a fallback
    /// for what it had not decoded itself. Two producers for one picture is what allowed a page's own decode and the
    /// pager's prefetch of the same file to run at once, and holding a copy is what made the view's idea of the truth
    /// diverge from the store's. Reading the store from `body` removes both: there is one owner, and a picture the
    /// store has given up cannot still be on screen.
    @ObservedObject var store: PreviewImageStore

    /// Opacity of the picture, animated from 0 to 1 when it first appears.
    @State private var imageOpacity: Double = 0

    @Environment(\.displayScale) private var displayScale

    /// The picture, or nil while the store has yet to build one.
    private var picture: CGImage? {
        store.picture(for: media.url)
    }

    var body: some View {
        Group {
            if media.fileType == .image {
                // The placeholder stays mounted underneath for this page's whole lifetime, and the picture fades in on
                // top of it. Nothing here is inserted or removed as the picture arrives, so the fade does not depend on
                // SwiftUI's structural-transition machinery — which is what made the earlier `.transition` /
                // `withAnimation` attempts fire only some of the time. It also means there is never a frame where the
                // placeholder has gone but the picture is not yet opaque, and the two already share a box because the
                // placeholder uses the real aspect ratio.
                ZStack {
                    placeholderView(icon: store.failedToBuildAPicture(for: media.url) ? .photoBadgeExclamationMark : .photo)

                    if let picture {
                        ZStack {
                            // `Image(_:scale:label:)` over a `CGImage`, as the house rule requires: the
                            // pipeline deals in `CGImage` and the platform type appears only at the point of display.
                            // Passing `displayScale` also makes the picture's ideal size equal the box it was decoded
                            // for, so nothing is scaled at draw time.
                            Image(picture, scale: displayScale, label: Text(verbatim: media.filename))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .horizontalOffsetScrollTransition()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .opacity(imageOpacity)
                        .onAppear {
                            // Driven from `onAppear`, inside SwiftUI's own update cycle, rather than from the async
                            // continuation that produced the picture — a transaction started there is lost whenever the
                            // change is folded into an update already in flight.
                            withAnimation(.easeOut(duration: 0.2)) {
                                imageOpacity = 1
                            }
                        }
                        .onDisappear {
                            imageOpacity = 0
                        }
                    }
                }
            } else {
                // Not an image, display the placeholder
                placeholderView(icon: .photoBadgeExclamationMark)
            }
        }
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }


    @ViewBuilder
    private func placeholderView(icon: SystemIcon) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                // The real shape of the image, read from its header up front, so the placeholder occupies
                // the box the decoded image will occupy and nothing resizes when it arrives. The fallback for an
                // unknown shape is named rather than written, because `PreviewImageStore` sizes its decode against
                // this very box and the two must not drift.
                .aspectRatio(media.aspectRatio ?? PreviewImageStore.assumedAspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            
            Image(systemIcon: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG

#Preview {
    ImageView(media: [SharedState.HardLink].sampleData.first!, store: .shared)
}

#endif
