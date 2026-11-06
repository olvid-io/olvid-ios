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


/// The message a message answers, as shown above it — the legacy `ReplyToBubbleView`, rearranged to the design of 2026-08.
///
/// **Everything here is resolved when the model is built**, on a background context, and nothing of it is fetched by a view. The legacy screen does the opposite: it
/// asks `DiscussionCacheDelegate.requestReplyToBubbleViewConfiguration(message:)`, which answers what it can at once and reconfigures the cell when the rest lands.
/// That is a second cadence, and on this screen it is not needed — a model is built ahead of the cell that wants it, and the *picture* is the one part that genuinely
/// arrives later, which the attachment machinery of Steps 3 to 8 already follows on its own.
///
/// The four states the legacy configuration has are kept, since a reply outlives what it answers: a message may not have arrived, may have been deleted, may have been
/// wiped by whoever sent it, and may simply be here. See ``WhatItSays``.
public struct MessageRepliedTo: Equatable, Sendable {

    /// Which message is being answered, so that the reader can be taken there. Nil when there is nowhere to go — a message that is not here, or is gone.
    ///
    /// Carried but not yet used: tapping the header is **Step 17b**, with the means for something inside a cell to move the list, which Step 23b needs too.
    public let identifier: Identifier?

    /// Whose message is being answered, which is what colours the whole header. See ``Sender``.
    public let sender: Sender

    /// The line under the name. See ``WhatItSays``.
    public let whatItSays: WhatItSays

    /// The picture beside the words: the first attachment of the message answered, and nil when it has none.
    ///
    /// A ``MessageAttachment`` and not an image, so that the picture is asked for, followed and cached by the machinery every other attachment of this screen goes
    /// through — a thumbnail here is the same question as a thumbnail anywhere else, and the legacy screen's separate hardlink-and-QuickLook path for it is not
    /// needed. Nil for a message the reader has yet to ask to see: its files are in the database, and showing one would be showing what its sender covered.
    public let thumbnail: MessageAttachment?

    public init(identifier: Identifier?, sender: Sender, whatItSays: WhatItSays, thumbnail: MessageAttachment?) {
        self.identifier = identifier
        self.sender = sender
        self.whatItSays = whatItSays
        self.thumbnail = thumbnail
    }


    public enum Identifier: Hashable, Sendable {
        /// The object ID of the `PersistedMessage` being answered, enforced by the data source — this module knows nothing of the persistence layer.
        case objectID(_ objectID: NSManagedObjectID)
        case forPreview(_ uuid: UUID)
    }


    /// The row of the list holding the message being answered, which is where a tap on the header takes the reader.
    ///
    /// **The identifier already is the answer.** A cell of a message is identified by that message's object ID, and so is this — both are built by the same data
    /// source, so the two cannot disagree and nothing has to be looked up. Nil when there is no message to go to, and for a preview, which has no list.
    ///
    /// A row the list does not hold — a message deleted, or one this screen does not show — moves nothing, silently. See ``WhereTheReaderWantsToGo/goTo(_:)``.
    var rowOfTheMessageRepliedTo: SingleDiscussionView.CellIdentifier? {
        switch identifier {
        case .objectID(let objectID): return .objectID(objectID)
        case .forPreview, nil: return nil
        }
    }


    /// Whoever wrote the message being answered.
    ///
    /// The **colours of the header come from this**, and they are the legacy screen's: a contact's own colour on the bar and on their name, over the reply-to
    /// background; the reader's own message filled Olvid blue with a white name, which is the one case the new design does not show and which therefore stays as it
    /// was. See ``MessageRepliedToStyle``.
    public enum Sender: Equatable, Sendable {

        /// A contact, named, in the colour derived from their cryptographic identity — the same colour their name has above their own messages.
        case aContact(name: String, color: Color)

        /// A contact who can no longer be found, named as far as they can be. Legacy gives them a white name over a neutral bar.
        case aContactNoLongerKnown(name: String)

        /// One of the reader's own messages, named as the app names them.
        case theReader(name: String)

        /// Nobody to name: the message is not here, or is gone. The header then shows its sentence and nothing else.
        case nobody

    }


    /// What the second line of the header shows.
    ///
    /// The wording of the last three is this module's, as the wiped bubble's is; the first is the message's own words and comes from the data source.
    public enum WhatItSays: Equatable, Sendable {

        /// What the message says: its body, or the name of its first file when it has no body. Settled with the design — the words first, the file name as the
        /// fallback, never both.
        case theseWords(String)

        /// It was wiped by somebody, named when they can be named.
        case itWasWipedBy(contactNamed: String?)

        /// It was deleted, or wiped by the expiry of its own visibility — which the legacy screen words the same way.
        case itWasDeleted

        /// It has not arrived yet. A reply can be received before the message it answers, and the sentence says so rather than pretending the message is gone.
        case itIsNotHereYet

    }

}
