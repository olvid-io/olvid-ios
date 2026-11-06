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


/// The link preview of a message, when it has one.
///
/// Exists for the reason ``MessageDocumentPreviewView`` does: the cell says *what a message shows*, and each of these views answers for one part of it, including
/// by showing nothing. It is also where the two routes a preview reaches a reader by are told apart, and where the corners are rounded.
struct MessageLinkPreviewView: View {

    /// Which corners this part joins to another part of the same message — see ``TheColumnOfPartsOfAMessage``. Fully rounded unless the cell says otherwise.
    @Environment(\.cornersOfThisPartOfTheMessage) private var corners

    let linkPreview: LinkPreviewInMessage?
    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    var body: some View {
        // A `Group`, and **not** a container — the one place on this screen where that is the right choice. A container with nothing in it is still a subview of the
        // cell's stack, which then puts its gap around it: six such views sit between a bubble and the date, so an ordinary text message paid six gaps for parts it
        // does not have. A `Group` contributes nothing at all when its branch is empty, and exactly one view when it is not. (A *row* of the list still needs a real
        // container — see `SingleDiscussionCellView`.)
        Group {
            switch linkPreview {
            case .attached(let attachment, let shape):
                previewOfTheAttachment(attachment, shape: shape)
                    .clipShape(MessageBubbleMetrics.shape(corners))
            case .toBeFetched(let url):
                LinkPreviewView(source: .toBeFetched(url: url), theMetadataCanBeRead: true, dataSource: dataSource, actions: actions)
                    .clipShape(MessageBubbleMetrics.shape(corners))
            case nil:
                EmptyView()
            }
        }
    }


    /// A preview the sender attached, which is watched as any other attachment is — the file has to arrive before there is anything to read.
    ///
    /// **No control, and no progress followed.** A preview is fetched whatever the size the reader has set as their limit
    /// (`fyleMessageJoinWithStatusesToDownload` ends in `|| join.isPreviewType`), so there is never anything to ask for; the legacy screen shows a spinner here and
    /// never a download button.
    ///
    /// An attachment the server has given up on shows nothing at all, as on the legacy screen, where `cancelledByServer` resolves to no configuration and the view
    /// is left out of the stack.
    private func previewOfTheAttachment(_ attachment: MessageAttachment, shape: LinkPreviewShape?) -> some View {
        FollowedAttachment(attachment: attachment,
                           sizeToRequest: .zero,
                           initialImage: nil,
                           dataSource: dataSource,
                           actions: actions,
                           showsTheStateControl: false) { _, phase in
            VStack(spacing: 0) {
                if phase != .cancelledByServer {
                    LinkPreviewView(source: .attached(attachment, shape: shape),
                                    theMetadataCanBeRead: phase == .available,
                                    dataSource: dataSource,
                                    actions: actions)
                }
            }
        }
    }

}
