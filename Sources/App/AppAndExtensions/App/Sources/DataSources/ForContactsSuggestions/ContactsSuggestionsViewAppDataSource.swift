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
import CoreData
import OSLog
import ObvTypes
import OlvidUtils
import ObvUICoreData
import ObvDesignSystem
import ObvSharedDataSources
import ObvAppCoreConstants
import ObvContactsSuggestions


/// Streams the deck of the contacts suggestions, and builds the model of the few cards on screen.
///
/// The deck holds the invitations awaiting an answer (one-to-one invitations received and introductions), whether or not we share a group with their
/// sender, newest first; then the users who are not one-to-one contacts yet and share at least one group with us, whoever shares the most groups with
/// us first. A user who sent an invitation appears once, as the invitation. A user we already invited is not suggested, nor is a user certified by our
/// own Keycloak server unless they invited us.
///
/// The deck of all the other known users (``ContactSuggestion/Scope/allOtherKnownUsers``) also holds the users set aside: the ones declined, and the ones
/// removed from the one-to-one contacts. A user we invited is there as that invitation while it is pending, so that the user finds there everyone that
/// list shows.
@MainActor
final class ContactsSuggestionsViewAppDataSource: ContactsSuggestionsViewDataSource {

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ContactsSuggestionsViewAppDataSource")

    private let backgroundContext: NSManagedObjectContext

    init(backgroundContext: NSManagedObjectContext) {
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.backgroundContext = backgroundContext
    }


    /// A fresh stream per call, so that each consumer — the contacts tab and the screen of suggestions — iterates its own. A consumer stops it by
    /// cancelling the task that iterates it, which also releases the controllers watching the database: there is nothing to finish by hand.
    func deckStream(ownedCryptoId: ObvCryptoId, scope: ContactSuggestion.Scope) -> AsyncStream<ContactSuggestion.Deck> {
        let manager = DeckStreamManager(ownedCryptoId: ownedCryptoId, scope: scope, within: backgroundContext)
        return manager.makeStream()
    }


    /// Builds the model of one card. Called only for the few cards on screen.
    func model(for identifier: ContactSuggestion.Identifier) async -> ContactSuggestion.Model? {
        let context = backgroundContext
        do {
            return try await context.perform {
                try Self.makeModel(for: identifier, within: context)
            }
        } catch {
            Self.logger.error("Could not build the model of a contact suggestion: \(error, privacy: .public)")
            return nil
        }
    }


    /// Returns the `ObvAvatarViewModel` of the user: the photo URL, the initials and the colours.
    /// That is what the avatar view needs before it can ask `ObvAvatarViewDataSource` for the image.
    func ownedAvatar(ownedCryptoId: ObvCryptoId) async -> ObvAvatarViewModel? {
        let context = backgroundContext
        do {
            return try await context.perform {
                try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context).map(ObvAvatarViewModel.init(ownedIdentity:))
            }
        } catch {
            Self.logger.error("Could not build the avatar of the owned identity: \(error, privacy: .public)")
            return nil
        }
    }

}


// MARK: - Building the model of a card

extension ContactsSuggestionsViewAppDataSource {

    /// Builds the model of the card of `identifier`.
    /// Returns `nil` when the person or the invitation is gone, or when the invitation no longer awaits an answer.
    private nonisolated static func makeModel(
        for identifier: ContactSuggestion.Identifier,
        within context: NSManagedObjectContext
    ) throws -> ContactSuggestion.Model? {
        
        switch identifier {

        case .contact(let contactIdentifier):
            return try makeModel(contactIdentifier: contactIdentifier, badge: .none, within: context)

        case .invitation(let ownedCryptoId, let invitationUUID, _):
            return try makeModel(ownedCryptoId: ownedCryptoId, invitationUUID: invitationUUID, within: context)

        case .invitationSent(let ownedCryptoId, let invitationUUID, let contactCryptoId):
            // Once answered or cancelled, the invitation is gone, and so is the card.
            guard try PersistedInvitation.getPersistedInvitation(uuid: invitationUUID, ownedCryptoId: ownedCryptoId, within: context) is PersistedInvitationOneToOneInvitationSent else {
                return nil
            }
            let contactIdentifier = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            return try makeModel(contactIdentifier: contactIdentifier, badge: .invitationSent, within: context)

        }

    }
    
    
    /// Builds the model of the card of an invitation: either a one-to-one invitation we received, or an introduction. Returns `nil` when the invitation is
    /// gone or no longer awaits an answer.
    ///
    /// The card shows the person who invited us, or the person introduced to us. When they are already a ``PersistedObvContactIdentity``, one-to-one
    /// or not (for example because we share a group), they are shown as we know them, with the groups in common if there are any. Otherwise they are
    /// shown with the details of the invitation, without groups and without a link to their details.
    private nonisolated static func makeModel(
        ownedCryptoId: ObvCryptoId,
        invitationUUID: UUID,
        within context: NSManagedObjectContext
    ) throws -> ContactSuggestion.Model? {
        
        guard let invitation = try PersistedInvitation.getPersistedInvitation(uuid: invitationUUID, ownedCryptoId: ownedCryptoId, within: context),
              let suggestionInvitation = invitation.contactSuggestionInvitation
        else {
            return nil
        }

        let badge: ContactSuggestion.Model.Badge
        let personIdentity: ObvGenericIdentity
        switch suggestionInvitation.kind {
        case .oneToOneInvitationReceived(let contactIdentity):
            badge = .invitationReceived
            personIdentity = contactIdentity
        case .introduction(let contactIdentity, let mediatorIdentity):
            // The mediator is a contact. The name from the invitation is only used if they were deleted since.
            let mediatorName = try PersistedObvContactIdentity.get(contactCryptoId: mediatorIdentity.cryptoId, ownedIdentityCryptoId: ownedCryptoId, whereOneToOneStatusIs: .any, within: context)?.customOrShortDisplayName
                ?? mediatorIdentity.currentIdentityDetails.coreDetails.getFullDisplayName()
            badge = .introducedBy(mediatorName: mediatorName)
            personIdentity = contactIdentity
        }

        let contactIdentifier = ObvContactIdentifier(contactCryptoId: personIdentity.cryptoId, ownedCryptoId: ownedCryptoId)
        if let model = try makeModel(contactIdentifier: contactIdentifier, badge: badge, within: context) {
            return model
        } else {
            let coreDetails = personIdentity.currentIdentityDetails.coreDetails
            let name = coreDetails.getFullDisplayName()
            return .init(avatar: ObvAvatarViewModel(contactCryptoId: personIdentity.cryptoId, contactFullDisplayName: name),
                         name: name,
                         positionAtCompany: coreDetails.positionAtCompany().trimmingWhitespacesAndNewlinesAndMapToNilIfZeroLength(),
                         badge: badge,
                         commonGroups: nil,
                         contactForDetails: nil)
        }

    }


    /// Builds the model of the card of a contact, with `badge`, the groups in common and a link to their details. Returns `nil` when there is no
    /// such contact.
    private nonisolated static func makeModel(
        contactIdentifier: ObvContactIdentifier,
        badge: ContactSuggestion.Model.Badge,
        within context: NSManagedObjectContext
    ) throws -> ContactSuggestion.Model? {
        guard let contact = try PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: context) else { return nil }
        return .init(avatar: ObvAvatarViewModel(contact: contact),
                     name: contact.customOrFullDisplayName,
                     positionAtCompany: contact.identityCoreDetails?.positionAtCompany().trimmingWhitespacesAndNewlinesAndMapToNilIfZeroLength(),
                     badge: badge,
                     commonGroups: try makeCommonGroups(contactIdentifier: contactIdentifier, within: context),
                     contactForDetails: contactIdentifier)
    }


    /// The groups, v1 and v2, that we share with the contact, sorted by name: the pictures of the first three, the name of the first one, and how many
    /// there are. Returns `nil` when we share no group with the contact.
    ///
    /// Every card shows them under the person's name. The onboarding also uses them to choose its people: it shows only people we share a group with.
    private nonisolated static func makeCommonGroups(
        contactIdentifier: ObvContactIdentifier,
        within context: NSManagedObjectContext
    ) throws -> ContactSuggestion.Model.CommonGroups? {
        let request = DisplayedContactGroup.getFetchRequestForAllDisplayedContactGroup(ownedIdentity: contactIdentifier.ownedCryptoId, contactIdentity: contactIdentifier.contactCryptoId)
        let groups = try context.fetch(request)
        guard let firstGroup = groups.first else { return nil }
        let pictures = groups.prefix(3).compactMap { group -> ContactSuggestion.Model.CommonGroups.Picture? in
            guard let id = try? group.objectPermanentID.description, let avatar = try? ObvAvatarViewModel(displayedContactGroup: group) else { return nil }
            return .init(id: id, avatar: avatar)
        }
        return .init(pictures: pictures, nameOfFirstGroup: firstGroup.displayedTitle, numberOfGroups: groups.count)
    }

}


// MARK: - Streaming the deck

extension ContactsSuggestionsViewAppDataSource {

    private final class DeckStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ContactSuggestion.Deck, PersistedObvContactIdentity, PersistedInvitation>, @unchecked Sendable {

        private let ownedCryptoId: ObvCryptoId
        private let scope: ContactSuggestion.Scope

        /// What each invitation means to the deck, decoded once per version of its dialog: an invitation whose dialog changes is given a new date.
        /// Only touched on the queue of the context, where the deck is built.
        private var roleOfInvitation = [NSManagedObjectID: (date: Date, role: PersistedInvitation.ContactSuggestionRole?)]()
        
        /// The invitation shown for each person with several, kept for as long as it awaits an answer: a newer one must not replace the card under
        /// the reader's finger.
        /// Only touched on the queue of the context, where the deck is built.
        private var invitationShownForCryptoId = [ObvCryptoId: UUID]()

        init(ownedCryptoId: ObvCryptoId, scope: ContactSuggestion.Scope, within context: NSManagedObjectContext) {
            self.ownedCryptoId = ownedCryptoId
            self.scope = scope

            // The contacts we can suggest (`isSuggestable`), in the order of the list of contacts; for the deck of all the other known users, the
            // ones set aside too. A contact invited by an earlier version of the app was not set aside when the invitation was sent, so this
            // controller still holds them: `createModel` leaves them out while that invitation is pending. In the deck of all the other known
            // users, a contact we invited shows as that invitation instead.
            let frc1: NSFetchedResultsController<PersistedObvContactIdentity>
            switch scope {
            case .suggestions:
                frc1 = PersistedObvContactIdentity.getFetchedResultsControllerForSuggestions(ownedCryptoId: ownedCryptoId, within: context)
            case .allOtherKnownUsers:
                frc1 = PersistedObvContactIdentity.getFetchedResultsControllerForAllWhoCouldBeInvited(ownedCryptoId: ownedCryptoId, within: context)
            }

            // All the invitations of the owned identity, of every kind, newest first, including the one-to-one invitations we sent, which are a
            // subentity of `PersistedInvitation`. `createModel` keeps those that matter to the deck.
            let frc2 = PersistedInvitation.getFetchedResultsControllerForOwnedIdentity(with: ownedCryptoId, within: context)

            // Whether a card is new is read on the contacts of `frc1` and on the invitations of `frc2`: marking them as seen builds the deck again.
            super.init(frc1: frc1, frc2: frc2)
        }

        /// Builds the deck from the suggestions and the invitations.
        override func createModel(
            fetchedObjects1: [PersistedObvContactIdentity],
            fetchedObjects2: [PersistedInvitation]
        ) throws -> ContactSuggestion.Deck {
            
            let context = frc1.managedObjectContext
            
            // The role of each invitation: `.awaitingAnAnswer`, `.introductionAccepted` or `nil`.
            let roles = roles(of: fetchedObjects2)
            
            // The invitations awaiting an answer, one per person. Each one becomes a card.
            let invitations = oneInvitationPerPerson(roles.compactMap({
                if case .awaitingAnAnswer(let invitation) = $0 { return invitation } else { return nil }
            }))
            let cryptoIdsWithAnInvitation = Set(invitations.map(\.contactCryptoId))
            
            // The one-to-one invitations we sent and that are still pending, one per person.
            var invitationSentForCryptoId = [ObvCryptoId: PersistedInvitationOneToOneInvitationSent]()
            for invitationSent in fetchedObjects2.compactMap({ $0 as? PersistedInvitationOneToOneInvitationSent }) {
                guard let contactCryptoId = invitationSent.contactIdentity, invitationSentForCryptoId[contactCryptoId] == nil else { continue }
                invitationSentForCryptoId[contactCryptoId] = invitationSent
            }

            // While it is under way, we do not suggest a person we invited, or a person whose introduction we accepted. A person we invite is
            // also set aside when the invitation is sent: for the suggestions, the first part only matters for an invitation sent by an earlier
            // version of the app. The deck of all the other known users shows a person we invited as that invitation.
            let cryptoIdsWithAnIntroductionAccepted = Set(roles.compactMap({
                if case .introductionAccepted(let contactCryptoId) = $0 { return contactCryptoId } else { return nil }
            }))
            
            var entries = [Entry]()
            // Whether a card was not in the deck the last time the user opened it. An invitation card has its own flag, even when it is from
            // somebody already shown as a suggestion: their invitation is a new card.
            var hasANewCard = false
            let uuidsOfTheInvitationsSeen = Set(fetchedObjects2.filter(\.suggestionSeen).map(\.uuid))

            // The person of an invitation may already be a contact, for example because we share a group. Their card then shows what we know of
            // them. These contacts are fetched in one request. They are few, and the request returns the same objects as the first controller.
            let contactsWithAnInvitation = try PersistedObvContactIdentity.getContacts(
                ownedCryptoId: ownedCryptoId,
                contactCryptoIds: cryptoIdsWithAnInvitation,
                within: context
            )
            let contactForCryptoId: [ObvCryptoId : PersistedObvContactIdentity] = Dictionary(
                contactsWithAnInvitation.compactMap({ contact in (try? contact.cryptoId).map({ ($0, contact) }) }),
                uniquingKeysWith: { first, _ in first }
            )
            for invitation in invitations {
                let contact = contactForCryptoId[invitation.contactCryptoId]
                entries.append(.init(
                    identifier: .invitation(ownedCryptoId: ownedCryptoId, invitationUUID: invitation.invitationUUID, contactCryptoId: invitation.contactCryptoId),
                    contact: contact,
                    invitationDate: invitation.date)
                )
                if !uuidsOfTheInvitationsSeen.contains(invitation.invitationUUID) {
                    hasANewCard = true
                }
            }
            
            // Add the remaining suggestions from frc1:
            // - skip a contact whose cryptoId can't be read
            // - skip people under way, except a person we invited in the deck of all the other known users: their card is that invitation
            // - skip people who already have an invitation card
            for contact in fetchedObjects1 {
                guard let contactCryptoId = try? contact.cryptoId else { continue }
                guard !cryptoIdsWithAnIntroductionAccepted.contains(contactCryptoId), !cryptoIdsWithAnInvitation.contains(contactCryptoId) else { continue }
                if let invitationSent = invitationSentForCryptoId[contactCryptoId] {
                    switch scope {
                    case .suggestions:
                        continue
                    case .allOtherKnownUsers:
                        // Among the suggestions rather than with the invitations to answer: there is nothing to answer. No badge shows this deck.
                        entries.append(.init(identifier: .invitationSent(ownedCryptoId: ownedCryptoId, invitationUUID: invitationSent.uuid, contactCryptoId: contactCryptoId),
                                             contact: contact,
                                             invitationDate: nil))
                        continue
                    }
                }
                entries.append(.init(identifier: .contact(ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)),
                                     contact: contact,
                                     invitationDate: nil))
                if !contact.suggestionSeen {
                    hasANewCard = true
                }
            }

            let identifiers = Self.sorted(entries).map(\.identifier)

            return .init(identifiers: identifiers, hasANewCard: hasANewCard)
            
        }
        
        
        /// The role of each invitation. An invitation means one of three things to the deck:
        /// - it awaits an answer, and becomes a card;
        /// - it's an introduction we accepted that isn't finished yet;
        /// - nothing.
        /// Read from the cache when its dialog has not changed since it was decoded.
        private func roles(of invitations: [PersistedInvitation]) -> [PersistedInvitation.ContactSuggestionRole?] {
            var roleOfInvitation = [NSManagedObjectID: (date: Date, role: PersistedInvitation.ContactSuggestionRole?)]()
            let roles = invitations.map { invitation in
                let role: PersistedInvitation.ContactSuggestionRole?
                if let cached = self.roleOfInvitation[invitation.objectID], cached.date == invitation.date {
                    role = cached.role
                } else {
                    role = invitation.contactSuggestionRole
                }
                roleOfInvitation[invitation.objectID] = (invitation.date, role)
                return role
            }
            // Only the invitations still there are kept.
            self.roleOfInvitation = roleOfInvitation
            return roles
        }
        
        
        /// Somebody may have invited us and been introduced to us, or been introduced by several contacts: they get one card, which answers one
        /// invitation at a time. The invitation already shown stays; otherwise their own invitation comes before an introduction, then the newest.
        /// The others wait until it is answered.
        private func oneInvitationPerPerson(_ invitations: [PersistedInvitation.ContactSuggestionInvitation]) -> [PersistedInvitation.ContactSuggestionInvitation] {
            func comesFirst(_ lhs: PersistedInvitation.ContactSuggestionInvitation, _ rhs: PersistedInvitation.ContactSuggestionInvitation) -> Bool {
                switch (lhs.kind, rhs.kind) {
                case (.oneToOneInvitationReceived, .introduction): return true
                case (.introduction, .oneToOneInvitationReceived): return false
                default: return lhs.date > rhs.date
                }
            }
            var invitationForCryptoId = [ObvCryptoId: PersistedInvitation.ContactSuggestionInvitation]()
            for invitation in invitations {
                let cryptoId = invitation.contactCryptoId
                if let kept = invitationForCryptoId[cryptoId] {
                    if kept.invitationUUID == invitationShownForCryptoId[cryptoId] { continue }
                    if invitation.invitationUUID != invitationShownForCryptoId[cryptoId] && comesFirst(kept, invitation) { continue }
                }
                invitationForCryptoId[cryptoId] = invitation
            }
            invitationShownForCryptoId = invitationForCryptoId.mapValues(\.invitationUUID)
            // In the order they came, for the sort of the deck to stay stable.
            let kept = Set(invitationShownForCryptoId.values)
            return invitations.filter { kept.contains($0.invitationUUID) }
        }
        
        
        private struct Entry {
            let identifier: ContactSuggestion.Identifier
            /// `nil` for somebody we do not know yet, who shares no group with us.
            let contact: PersistedObvContactIdentity?
            let invitationDate: Date?
        }
        
        
        /// The invitations awaiting an answer first, the newest first, since somebody is waiting for the answer; then whoever shares the most groups
        /// with us; and otherwise the order of the list of contacts, the sort being stable.
        private static func sorted(_ entries: [Entry]) -> [Entry] {
            let keyed = entries.enumerated().map { index, entry in
                (entry: entry, index: index, numberOfGroupsInCommon: entry.contact?.numberOfGroupsInCommon ?? 0)
            }
            return keyed.sorted { lhs, rhs in
                switch (lhs.entry.invitationDate, rhs.entry.invitationDate) {
                case let (l?, r?) where l != r: return l > r
                case (.some, .none): return true
                case (.none, .some): return false
                default: break
                }
                if lhs.numberOfGroupsInCommon != rhs.numberOfGroupsInCommon {
                    return lhs.numberOfGroupsInCommon > rhs.numberOfGroupsInCommon
                }
                return lhs.index < rhs.index
            }.map(\.entry)
        }

    }

}
