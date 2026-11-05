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
import ObvDesignSystem
import ObvTypes


/// Whoever sent a received message, as named above the first of a run of their messages in a group discussion.
///
/// The colour is the sender's own, derived from their cryptographic identity by whoever builds this — the same colour their picture is drawn in, which is why the
/// two agree without this having to say so. A contact since deleted still has a sentence and an icon of their own, and gets the secondary label colour instead.
public struct MessageSender: Equatable, Sendable {

    let name: String
    let nameColor: Color
    let avatar: ObvAvatarViewModel

    /// Which contact this sender is, so that tapping their name or their picture can open them — see ``MessageSenderView``.
    ///
    /// **An `ObvContactIdentifier` and not an object ID**, this module knowing nothing of the persistence layer, and the
    /// screen this opens being keyed by exactly this type already: the legacy route takes an object ID only because a
    /// legacy cell had one, and converts it straight back into an identifier before presenting anything.
    ///
    /// **Optional for one case, and one only: a contact since deleted.** Such a sender is still *named* — a sentence and a
    /// crossed-out person where the picture goes — because the message is still there and still came from somebody. But
    /// there is no contact left to open, so the tap does nothing. Every live sender has one, one-to-one or not: a sender in
    /// a group is a contact cryptographically whether or not the reader has a one-to-one discussion with them, and the
    /// contact screen knows the difference — it offers *Invite* for one, and *Discuss* and *Call* for the other.
    let contactIdentifier: ObvContactIdentifier?

    public init(name: String, nameColor: Color, avatar: ObvAvatarViewModel, contactIdentifier: ObvContactIdentifier?) {
        self.name = name
        self.nameColor = nameColor
        self.avatar = avatar
        self.contactIdentifier = contactIdentifier
    }

}


/// What a received cell does about its sender, which is decided by the *discussion* and by the message above rather than by the message itself.
///
/// Three cases and not a `MessageSender?`, because "nothing to show" happens for two different reasons that the cell has to tell apart: a one-to-one discussion
/// keeps no room at all for a picture, whereas a message within a run keeps the room its neighbours use, so that the bubbles of a run line up under the name that
/// heads it. The legacy screen says the same thing with two booleans, `alwaysHideContactPictureAndNameView` and `previousMessageIsFromSameContact`.
public enum SenderOfAMessage: Equatable, Sendable {

    /// A one-to-one discussion, where the sender is never in doubt: nothing is drawn, and nothing is kept aside.
    case neverShown

    /// A group discussion, and this message opens a run from this person: their picture and their name go above the bubble.
    case shown(MessageSender)

    /// A group discussion, and the message above is from the same person: nothing is drawn, and the column their picture would be in is kept empty.
    case withinARunOfTheirMessages

    /// How much of the leading edge belongs to the sender's picture rather than to the message.
    ///
    /// `MessageCellConstants.contactPictureSize` plus `gapBetweenContactPictureAndMessage`, which the legacy screen insets the whole of a received cell by
    /// **whenever the discussion is a group one** — whether or not this particular message shows a name.
    var widthOfTheColumnOfThePicture: CGFloat {
        switch self {
        case .neverShown: return 0
        case .shown, .withinARunOfTheirMessages: return MessageSenderMetrics.pictureSize + MessageSenderMetrics.gapBetweenThePictureAndTheMessage
        }
    }

}


/// Metrics of the sender above a message. These values are those of the legacy screen, see `MessageCellConstants` and `ContactPictureAndNameView` within the app.
enum MessageSenderMetrics {

    /// `MessageCellConstants.contactPictureSize`, which is also the height of the name beside it.
    static let pictureSize: CGFloat = 30

    /// `MessageCellConstants.gapBetweenContactPictureAndMessage`
    static let gapBetweenThePictureAndTheMessage: CGFloat = 4

    /// The `pictureNameGap` of `ContactPictureAndNameView`, plus the `leadingPadding` of the label within `ContactNameView`.
    static let gapBetweenThePictureAndTheName: CGFloat = 6 + 4

    /// `MessageCellConstants.fontForContactName`, a rounded bold 17pt.
    ///
    /// A fixed size, as it is there: the legacy label asks for `adjustsFontForContentSizeCategory`, which does nothing to a font that was not built from a text
    /// style or through `UIFontMetrics`, and this one is `UIFont.rounded(ofSize:weight:)`.
    static let fontOfTheName: Font = .system(size: 17, weight: .bold, design: .rounded)

}


/// The picture and the name of whoever sent a message, above the first of a run of their messages — the legacy `ContactPictureAndNameView`.
///
/// **Tapping it opens that person**, as it does on the legacy screen. The picture and the name are one target rather than two, which is a departure: the
/// legacy affordance is `userDidTapOnContactImage`, the image alone.
///
/// What opens decides for itself what to offer, and this knows none of it: *Invite* for somebody the reader has no one-to-one discussion with, *Discuss* and *Call*
/// for somebody they do.
struct MessageSenderView: View {

    let sender: MessageSender
    let dataSource: any SingleDiscussionCellViewDataSource

    /// What the reader asks for by tapping a sender: to be shown that person.
    let actions: any SingleDiscussionCellViewActions

    var body: some View {
        // **The picture and the name are one target**, so that a reader who aims at either gets the person. The empty space
        // beside them belongs to nobody, as it does beside a bubble.
        //
        // **Always a `Button`, and never a branch on whether there is a contact to open.** A conditional wrapper would give
        // the view two shapes for one sender, and a sender within a `List` row is the last place to want that; the guard
        // lives in the action instead, where a contact since deleted simply asks for nothing. And `.buttonStyle(.plain)`,
        // without which a button in a row becomes the *row's* button and never fires at all.
        Button {
            guard let contactIdentifier = sender.contactIdentifier else { return }
            Task { await actions.userWantsToSeeAContact(contactIdentifier: contactIdentifier) }
        } label: {
            thePictureAndTheName
        }
        .buttonStyle(.plain)
    }


    private var thePictureAndTheName: some View {
        HStack(spacing: 0) {
            // The green shield of a sender certified by the reader's own keycloak, which `NewCircledInitialsView` draws on this picture too. Its **red** shield —
            // a contact no longer active — has no equivalent in `ObvAvatarView` and is therefore not drawn here.
            ObvAvatarView(model: sender.avatar,
                          style: .circle,
                          size: .custom(frameSize: .init(width: MessageSenderMetrics.pictureSize, height: MessageSenderMetrics.pictureSize)),
                          dataSource: dataSource,
                          showGreenShieldIfAppropriate: true)
            Text(verbatim: sender.name)
                .font(MessageSenderMetrics.fontOfTheName)
                .foregroundStyle(sender.nameColor)
                .lineLimit(1)
                .padding(.leading, MessageSenderMetrics.gapBetweenThePictureAndTheName)
        }
        .frame(height: MessageSenderMetrics.pictureSize)
    }

}


#if DEBUG

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        ForEach(Array(MessageSender.sampleData.enumerated()), id: \.offset) { _, sender in
            MessageSenderView(sender: sender, dataSource: singleDiscussionCellViewDataSourceForPreviews, actions: singleDiscussionCellViewDataSourceForPreviews)
        }
    }
    .padding()
}

#endif
