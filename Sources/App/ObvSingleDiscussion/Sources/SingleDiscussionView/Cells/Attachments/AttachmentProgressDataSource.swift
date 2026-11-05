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


/// How far along the download of an attachment is.
///
/// A protocol of its own, and not two more methods among the ones that hand over models and images, because what it carries behaves unlike anything else on
/// this screen: it changes many times a second, it means nothing once the file has arrived, and it comes from the network layer rather than from the database.
/// Keeping it separate is what stops a number ticking during a download from travelling through the machinery that exists to describe messages.
@MainActor
public protocol AttachmentProgressDataSource: AnyObject {

    /// Follows the download of one attachment until the caller finishes with it.
    ///
    /// Unlike the streams of models and images on this screen, this one is finished explicitly rather than by cancelling the task that reads it: what feeds it
    /// lives outside the app's process boundary and cannot see that a view has gone away. So the `streamUUID` comes back here, to be handed to
    /// ``finishAsyncStreamOfProgressForAttachment(streamUUID:)``.
    ///
    /// It yields the progress so far as soon as it can, so an attachment paused half-way shows the arc it had rather than an empty one. It ends when the
    /// download does, which is not a failure: what says that the file has arrived is the state stream, not this.
    ///
    /// Only worth asking for while an attachment is downloading or waiting to be — an implementation is free to answer nothing for any other attachment.
    func getAsyncStreamOfProgressForAttachment(_ attachment: MessageAttachment) async throws -> (streamUUID: UUID, stream: AsyncStream<AttachmentProgress>)

    /// Ends a stream obtained above. Must be called, or whatever is feeding it goes on doing so.
    func finishAsyncStreamOfProgressForAttachment(streamUUID: UUID) async

}


/// How much of an attachment has been downloaded, as the view draws it.
///
/// A struct around a single value on purpose: the attachment *cards* will want a throughput and an estimated time remaining beside the fraction, and both are
/// derived by the app from the bytes the engine reports. Adding them here later costs nothing, where widening an `AsyncStream<Double>` would break every
/// caller.
public struct AttachmentProgress: Sendable, Equatable {

    /// Between 0 and 1.
    public let fractionCompleted: Double

    public init(fractionCompleted: Double) {
        self.fractionCompleted = fractionCompleted
    }

}
