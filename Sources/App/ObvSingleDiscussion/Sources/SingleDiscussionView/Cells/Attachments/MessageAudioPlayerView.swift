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


/// The audio player of a message, when it has one.
///
/// Exists for the same reason ``MessageImagesView``, ``MessageDocumentPreviewView`` and ``MessageAttachmentCardsView`` do: the cell says *what a message shows*, and
/// each of these answers for one part of it, including by showing nothing.
///
/// It rounds nothing itself, unlike its neighbours: an audio player is drawn in a message bubble, which is rounded already.
struct MessageAudioPlayerView: View {

    let audio: MessageAttachment?
    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    var body: some View {
        // A `Group`, and **not** a container — the one place on this screen where that is the right choice. A container with nothing in it is still a subview of the
        // cell's stack, which then puts its gap around it: six such views sit between a bubble and the date, so an ordinary text message paid six gaps for parts it
        // does not have. A `Group` contributes nothing at all when its branch is empty, and exactly one view when it is not. (A *row* of the list still needs a real
        // container — see `SingleDiscussionCellView`.)
        Group {
            if let audio {
                AudioPlayerView(audio: audio, dataSource: dataSource, actions: actions)
            }
        }
    }

}
