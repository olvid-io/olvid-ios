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


/// Whether the messages the reader has chosen may be forwarded, and — when they may not — the one thing that stopped them.
///
/// **Facts, and the view does the wording**, which is ``WhatCanBeDeleted``'s shape and ``WhatAMessageOffers``' before it. The app answers what is so; this module
/// says the sentence. That is the direction of the whole migration: what a screen says belongs to the screen.
///
/// **All of them or none**, which is what one Forward over a whole selection promises. A partial forward — sending the eligible ones and quietly dropping the rest
/// — would leave the reader believing they had sent something they had not, and they cannot re-read the selection once the chooser is up.
///
/// **Two cases and not a struct**, unlike ``WhatCanBeDeleted``, because there is nothing else to carry: a deletion has kinds to offer and two facts its wording
/// turns on, where a forward either happens or is refused for exactly one reason. A state that cannot be in two of these at once should not be able to say that
/// it is.
///
public enum WhatCanBeForwarded: Equatable, Sendable {

    /// Every message chosen may be forwarded, and the reader is shown where to send them.
    case allOfThem

    /// At least one may not — and so none are sent, that being this type's own promise rather than a fact about the messages. The name states the fact and the
    /// documentation the consequence, so that neither has to be inferred from the other. See ``Reason``.
    case atLeastOneCannotBeForwarded(because: Reason)

    /// What stopped them, in the words this module has to find a sentence for.
    ///
    /// **Mirrored rather than shared.** The app calls this `WhyAMessageCannotBeForwarded`, in `ObvUICoreData`, which this module does not depend on and should
    /// not: it knows nothing of Core Data, and this is the fourth enum it has had to say for itself after ``MessageAction``, ``WhatAMessageOffers/Entry`` and
    /// ``WhatCanBeDeleted/Kind``. The app maps between them in one place and the compiler keeps that honest.
    ///
    /// **A reason about *the selection*, not about a message.** The plural rule reports whichever of these comes first in the app's own case order rather than
    /// whichever message happens to come first, a selection being a set with no order the reader would recognise — so the same ticks always give the same
    /// sentence. Which of several offending messages it was is deliberately not said: naming one would invite the reader to untick it and try again, and the
    /// next one would refuse them just the same.
    public enum Reason: Equatable, Sendable, CaseIterable {

        /// Something that is not a message at all was ticked — a contact joined, a call was missed, the shared settings changed.
        ///
        /// **The one a selection meets by accident**, and the reason this is worth wording carefully: a system message is a row a reader may tick like any
        /// other, so a run of messages dragged over one contains something unforwardable without anything having looked wrong.
        case aSystemMessageWasChosen

        /// One has been wiped, here or by whoever sent it.
        case oneHasBeenDeleted

        /// One is a received message that must be tapped before it can be read, and has not been.
        case oneHasNotBeenOpenedYet

        /// One is read-once, or visible for a limited time.
        case oneIsEphemeral

        /// One is a place, or a location being shared.
        case oneIsALocation

        /// One is a poll.
        case oneIsAPoll

        /// One carries an attachment that has not finished arriving — the only reason about a message that goes away by waiting.
        case oneHasAnAttachmentStillArriving

        /// **Whether they may go could not be established**, so they do not.
        ///
        /// Not about a message at all, and never seen in ordinary use. It exists because the rule that answers this question must **refuse** when it cannot run
        /// rather than shrug: the direction of that failure is content leaving the discussion. The reader is told plainly that the check did not happen and can
        /// simply ask again, which is the honest thing to say and the only one that is true of every message they ticked.
        case theyCouldNotBeChecked

    }

}
