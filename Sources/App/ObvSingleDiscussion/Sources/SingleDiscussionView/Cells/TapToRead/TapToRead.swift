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
import CoreData


/// A message the reader has to ask to see: one its sender made read-once, or visible for a while only.
///
/// **Nothing of what it says is in here**, and that is the whole point. The body, the link preview and the pictures exist in the database from the moment such a
/// message arrives — nothing puts them there when it is read — so a screen that builds a model without asking whether reading requires an action shows a reader
/// what they have not asked for, and shows the *sender* something they were promised would be shown once.
public struct TapToRead: Equatable, Sendable {

    /// Identifies the message, which is what revealing names.
    public let identifier: Identifier

    public enum Identifier: Hashable, Sendable {
        /// The object ID of a `PersistedMessageReceived`, enforced by the data source — this module knows nothing of the persistence layer. Object IDs must not
        /// escape into anything persisted or crossing a process boundary.
        case objectID(_ objectID: NSManagedObjectID)
        case forPreview(_ uuid: UUID)
    }

    /// Whether the bubble inviting the tap is drawn at all.
    ///
    /// It is `hasBodyText` on the legacy screen — a message with something written in it says "Tap to see the message", and a message whose content is *only*
    /// attachments says nothing, its covered attachments being the whole of what there is to tap. Whether there is a body is the one thing about the content this
    /// model may carry, since it is what the sender's contract makes visible.
    public let showsTheBubble: Bool

    /// What the message has attached, kept for its **shapes** alone: the presentations of Steps 5 to 8 lay themselves out from this, and are then covered — no
    /// picture asked for, no filename shown, nothing playable.
    ///
    /// It carries no body and no link preview: the legacy screen hides both outright, and a preview is the rendering of a URL *in* the body.
    public let covered: MessageContent.Ordinary

    public init(identifier: Identifier, showsTheBubble: Bool, covered: MessageContent.Ordinary) {
        self.identifier = identifier
        self.showsTheBubble = showsTheBubble
        self.covered = covered
    }

}


// MARK: - Covering the attachments of a message that has not been read

extension EnvironmentValues {

    /// Whether the attachments drawn below are those of a message the reader has yet to ask to see.
    ///
    /// **An environment value rather than a parameter**, which is unusual here and deliberate. Covering is a property of the *message*, and it has to reach the four
    /// presentations of an attachment — an image, a card, a document preview, a player — plus what they are built on. Threading a flag through five views and their
    /// initialisers would put a message's business into the signature of everything that draws a file; an ambient condition is what the environment is for.
    ///
    /// What reads it is almost all in one place, `FollowedAttachment`, which is what every presentation follows its attachment through: it asks for no picture, shows
    /// none, offers no control and follows no download. Two others read it to hide what they draw *beside* a picture — a filename, a waveform.
    var attachmentsAreCoveredUntilRead: Bool {
        get { self[AttachmentsAreCoveredUntilReadKey.self] }
        set { self[AttachmentsAreCoveredUntilReadKey.self] = newValue }
    }

}


private struct AttachmentsAreCoveredUntilReadKey: EnvironmentKey {
    static let defaultValue = false
}
