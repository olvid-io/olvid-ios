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


/// The document preview of a message, when it has one.
///
/// Exists for the same reason ``MessageImagesView`` and ``MessageAttachmentCardsView`` do: the cell says *what a message shows*, and each of those views answers
/// for one part of it, including by showing nothing. It is also where the corners are rounded, on the group rather than on the preview, as everywhere else on this
/// screen.
struct MessageDocumentPreviewView: View {

    /// Which corners this part joins to another part of the same message — see ``TheColumnOfPartsOfAMessage``. Fully rounded unless the cell says otherwise.
    @Environment(\.cornersOfThisPartOfTheMessage) private var corners

    let document: MessageAttachment?
    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // A `Group`, and **not** a container — the one place on this screen where that is the right choice. A container with nothing in it is still a subview of the
        // cell's stack, which then puts its gap around it: six such views sit between a bubble and the date, so an ordinary text message paid six gaps for parts it
        // does not have. A `Group` contributes nothing at all when its branch is empty, and exactly one view when it is not. (A *row* of the list still needs a real
        // container — see `SingleDiscussionCellView`.)
        Group {
            if let document {
                documentPreviewView(document)
                    .clipShape(MessageBubbleMetrics.shape(corners))
            }
        }
    }


    /// Builds the preview, handing it whatever has already been decoded at that size. The lookup happens here, and not in the view built, so that nothing is
    /// fetched from within a view's initializer.
    private func documentPreviewView(_ document: MessageAttachment) -> some View {
        let pixelSize = CGSize(width: DocumentPreviewView.sizeToRequestForThePreview.width * displayScale,
                               height: DocumentPreviewView.sizeToRequestForThePreview.height * displayScale)
        return DocumentPreviewView(document: document,
                                   initialImage: dataSource.cachedImageForAttachment(document, pixelSize: pixelSize),
                                   dataSource: dataSource,
                                   actions: actions)
    }

}
