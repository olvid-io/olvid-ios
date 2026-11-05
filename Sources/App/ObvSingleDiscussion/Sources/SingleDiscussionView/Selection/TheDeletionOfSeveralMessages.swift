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


/// Where the reader is in the act of deleting the messages they have chosen.
///
/// **One value rather than three booleans**, for the reason ``WhatAMessageOffers`` gives about entries: a state that cannot be in two of these at once should not
/// be able to say that it is. Each case is a thing the reader can see.
enum TheDeletionOfSeveralMessages: Equatable {

    /// Nothing asked for, which is how the screen sits for all but a few seconds of its life.
    case notAsked

    /// The trash has been tapped and the kinds are being worked out. Brief, and deliberately shows nothing: the answer takes a few simulated deletions, and a
    /// spinner that appears and vanishes at that rate reads as a fault rather than as progress. The same reasoning as the search bar's, which shows nothing
    /// between a keystroke and its results.
    case findingOutWhatCanBeDone

    /// The sheet, offering what may be done.
    case choosing(WhatCanBeDeleted)

    /// Nothing may be done, and the reader is told so rather than left with a button that does nothing. See ``WhatCanBeDeleted/kinds``.
    case nothingCanBeDeleted

    /// The deletion is under way. The screen stays as it is and the bar stops answering — the messages are about to leave the transcript, and a reader who
    /// tapped twice would ask for the second deletion of a selection that no longer exists.
    case deleting

    /// It did not work. Rare enough that it says so and no more.
    case itFailed

}


/// The two sheets of a deletion, and nothing else.
///
/// **A modifier of its own, and not merely for tidiness.** `SingleDiscussionView`'s body has already been too large for the type checker once, which it answers by
/// giving up on the whole expression rather than on the part that grew; ``TheContextMenuOfAMessageOnThisScreen`` was extracted for exactly that reason and this
/// follows it.
struct TheDeletionOfSeveralMessagesOnThisScreen: ViewModifier {

    @Binding var deletion: TheDeletionOfSeveralMessages

    /// How many messages the question is about, which is in its wording.
    let numberOfSelectedMessages: Int

    /// Carries out what the reader chose.
    let delete: (WhatCanBeDeleted.Kind) -> Void

    /// What is on offer, or nil when no sheet is up. Written back only to dismiss: `confirmationDialog` wants a binding it can clear when the reader taps outside
    /// it or picks Cancel, and there is nothing else it may do to this state.
    private var whatIsOnOffer: Binding<WhatCanBeDeleted?> {
        Binding {
            guard case .choosing(let offer) = deletion else { return nil }
            return offer
        } set: { newValue in
            guard newValue == nil, case .choosing = deletion else { return }
            deletion = .notAsked
        }
    }

    private func says(_ said: Bool) -> Binding<Bool> {
        Binding { said } set: { stillSaid in
            guard !stillSaid else { return }
            deletion = .notAsked
        }
    }

    func body(content: Content) -> some View {
        content
            // **`presenting:`, so that what is on offer travels with the sheet** rather than being read back from state that may have moved on while it stood
            // open — the same reasoning as a press carrying the message it is a press *on*. A sheet can stand there for as long as the reader likes.
            .confirmationDialog(theQuestion, isPresented: says(whatIsOnOffer.wrappedValue != nil), titleVisibility: .visible, presenting: whatIsOnOffer.wrappedValue) { offer in
                // One button per kind, cheapest first — the order is ``WhatCanBeDeleted/Kind``'s own, so nothing here can put them out of it.
                ForEach(offer.kinds, id: \.self) { kind in
                    Button(role: .destructive) {
                        delete(kind)
                    } label: {
                        theTitle(of: kind, given: offer)
                    }
                }
                // Added rather than left to the system. `confirmationDialog` provides one when no button has the cancel role, and relying on that means the sheet
                // silently loses its way out on the day somebody adds a cancelling button for another reason.
                Button(role: .cancel) {
                    deletion = .notAsked
                } label: {
                    Text("Cancel")
                }
            } message: { offer in
                // Only when there are files to speak of: a selection of plain messages asks the shorter question, as legacy's does.
                if offer.numberOfAttachments > 0 {
                    Text("DELETE_WILL_ALSO_DELETE_COUNT_ATTACHMENTS_\(offer.numberOfAttachments)")
                }
            }
            // **Says why, rather than greying the trash.** The reader chose these messages and asked for something; a control that declines without a word leaves
            // them to guess which message is the problem. See ``WhatCanBeDeleted/kinds``.
            .alert(Text("NOTHING_CAN_BE_DELETED"), isPresented: says(deletion == .nothingCanBeDeleted)) {
                // No buttons: SwiftUI gives an alert its own *OK* when none are declared, which is the whole of what this needs.
            } message: {
                Text("NOTHING_CAN_BE_DELETED_EXPLANATION")
            }
            .alert(Text("THE_DELETION_DID_NOT_HAPPEN"), isPresented: says(deletion == .itFailed)) {
            }
    }


    /// *Delete 3 messages?* — the question, which carries the count because that is the one thing the reader cannot check while a sheet covers the transcript.
    private var theQuestion: Text {
        Text("DELETE_COUNT_MESSAGES_QUESTION_\(numberOfSelectedMessages)")
    }


    /// What a kind is called, which is **the app's six strings, copied here with their translations**.
    ///
    /// The four variants of *everywhere* are legacy's, keyed on the same two facts:
    /// `CommonString.AlertButton.deletionActionTitle(for:ownedIdentityHasHasAnotherReachableDevice:multipleContacts:)`. They are worded here rather than by the
    /// app because wording is what a screen does — see ``WhatCanBeDeleted``, which carries the facts and no sentences.
    private func theTitle(of kind: WhatCanBeDeleted.Kind, given offer: WhatCanBeDeleted) -> Text {
        switch kind {
        case .fromThisDeviceOnly:
            return Text("DELETE_FROM_THIS_DEVICE_ONLY")
        case .fromAllOwnedDevices:
            return Text("DELETE_FROM_ALL_OWNED_DEVICES")
        case .fromAllOwnedDevicesAndAllContactDevices:
            switch (offer.readerHasAnotherDevice, offer.discussionHasSeveralContacts) {
            case (false, false):
                return Text("DELETE_FROM_THIS_DEVICE_AND_CONTACT_DEVICES")
            case (false, true):
                return Text("DELETE_FROM_THIS_DEVICE_AND_ALL_CONTACTS_DEVICES")
            case (true, false):
                return Text("DELETE_FROM_ALL_OWNED_DEVICES_AND_CONTACT_DEVICES")
            case (true, true):
                return Text("DELETE_FROM_ALL_OWNED_DEVICES_AND_ALL_CONTACTS_DEVICES")
            }
        }
    }

}


extension View {

    /// The sheets that delete the messages the reader has chosen — see ``TheDeletionOfSeveralMessagesOnThisScreen``.
    func deletesTheMessagesTheReaderHasChosen(_ deletion: Binding<TheDeletionOfSeveralMessages>, numberOfSelectedMessages: Int, delete: @escaping (WhatCanBeDeleted.Kind) -> Void) -> some View {
        modifier(TheDeletionOfSeveralMessagesOnThisScreen(deletion: deletion, numberOfSelectedMessages: numberOfSelectedMessages, delete: delete))
    }

}
