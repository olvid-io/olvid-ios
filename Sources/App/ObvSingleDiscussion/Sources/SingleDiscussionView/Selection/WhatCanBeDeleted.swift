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


/// What may be done to the messages the reader has chosen, when what they have asked for is to delete them.
///
/// **Facts, and the view does the wording** — which is ``WhatAMessageOffers``' shape exactly, and taken from it deliberately. The app answers *which kinds are
/// open* and the two things their names turn on; this module says the sentences. That is the direction of the whole migration: what a screen says belongs to the
/// screen, and the app is left answering questions only it can answer.
///
/// **Asked when the trash is tapped, and never before.** The answer is arrived at by simulating each deletion, which is real work on the main thread against the
/// view context — see ``SingleDiscussionViewDataSource/whatCanBeDeleted(cellIdentifiers:discussionIdentifier:)``. Asking it as the selection changes would run it
/// on every tick.
public struct WhatCanBeDeleted: Equatable, Sendable {

    /// The kinds on offer, cheapest first, and **empty when there are none** — which is not a failure and has to be said rather than shown as a disabled button.
    /// See ``TheDeletionOfSeveralMessages``.
    public let kinds: [Kind]

    /// Whether this reader has another device that can be reached, which changes what *delete everywhere* is called. It is one of the two facts legacy's
    /// `deletionActionTitle(for:ownedIdentityHasHasAnotherReachableDevice:multipleContacts:)` switches on, and it is a fact about the reader rather than about
    /// the messages — which is why it cannot be worked out here.
    public let readerHasAnotherDevice: Bool

    /// Whether this discussion is with more than one person, which is the other. A group of one is worded as a single contact, exactly as legacy words it.
    public let discussionHasSeveralContacts: Bool

    /// How many files the deletion would take with it, which is in the question rather than in the buttons — legacy asks *this will also delete n attachments*.
    /// Zero for a selection carrying none, and the question is then the shorter one.
    public let numberOfAttachments: Int

    public init(kinds: [Kind], readerHasAnotherDevice: Bool, discussionHasSeveralContacts: Bool, numberOfAttachments: Int) {
        self.kinds = kinds.sorted()
        self.readerHasAnotherDevice = readerHasAnotherDevice
        self.discussionHasSeveralContacts = discussionHasSeveralContacts
        self.numberOfAttachments = numberOfAttachments
    }

    /// Nothing on offer, which is what a selection holding something undeletable comes to — a location the reader is still sharing, above all.
    public static let nothing = WhatCanBeDeleted(kinds: [], readerHasAnotherDevice: false, discussionHasSeveralContacts: false, numberOfAttachments: 0)

    /// How far a deletion reaches.
    ///
    /// **Mirrored rather than shared.** The app calls this `DeletionType`, in `ObvUICoreData`, which this module does not depend on and should not: it knows
    /// nothing of Core Data and this is the third enum it has had to say for itself, after ``MessageAction`` and ``WhatAMessageOffers/Entry``. The app maps
    /// between them in one place and the compiler keeps that honest. Moving `DeletionType` into `ObvAppTypes` — which both modules already depend on — would
    /// remove the mapping altogether, and is a cleanup of its own rather than a part of this step.
    ///
    /// `Comparable` so that the order is a property of the kinds and not of whoever assembles the list: cheapest first, which is the order legacy sorts its own
    /// buttons into.
    public enum Kind: Comparable, Sendable, CaseIterable {

        /// Gone from this device, and from nowhere else. Always on offer for a message that can be deleted at all.
        case fromThisDeviceOnly

        /// Gone from every device this reader owns.
        case fromAllOwnedDevices

        /// Gone from everywhere, including the devices of whoever the discussion is with. The only one that sends anything.
        case fromAllOwnedDevicesAndAllContactDevices

    }

}
