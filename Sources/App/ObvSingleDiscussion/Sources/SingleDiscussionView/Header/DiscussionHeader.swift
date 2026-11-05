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
import ObvDesignSystem


/// Who the reader is talking to, as it is shown above the discussion.
///
/// **One streamed value, and not five reads.** Everything here comes from a handful of objects and every one of them changes under the reader: a contact is
/// renamed, a group gains a member, a discussion is locked. The legacy screen answers that by re-running `configureNavigationTitle()` from five different places,
/// on notifications; this screen answers it the way it has answered everything since Step 0.
///
/// The three cases the legacy screen distinguishes are already resolved when a value of this type is made — a locked discussion arrives here as a padlock and a
/// title like any other. See `SingleDiscussionViewAppDataSource.header(of:)`, where that resolution is written down.
public struct DiscussionHeader: Equatable, Sendable {

    /// What this discussion is called: a contact's name, a group's name, or the discussion's own title once it is locked.
    ///
    /// It is also what the **back button of the next screen** is built from, which is why it is a plain string and not something already drawn. See
    /// ``SingleDiscussionView``, which hands it to `navigationTitle` as well as to the header.
    public let title: String

    /// The line under the title: a contact's position at company, or the members of a group, already sorted and formatted. Empty when there is nothing to say —
    /// a contact with no position, a group of nobody — and the header then draws one line rather than a blank second one.
    public let subtitle: String

    /// The picture, or the initials, or the padlock. Built by the app from `PersistedDiscussion.avatarViewModel`, which is the mapping the rest of the app
    /// already uses for a discussion — the padlock of a locked one included.
    public let avatar: ObvAvatarViewModel

    /// Whether this discussion is one that can still be acted on — `status == .active`. It gates the settings and the gallery, and with them the ellipsis itself:
    /// a locked discussion offers none of the three and shows **no button at all**, as the legacy screen shows none.
    public let isActive: Bool

    /// Whether a call can be placed from here. Not simply "is a group": a group whose members have all left cannot be called, which is what
    /// `PersistedDiscussion.isCallAvailable` decides.
    public let isCallAvailable: Bool

    /// Whether the reader may write here at all. When false the screen shows **no composition bar**, as the legacy screen shows none.
    ///
    /// **Not the same question as ``isActive``**, which is only the discussion's status. This also refuses a one-to-one whose contact is no longer active, a
    /// group v1 with nobody left to write to, and a group v2 whose permissions have been withdrawn — `PersistedDiscussion.ownedIdentityIsAllowedToSendMessages`,
    /// where the conditions are written down.
    ///
    /// **Here rather than in `InitialValues` precisely because it changes under the reader.** A discussion becomes locked while it is open; a contact is
    /// re-added and it becomes writable again; a group v2 grants or withdraws the permission. This type is the one thing about the discussion that is
    /// *followed* — see `SingleDiscussionView.followsTheHeader()` — and the streams behind it already watch every object the answer depends on: the discussion
    /// for its status, the contact for `isActive`, the group for its members and permissions. So the bar appears and disappears with the answer, animated,
    /// which is what legacy does over 0.3s on three separate notifications.
    public let theReaderCanWriteHere: Bool

    /// The mute this discussion is under, and nil when it is under none. See ``Mute``.
    public let mute: Mute?

    /// What it means for a discussion to be muted, as far as the bar is concerned: a moon, and a menu that says until when.
    public struct Mute: Equatable, Sendable {

        /// When the mute ends.
        ///
        /// Carried as a **date and not as a "still muted" flag**, because it is what lets the moon go away by itself. `currentMuteNotificationsEndDate` turns nil
        /// once that moment passes, but nothing in the database *changes* then — no fetched results controller has anything to report — so a screen left open
        /// across the end of a mute would go on showing the moon. The view sleeps until this date instead. See ``DiscussionUnmuteButton``.
        ///
        /// Always in the future when a value of this type is made: an expired mute arrives as nil.
        public let endDate: Date

        /// The sentence at the head of the menu, naming that date — or saying the mute is indefinite, which is what the legacy screen says of one more than ten
        /// years out.
        ///
        /// **Built by the app**, for the reason `InitialValues.sentenceSayingTheDiscussionIsEndToEndEncrypted` is: it is the app's sentence, formatted with the
        /// app's formatter, and one of its two forms is a string this module does not own.
        public let sentence: String

        public init(endDate: Date, sentence: String) {
            self.endDate = endDate
            self.sentence = sentence
        }

    }

    public init(title: String, subtitle: String, avatar: ObvAvatarViewModel, isActive: Bool, isCallAvailable: Bool, theReaderCanWriteHere: Bool, mute: Mute?) {
        self.title = title
        self.subtitle = subtitle
        self.avatar = avatar
        self.isActive = isActive
        self.isCallAvailable = isCallAvailable
        self.theReaderCanWriteHere = theReaderCanWriteHere
        self.mute = mute
    }

}
