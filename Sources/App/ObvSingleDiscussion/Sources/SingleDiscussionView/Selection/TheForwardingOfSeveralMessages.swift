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


/// Where the reader is in the act of forwarding the messages they have chosen.
///
/// **One value rather than several booleans**, which is ``TheDeletionOfSeveralMessages``' shape and taken from it deliberately: a state that cannot be in two of
/// these at once should not be able to say that it is. Each case is a thing the reader can see, or in two places a thing they can see *nothing* of, which is
/// itself a decision recorded below.
enum TheForwardingOfSeveralMessages: Equatable {

    /// Nothing asked for, which is how the screen sits for all but a few seconds of its life.
    case notAsked

    /// Forward has been tapped and the messages are being asked whether they may go. Brief, and deliberately shows nothing — the same reasoning as
    /// ``TheDeletionOfSeveralMessages/findingOutWhatCanBeDone``, and cheaper still: this question is plain property reads where the deletion's is a simulation.
    case findingOutWhetherTheyCanBeForwarded

    /// More were chosen than may be sent at once. See ``theMostThatMayBeForwardedAtOnce``.
    case tooManyWereChosen(theMost: Int)

    /// One of them may not be forwarded, so none are, and the reader is told which rule refused them rather than left with a control that declines without a
    /// word. See ``WhatCanBeForwarded``.
    case nothingCanBeForwarded(WhatCanBeForwarded.Reason)

    /// The chooser is up, or the messages are on their way. The screen stays as it is and the menu stops answering: a second tap would ask to forward a
    /// selection that is already being forwarded, and the chooser is the app's to present rather than something this screen can show twice.
    case underWay

    /// It did not work. Rare enough that it says so and no more.
    case itFailed


    /// **How many messages may be forwarded in one go**, and the one number in this feature that is a product decision rather than a consequence.
    ///
    /// **A forward is not a deletion, and that is the whole of the reasoning.** A deletion for everyone is *one* protocol message carrying a reference per
    /// message — which is why the trash is uncapped and why a loop there would have been a fault rather than a slowness. A forward creates and sends a real
    /// message per source message **per destination**, so a hundred messages to three discussions is three hundred sends, awaited one after another, with the
    /// screen unable to answer for the length of it. There is no payload trick that makes that cheap; the only honest answers are a limit or a progress bar, and
    /// a limit is the one that does not require the reader to wait to find out.
    ///
    /// **Thirty is WhatsApp's number**, chosen for that reason rather than by measurement: a limit a reader has already met elsewhere needs less explaining than
    /// a better one they have not. It is one constant, and raising it costs nothing but the wait it buys.
    static let theMostThatMayBeForwardedAtOnce: Int = 30

}


/// The three alerts of a forward, and nothing else.
///
/// **A modifier of its own**, for the reason ``TheDeletionOfSeveralMessagesOnThisScreen`` is one: `SingleDiscussionView`'s body has already been too large for the
/// type checker once, which it answers by giving up on the whole expression rather than on the part that grew.
///
/// **Three alerts and no sheet**, which is where this parts company with the deletion. A deletion asks the reader to choose *how far it reaches* and needs a
/// `confirmationDialog` of kinds; a forward asks *where to*, and that question is the app's chooser — a `UIViewController` this module never sees. So everything
/// here is a refusal, and the one success path shows nothing at all.
struct TheForwardingOfSeveralMessagesOnThisScreen: ViewModifier {

    @Binding var forwarding: TheForwardingOfSeveralMessages

    private func says(_ said: Bool) -> Binding<Bool> {
        Binding { said } set: { stillSaid in
            guard !stillSaid else { return }
            forwarding = .notAsked
        }
    }

    /// The most that may be sent at once, or nil when that is not what refused the reader.
    ///
    /// **`presenting:`, so the number travels with the alert** rather than being read back from a state that may have moved on while it stood open — the same
    /// reasoning as the deletion's sheet, and as a press carrying the message it is a press *on*.
    private var theMostThatMayBeSent: Int? {
        guard case .tooManyWereChosen(let theMost) = forwarding else { return nil }
        return theMost
    }

    private var theReasonNothingMayGo: WhatCanBeForwarded.Reason? {
        guard case .nothingCanBeForwarded(let reason) = forwarding else { return nil }
        return reason
    }

    func body(content: Content) -> some View {
        content
            .alert(Text("TOO_MANY_MESSAGES_TO_FORWARD"), isPresented: says(theMostThatMayBeSent != nil), presenting: theMostThatMayBeSent) { _ in
                // No buttons: SwiftUI gives an alert its own *OK* when none are declared, which is the whole of what this needs.
            } message: { theMost in
                Text("AT_MOST_COUNT_MESSAGES_MAY_BE_FORWARDED_AT_ONCE_\(theMost)")
            }
            // **Says why, rather than greying the entry.** The reader chose these messages and asked for something; a control that declines without a word leaves
            // them to guess which of them is the problem — the decision Step 42c took for the trash, and the reason this reaches for a reason at all.
            .alert(Text("NOTHING_CAN_BE_FORWARDED"), isPresented: says(theReasonNothingMayGo != nil), presenting: theReasonNothingMayGo) { _ in
            } message: { reason in
                theExplanation(of: reason)
            }
            .alert(Text("THE_FORWARD_DID_NOT_HAPPEN"), isPresented: says(forwarding == .itFailed)) {
            }
    }


    /// What to say about the one thing that refused the whole selection.
    ///
    /// **Worded here and not by the app**, which is ``WhatCanBeForwarded``'s whole point: the app answers what is so, and a screen says the sentence.
    ///
    /// Each is written about *the selection* rather than about a message — *one of the messages you chose…* — because that is what the reader asked to forward and
    /// because naming a single culprit would invite them to untick it and meet the next one.
    private func theExplanation(of reason: WhatCanBeForwarded.Reason) -> Text {
        switch reason {
        case .aSystemMessageWasChosen:
            return Text("CANNOT_FORWARD_A_SYSTEM_MESSAGE")
        case .oneHasBeenDeleted:
            return Text("CANNOT_FORWARD_A_DELETED_MESSAGE")
        case .oneHasNotBeenOpenedYet:
            return Text("CANNOT_FORWARD_AN_UNOPENED_MESSAGE")
        case .oneIsEphemeral:
            return Text("CANNOT_FORWARD_AN_EPHEMERAL_MESSAGE")
        case .oneIsALocation:
            return Text("CANNOT_FORWARD_A_LOCATION")
        case .oneIsAPoll:
            return Text("CANNOT_FORWARD_A_POLL")
        case .oneHasAnAttachmentStillArriving:
            return Text("CANNOT_FORWARD_AN_ATTACHMENT_STILL_ARRIVING")
        case .theyCouldNotBeChecked:
            return Text("CANNOT_CHECK_WHETHER_MESSAGES_CAN_BE_FORWARDED")
        }
    }

}


extension View {

    /// The alerts that refuse a forward of the messages the reader has chosen — see ``TheForwardingOfSeveralMessagesOnThisScreen``.
    func forwardsTheMessagesTheReaderHasChosen(_ forwarding: Binding<TheForwardingOfSeveralMessages>) -> some View {
        modifier(TheForwardingOfSeveralMessagesOnThisScreen(forwarding: forwarding))
    }

}
