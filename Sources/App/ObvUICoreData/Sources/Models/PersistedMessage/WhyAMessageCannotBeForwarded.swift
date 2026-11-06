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


/// The one thing that stops a message being forwarded.
///
/// See ``PersistedMessage/whyThisMessageCannotBeForwarded``, which is where the rule lives and which explains why this is the primitive and
/// `forwardActionCanBeMadeAvailable` the derived value.
///
/// **The order of the cases is the order the rule asks in**, and it is load-bearing rather than decorative: a message may fail several clauses at once — a wiped
/// read-once message fails two — and what is reported is the **first** of them. The order puts the facts that will never change again ahead of the ones that may,
/// so a reader is told *this message was deleted* rather than *this message is ephemeral*, which would invite them to wait for something that is not coming. The
/// one that genuinely resolves itself, an attachment still arriving, is last for the same reason.
///
/// **Not `Comparable`.** The order matters to whoever asks, and asking is done in one place; making the ordering part of the type would invite a second place to
/// sort by it and quietly disagree with the rule.
public enum WhyAMessageCannotBeForwarded: Sendable, Equatable, CaseIterable {

    /// The discussion talking about itself — a contact joined, a call was missed, the shared settings changed. There is nothing to carry elsewhere.
    ///
    /// **The one a selection meets by accident**, and the reason this enum is worth having at all: a system message is a row a reader may tick like any other, so
    /// a reader who selects a run of messages spanning one has chosen something unforwardable without noticing.
    case itIsASystemMessage

    /// Wiped, locally or by whoever sent it. There is no longer anything to forward.
    case itHasBeenDeleted

    /// A received message that must be tapped before it can be read, and has not been. Forwarding it would be reading it on the reader's behalf.
    ///
    /// Received messages only: the reader has, by construction, seen what they sent.
    case itHasNotBeenOpenedYet

    /// Read once, or visible for a limited time. What makes it ephemeral is a promise to its sender, and forwarding it out of the discussion breaks that promise.
    ///
    /// **`existenceDuration` alone is not this**, on either side: a message that will one day be deleted is not one whose *reading* is restricted, and the
    /// existing rule has always allowed it to be forwarded. Only `readOnce` and `visibilityDuration` count.
    case itIsEphemeral

    /// A place, or a location being shared. What it means is *where I am*, which is not a thing to repeat elsewhere on somebody's behalf.
    case itIsALocation

    /// A poll. Its answers belong to the discussion it was asked in.
    case itIsAPoll

    /// An attachment that has not finished arriving. Forwarding would send a file the reader does not yet hold.
    ///
    /// **The only reason on this list that resolves itself by waiting**, which is why it is last among the ones that are about a message: waiting is the answer,
    /// and it is worth being the thing the reader is told when it is the only obstacle.
    case oneOfItsAttachmentsIsNotAvailableYet

    /// **The question could not be asked**, so the answer is no.
    ///
    /// The one case here that is not about a message at all, which is why it is last and why nothing that examines a message ever returns it. It exists so that
    /// a rule which cannot do its work **refuses** rather than shrugging: the alternative is a nil that a caller reads as *everything may go*, and the direction
    /// of that failure is content leaving the discussion — an ephemeral message forwarded out of it because a check did not run. The deletion's own plural rule
    /// fails the same way round, answering an empty set of kinds when it cannot proceed.
    ///
    /// It cannot arise in ordinary use: the callers are main-actor bound and read the view context. It is here for the direction of the failure, not for the
    /// likelihood of it.
    case theQuestionCouldNotBeAsked

}
