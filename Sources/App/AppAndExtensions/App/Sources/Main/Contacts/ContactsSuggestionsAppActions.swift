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
import ObvEngine
import ObvTypes
import ObvUICoreData
import ObvContactsSuggestions
import ObvSettings
import OlvidUtils


/// What the screen of suggestions asks of the app.
///
/// It answers the cards itself: it accepts and declines the invitations through the engine. It hands to its ``delegate`` what needs the delegate
/// chain (inviting, setting a contact aside, saving the cards seen) and the navigation.
///
/// The flow that presents the screen creates it once and keeps it. It holds its delegate weakly, so the sheet, which holds its actions, does not
/// hold the flow.
@MainActor
final class ContactsSuggestionsAppActions: ContactsSuggestionsViewActions {

    weak var delegate: ContactsSuggestionsAppActionsDelegate?

    private let obvEngine: ObvEngine

    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
    }


    // MARK: - ContactsSuggestionsViewActions

    func userAccepted(_ identifier: ContactSuggestion.Identifier) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        guard identifier.ownedCryptoId == delegate.currentOwnedCryptoId else { throw ObvError.notTheCurrentProfile }
        switch identifier {
        case .contact(let contactIdentifier):
            try await delegate.userWantsToInviteContact(self, contactIdentifier: contactIdentifier)
        case .invitation(let ownedCryptoId, let invitationUUID, _):
            let dialog = try invitationDialog(ownedCryptoId: ownedCryptoId, invitationUUID: invitationUUID)
            switch dialog.category {
            case .oneToOneInvitationReceived:
                try await obvEngine.respondTo(dialog.settingResponseToOneToOneInvitationReceived(invitationAccepted: true))
            case .acceptMediatorInvite:
                try await obvEngine.respondTo(dialog.settingResponseToAcceptMediatorInvite(acceptInvite: true))
            default:
                assertionFailure()
                throw ObvError.unexpectedDialogCategory
            }
        case .invitationSent(let ownedCryptoId, let invitationUUID, _):
            // "Uninvite", on the right: the left only skips cards, and a run of skips must never cancel an invitation. Without a confirmation, as
            // on Android: the person stays in the deck of all the other known users, now as somebody to invite.
            guard let invitation = try PersistedInvitation.getPersistedInvitation(uuid: invitationUUID, ownedCryptoId: ownedCryptoId, within: ObvStack.shared.viewContext),
                  invitation is PersistedInvitationOneToOneInvitationSent,
                  let dialog = invitation.obvDialog
            else {
                throw ObvError.invitationNotFound
            }
            guard case .oneToOneInvitationSent = dialog.category else {
                assertionFailure()
                throw ObvError.unexpectedDialogCategory
            }
            try await obvEngine.respondTo(dialog.cancellingOneToOneInvitationSent())
        }
    }


    func userDeclined(_ identifier: ContactSuggestion.Identifier) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        guard identifier.ownedCryptoId == delegate.currentOwnedCryptoId else { throw ObvError.notTheCurrentProfile }
        switch identifier {
        case .contact(let contactIdentifier):
            try await delegate.userWantsToStopSuggestingContact(self, contactIdentifier: contactIdentifier)
        case .invitation(let ownedCryptoId, let invitationUUID, let personCryptoId):
            let dialog = try invitationDialog(ownedCryptoId: ownedCryptoId, invitationUUID: invitationUUID)
            let declinedDialog: ObvDialog
            switch dialog.category {
            case .oneToOneInvitationReceived:
                declinedDialog = try dialog.settingResponseToOneToOneInvitationReceived(invitationAccepted: false)
            case .acceptMediatorInvite:
                declinedDialog = try dialog.settingResponseToAcceptMediatorInvite(acceptInvite: false)
            default:
                assertionFailure()
                throw ObvError.unexpectedDialogCategory
            }
            // Somebody we know through a group, and whose invitation was declined, is not suggested again either. Saved before the answer: once the
            // invitation is gone, they would otherwise be suggestable again, and their card would come back as somebody to invite.
            let contactIdentifier = ObvContactIdentifier(contactCryptoId: personCryptoId, ownedCryptoId: ownedCryptoId)
            if try PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .nonOneToOne, within: ObvStack.shared.viewContext) != nil {
                try await delegate.userWantsToStopSuggestingContact(self, contactIdentifier: contactIdentifier)
            }
            try await obvEngine.respondTo(declinedDialog)
        case .invitationSent:
            // "OK": the invitation stays as it is, and the deck moves on.
            return
        }
    }


    /// Saved for whichever profile the cards belong to, even one the user has just left: the sheet of that profile closes after the switch.
    func cardsWereSeen(_ identifiers: [ContactSuggestion.Identifier]) {
        for (ownedCryptoId, identifiers) in Dictionary(grouping: identifiers, by: \.ownedCryptoId) {
            var contactCryptoIds = Set<ObvCryptoId>()
            var invitationUUIDs = Set<UUID>()
            for identifier in identifiers {
                switch identifier {
                case .contact(let contactIdentifier):
                    contactCryptoIds.insert(contactIdentifier.contactCryptoId)
                case .invitation(_, let invitationUUID, _), .invitationSent(_, let invitationUUID, _):
                    invitationUUIDs.insert(invitationUUID)
                }
            }
            delegate?.contactSuggestionsWereSeen(self, ownedCryptoId: ownedCryptoId, contactCryptoIds: contactCryptoIds, invitationUUIDs: invitationUUIDs)
        }
    }


    func userWantsToSeeDetails(of contactIdentifier: ObvContactIdentifier) {
        delegate?.userWantsToSeeDetails(self, of: contactIdentifier)
    }


    func userWantsToSeeOtherKnownUsers() {
        delegate?.userWantsToSeeOtherKnownUsers(self)
    }


    func userWantsToClose() {
        delegate?.userWantsToClose(self)
    }


    func onboardingWasShown() {
        ObvMessengerSettings.ContactsSuggestions.onboardingWasShown = true
    }


    // MARK: - Helpers

    /// The dialog of an invitation that still awaits an answer, and so is either a one-to-one invitation received or an introduction.
    ///
    /// The card may be older than the invitation. Between a change and the next deck, the invitation can be gone, or already answered on another
    /// device: an introduction answered elsewhere stays, as `.mediatorInviteAccepted`. Both cases throw.
    private func invitationDialog(ownedCryptoId: ObvCryptoId, invitationUUID: UUID) throws -> ObvDialog {
        guard let invitation = try PersistedInvitation.getPersistedInvitation(uuid: invitationUUID, ownedCryptoId: ownedCryptoId, within: ObvStack.shared.viewContext),
              let dialog = invitation.obvDialog
        else {
            throw ObvError.invitationNotFound
        }
        guard invitation.contactSuggestionInvitation != nil else {
            throw ObvError.invitationNoLongerAwaitsAnAnswer
        }
        return dialog
    }


    enum ObvError: Error {
        case delegateIsNil
        case invitationNotFound
        case invitationNoLongerAwaitsAnAnswer
        case unexpectedDialogCategory
        case notTheCurrentProfile
    }

}


// MARK: - ContactsSuggestionsAppActionsDelegate

/// What ``ContactsSuggestionsAppActions`` cannot do itself: the requests that go up the delegate chain, and the navigation.
@MainActor
protocol ContactsSuggestionsAppActionsDelegate: AnyObject {
    /// The profile on screen. A card of another profile is not answered.
    var currentOwnedCryptoId: ObvCryptoId { get }
    func userWantsToInviteContact(_ actions: ContactsSuggestionsAppActions, contactIdentifier: ObvContactIdentifier) async throws
    func userWantsToStopSuggestingContact(_ actions: ContactsSuggestionsAppActions, contactIdentifier: ObvContactIdentifier) async throws
    func contactSuggestionsWereSeen(_ actions: ContactsSuggestionsAppActions, ownedCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>, invitationUUIDs: Set<UUID>)
    func userWantsToSeeDetails(_ actions: ContactsSuggestionsAppActions, of contactIdentifier: ObvContactIdentifier)
    func userWantsToSeeOtherKnownUsers(_ actions: ContactsSuggestionsAppActions)
    func userWantsToClose(_ actions: ContactsSuggestionsAppActions)
}
