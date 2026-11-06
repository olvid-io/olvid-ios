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

import Foundation
import CoreGraphics

@MainActor
public protocol ComposeAttachmentViewDataSource: AnyObject {

    func getInitialComposeViewDataSourceFyleModel(attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) -> ComposeViewDataSourceFyleModel?
    func getAsyncStreamOfComposeViewDataSourceFyleModel(attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ComposeViewDataSourceFyleModel>)
    func finishAsyncStreamOfComposeViewDataSourceFyleModel(streamUUID: UUID)

    /// How far the export of this clip has got, between 0 and 1, or nil when nothing is being exported for it. Nil for anything that is not a
    /// video being exported right now, including a clip whose export has finished, failed or been abandoned.
    func getProgressOfTheVideoBeingPrepared(attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) -> Double?

    /// The same value as ``getProgressOfTheVideoBeingPrepared(attachmentIdentifier:)``: the current value, then every change. A new stream per
    /// call, which ends when its consumer stops iterating it.
    func getAsyncStreamOfTheProgressOfTheVideoBeingPrepared(attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) -> AsyncStream<Double?>

    /// The frames of an animated attachment, looping, each held as long as its file asks, until the caller stops listening.
    ///
    /// Decoded off the main actor, within a memory budget, and stopped when the task consuming the stream is cancelled. `maxPixelSize` bounds the longer side
    /// of each frame. An attachment with no file on disk finishes at once.
    func getAsyncStreamOfFramesForAnimatedImage(attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier, maxPixelSize: Int) -> AsyncStream<CGImage>

}
