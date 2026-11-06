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


/// A message that is gone, and the sentence saying how.
///
/// **Three cases, and not the four the legacy screen appears to offer.** `WipedView` there chooses between "Wiped message", "Message deleted by *someone*", "Message
/// deleted by You" and "Remotely wiped" — but the fourth of those cannot be produced, and the first cannot be produced for a message *received*:
///
/// - `.remoteWiped(remoteCryptoId:)` metadata is written in exactly one place, `PersistedMessage.wipeThisMessage(requesterCryptoId:)`, and only in its final `else`:
///   the requester is neither the owned identity — that branch *deletes* the message — nor, for a received message, its sender, which deletes it too. The deleter is
///   therefore always some other member of a group v2 with the right permission, and **"deleted by You" is unreachable**.
/// - `.wiped` metadata is written in exactly one place too, `PersistedMessageSent.wipeExpiredMessageSent()`: a **sent** message whose limited visibility ran out,
///   where the discussion keeps such messages rather than deleting them. A received message that expires is deleted.
///
/// Worth knowing about the second case: a group-v2 member with that permission can wipe a message the reader *sent*, so a sent bubble may name a deleter too.
public enum WipedMessage: Equatable, Sendable {

    /// The reader's own message, gone because the visibility its sender — themself — put on it ran out, in a discussion that keeps them. "Wiped message 🧹".
    case byTheExpiryOfItsOwnVisibility

    /// Deleted for everyone by someone who was allowed to: "Message deleted by *name*", or "Remotely wiped" when there is no name to give — a contact since deleted,
    /// or a member who has left the group.
    case byAContact(named: String?)

}
