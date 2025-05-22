/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvUIGroupV2
import ObvTypes
import ObvAppTypes
import ObvUICoreData
import ObvDesignSystem


protocol AppListOfGroupMembersViewDataSourceDelegate: AnyObject {
    func fetchAvatarImage(_ dataSource: AppDataSourceForObvUIGroupV2Router, localPhotoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?
}


/// This class acts as a data source for all the views implemented by `ObvUIGroupV2`.
/// It is used both when creating a new group, and when editing an existing group.
/// This class acts as a "bridge" between the persisted groups, members, contacts,... stored in the Core Data database,
/// and the `ObvUIGroupV2` views' models.
@MainActor
final class AppDataSourceForObvUIGroupV2Router {
    
    private var singleGroupV2MainViewModelStreamManagerForStreamUUID = [UUID: SingleGroupV2MainViewModelStreamManager]()
    private var groupLightweightModelStreamManagerForStreamUUID = [UUID: GroupLightweightModelStreamManager]()
    private var listOfSingleGroupMemberViewModelStreamManagerForStreamUUID = [UUID: ListOfSingleGroupMemberViewModelStreamManager]()
    private var singleGroupMemberViewModelStreamManagerForStreamUUID = [UUID: SingleGroupMemberViewModelStreamManager]()
    private var selectUsersToAddViewModelStreamManagerForStreamUUID = [UUID: SelectUsersToAddViewModelStreamManager]()
    private var selectUsersToAddViewModelUserStreamManagerForStreamUUID = [UUID: SelectUsersToAddViewModelUserStreamManager]()
    private var oneToOneInvitableViewModelStreamManagerForStreamUUID = [UUID: OneToOneInvitableViewModelStreamManager]()
    private var onetoOneInvitableGroupMembersViewModelStreamManagerForStreamUUID = [UUID: OnetoOneInvitableGroupMembersViewModelStreamManager]()
    private var onetoOneInvitableGroupMembersViewCellModelStreamManagerForStreamUUID = [UUID: OnetoOneInvitableGroupMembersViewCellModelStreamManager]()
    private var ownedIdentityAsGroupMemberViewModelStreamManagerForStreamUUID = [UUID: OwnedIdentityAsGroupMemberViewModelStreamManager]()

    private weak var delegate: AppListOfGroupMembersViewDataSourceDelegate?
    
    func setDelegate(to delegate: AppListOfGroupMembersViewDataSourceDelegate) {
        assert(self.delegate == nil)
        self.delegate = delegate
    }
    
}


// MARK: - Stream Manager for OwnedIdentityAsGroupMemberViewModel

extension AppDataSourceForObvUIGroupV2Router {
    
    private final class OwnedIdentityAsGroupMemberViewModelStreamManager: NSObject, NSFetchedResultsControllerDelegate {
        
        let streamUUID = UUID()
        let frcForPersistedObvOwnedIdentity: NSFetchedResultsController<PersistedObvOwnedIdentity>
        let frcForPersistedGroupV2: NSFetchedResultsController<PersistedGroupV2>
        private var stream: AsyncStream<ObvUIGroupV2.OwnedIdentityAsGroupMemberViewModel>?
        private var continuation: AsyncStream<ObvUIGroupV2.OwnedIdentityAsGroupMemberViewModel>.Continuation?

        init(groupIdentifier: ObvGroupV2Identifier) {
            self.frcForPersistedObvOwnedIdentity = PersistedObvOwnedIdentity.getFetchedResultsController(ownedCryptoId: groupIdentifier.ownedCryptoId, within: ObvStack.shared.viewContext)
            self.frcForPersistedGroupV2 = PersistedGroupV2.getFetchedResultsController(groupV2Identifier: groupIdentifier, within: ObvStack.shared.viewContext)
            super.init()
        }
        
        private func createModel() throws -> ObvUIGroupV2.OwnedIdentityAsGroupMemberViewModel {
            guard let fetchedObjects = frcForPersistedGroupV2.fetchedObjects else {
                assertionFailure()
                throw ObvError.couldNotFetchGroup
            }
            guard let persistedGroup = fetchedObjects.first else {
                // This happens when leaving a group
                throw ObvError.groupCannotBeFound
            }
            let model = try ObvUIGroupV2.OwnedIdentityAsGroupMemberViewModel(persistedGroup: persistedGroup)
            return model
        }
        
        @MainActor
        func startStream() throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.OwnedIdentityAsGroupMemberViewModel>) {
            if let stream {
                return (streamUUID, stream)
            }
            frcForPersistedObvOwnedIdentity.delegate = self
            frcForPersistedGroupV2.delegate = self
            try frcForPersistedObvOwnedIdentity.performFetch()
            try frcForPersistedGroupV2.performFetch()
            let stream = AsyncStream(ObvUIGroupV2.OwnedIdentityAsGroupMemberViewModel.self) { [weak self] (continuation: AsyncStream<ObvUIGroupV2.OwnedIdentityAsGroupMemberViewModel>.Continuation) in
                guard let self else { return }
                self.continuation = continuation
                do {
                    let model = try createModel()
                    continuation.yield(model)
                } catch {
                    if let error = error as? ObvUIGroupV2.OwnedIdentityAsGroupMemberViewModel.ObvErrorForInitBasedOnPersistedGroupV2 {
                        switch error {
                        case .persistedOwnedIdentityMissing:
                            // This happens when leaving a group, we don't yield a new model value in this case
                            return
                        }
                    } else if let error = error as? AppDataSourceForObvUIGroupV2Router.ObvError {
                        switch error {
                        case .groupCannotBeFound:
                            // This happens when leaving a group, we don't yield a new model value in this case
                            return
                        default:
                            assertionFailure()
                        }
                    } else {
                        assertionFailure()
                    }
                }
            }
            self.stream = stream
            return (streamUUID, stream)
        }

        func finishStream() {
            continuation?.finish()
        }

        func controller(_ controller: NSFetchedResultsController<any NSFetchRequestResult>, didChangeContentWith diff: CollectionDifference<NSManagedObjectID>) {
            guard let continuation else { assertionFailure(); return }
            do {
                let model = try createModel()
                continuation.yield(model)
            } catch {
                if let error = error as? ObvUIGroupV2.OwnedIdentityAsGroupMemberViewModel.ObvErrorForInitBasedOnPersistedGroupV2 {
                    switch error {
                    case .persistedOwnedIdentityMissing:
                        // This happens when leaving a group, we don't yield a new model value in this case
                        return
                    }
                } else if let error = error as? AppDataSourceForObvUIGroupV2Router.ObvError {
                    switch error {
                    case .groupCannotBeFound:
                        // This happens when leaving a group, we don't yield a new model value in this case
                        return
                    default:
                        assertionFailure()
                    }
                } else {
                    assertionFailure()
                }
            }
        }

    }
    
}

// MARK: - Stream Manager for OnetoOneInvitableGroupMembersViewCellModel

extension AppDataSourceForObvUIGroupV2Router {
    
    /// Stream manager used to feed a cell displaying a group member in the view showing all the group members that can be invited to a one2one discussion.
    /// A group member can be identified by one of two possible identifiers: an ObjectID to a persisted contact, or an ObjectID to a group member.
    /// We also need to observe persisted one to one invitation sent, as we need to know whether a non-one2one contact can be invited or not (we disallow a second
    /// invitation to be sent).
    private final class OnetoOneInvitableGroupMembersViewCellModelStreamManager: NSObject, NSFetchedResultsControllerDelegate {
        
        let streamUUID = UUID()
        let frcKind: FetchedResultsControllerKind
        let frcPersistedInvitationOneToOneInvitationSent: NSFetchedResultsController<PersistedInvitationOneToOneInvitationSent>?
        private var stream: AsyncStream<ObvUIGroupV2.OnetoOneInvitableGroupMembersViewCellModel>?
        private var continuation: AsyncStream<ObvUIGroupV2.OnetoOneInvitableGroupMembersViewCellModel>.Continuation?

        enum FetchedResultsControllerKind {
            case persistedGroupV2Member(frc: NSFetchedResultsController<PersistedGroupV2Member>)
            case persistedObvContactIdentity(frc: NSFetchedResultsController<PersistedObvContactIdentity>)
        }

        init(memberIdentifier: ObvUIGroupV2.OnetoOneInvitableGroupMembersViewModel.Identifier) throws {
            
            switch memberIdentifier {
            case .contactIdentifier:
                assertionFailure()
                throw ObvError.unexpectedIdentifierType
            case .objectIDOfPersistedGroupV2Member(let objectID):
                let frc = PersistedGroupV2Member.getFetchedResultsController(objectID: .init(objectID: objectID), within: ObvStack.shared.viewContext)
                self.frcKind = .persistedGroupV2Member(frc: frc)
            case .objectIDOfPersistedObvContactIdentity(let objectID):
                let frc = PersistedObvContactIdentity.getFetchedResultsController(objectID: .init(objectID: objectID), within: ObvStack.shared.viewContext)
                self.frcKind = .persistedObvContactIdentity(frc: frc)
            }
            
            let contactIdentifier: ObvContactIdentifier?
            switch memberIdentifier {
            case .contactIdentifier:
                assertionFailure()
                throw ObvError.unexpectedIdentifierType
            case .objectIDOfPersistedGroupV2Member(let objectID):
                if let groupMember = try PersistedGroupV2Member.get(objectID: objectID, within: ObvStack.shared.viewContext) {
                    contactIdentifier = try groupMember.userIdentifier
                } else {
                    assertionFailure()
                    contactIdentifier = nil
                }
            case .objectIDOfPersistedObvContactIdentity(let objectID):
                if let contact = try PersistedObvContactIdentity.get(objectID: objectID, within: ObvStack.shared.viewContext) {
                    contactIdentifier = try contact.contactIdentifier
                } else {
                    assertionFailure()
                    contactIdentifier = nil
                }
            }

            if let contactIdentifier {
                frcPersistedInvitationOneToOneInvitationSent = PersistedInvitationOneToOneInvitationSent.getFetchedResultsController(ownedCryptoId: contactIdentifier.ownedCryptoId,
                                                                                                                                     remoteCryptoId: contactIdentifier.contactCryptoId,
                                                                                                                                     within: ObvStack.shared.viewContext)
            } else {
                frcPersistedInvitationOneToOneInvitationSent = nil
            }
            super.init()
        }
    
        private func createModel() throws -> ObvUIGroupV2.OnetoOneInvitableGroupMembersViewCellModel {
                        
            switch frcKind {

            case .persistedGroupV2Member(frc: let frc):
                
                guard let fetchedObjects = frc.fetchedObjects else { assertionFailure(); throw ObvError.fetchedObjectsIsNil }
                assert(fetchedObjects.count == 1 || fetchedObjects.count == 0)
                guard let persistedMember = fetchedObjects.first else { throw ObvError.groupMemberIsNil }
                
                let contactIdentifier = ObvContactIdentifier(contactCryptoId: persistedMember.cryptoId, ownedCryptoId: try persistedMember.persistedGroup.ownCryptoId)
                
                let kind: OnetoOneInvitableGroupMembersViewCellModel.Kind
                if let persistedContact = persistedMember.contact {
                    if persistedContact.isOneToOne {
                        
                        kind = .oneToOneContactsAmongMembers
                        
                    } else {
                        
                        let sentInvitation = frcPersistedInvitationOneToOneInvitationSent?.fetchedObjects?.first
                        let invitationSentAlready = sentInvitation != nil

                        kind = .invitableGroupMembers(invitationSentAlready: invitationSentAlready)
                        
                    }
                } else {
                    kind = .notInvitableGroupMembers
                }

                let detailedProfileCanBeShown: Bool = (persistedMember.contact != nil)
                
                let model = ObvUIGroupV2.OnetoOneInvitableGroupMembersViewCellModel(
                    contactIdentifier: contactIdentifier,
                    isKeycloakManaged: persistedMember.isKeycloakManaged,
                    profilePictureInitial: persistedMember.circledInitialsConfiguration.initials?.text,
                    circleColors: .init(background: persistedMember.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                        foreground: persistedMember.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                    identityDetails: try persistedMember.identityDetails,
                    kind: kind,
                    isRevokedAsCompromised: false,
                    detailedProfileCanBeShown: detailedProfileCanBeShown,
                    customDisplayName: persistedMember.contact?.customDisplayNameSanitized,
                    customPhotoURL: persistedMember.contact?.customPhotoURL)
                
                return model

            case .persistedObvContactIdentity(frc: let frc):

                guard let fetchedObjects = frc.fetchedObjects else { assertionFailure(); throw ObvError.fetchedObjectsIsNil }
                assert(fetchedObjects.count == 1)
                guard let persistedContact = fetchedObjects.first else { assertionFailure(); throw ObvError.groupMemberIsNil }

                let kind: OnetoOneInvitableGroupMembersViewCellModel.Kind
                if persistedContact.isOneToOne {
                    kind = .oneToOneContactsAmongMembers
                } else {
                    let contactIdentifier = try persistedContact.contactIdentifier
                    let sentInvitation = try PersistedInvitationOneToOneInvitationSent.get(fromOwnedIdentity: contactIdentifier.ownedCryptoId,
                                                                                       toContact: contactIdentifier.contactCryptoId,
                                                                                       within: ObvStack.shared.viewContext)
                    let invitationSentAlready = sentInvitation != nil
                    kind = .invitableGroupMembers(invitationSentAlready: invitationSentAlready)
                }
                
                let model = ObvUIGroupV2.OnetoOneInvitableGroupMembersViewCellModel(
                    contactIdentifier: try persistedContact.contactIdentifier,
                    isKeycloakManaged: persistedContact.isCertifiedByOwnKeycloak,
                    profilePictureInitial: persistedContact.circledInitialsConfiguration.initials?.text,
                    circleColors: .init(background: persistedContact.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                        foreground: persistedContact.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                    identityDetails: try persistedContact.identityDetails,
                    kind: kind,
                    isRevokedAsCompromised: false,
                    detailedProfileCanBeShown: true,
                    customDisplayName: persistedContact.customDisplayNameSanitized,
                    customPhotoURL: persistedContact.customPhotoURL)

                return model
                
            }
                        
        }

        @MainActor
        func startStream() throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.OnetoOneInvitableGroupMembersViewCellModel>) {
            if let stream {
                return (streamUUID, stream)
            }
            
            switch frcKind {
            case .persistedGroupV2Member(frc: let frc):
                frc.delegate = self
                try frc.performFetch()
            case .persistedObvContactIdentity(let frc):
                frc.delegate = self
                try frc.performFetch()
            }
            frcPersistedInvitationOneToOneInvitationSent?.delegate = self
            try frcPersistedInvitationOneToOneInvitationSent?.performFetch()
            
            let stream = AsyncStream(ObvUIGroupV2.OnetoOneInvitableGroupMembersViewCellModel.self) { [weak self] (continuation: AsyncStream<ObvUIGroupV2.OnetoOneInvitableGroupMembersViewCellModel>.Continuation) in
                guard let self else { return }
                self.continuation = continuation
                do {
                    let model = try createModel()
                    continuation.yield(model)
                } catch {
                    assertionFailure()
                }
            }
            self.stream = stream
            return (streamUUID, stream)

        }

        func finishStream() {
            continuation?.finish()
        }

        func controller(_ controller: NSFetchedResultsController<any NSFetchRequestResult>, didChangeContentWith diff: CollectionDifference<NSManagedObjectID>) {
            guard let continuation else { assertionFailure(); return }
            do {
                let model = try createModel()
                continuation.yield(model)
            } catch {
                if let error = error as? ObvError {
                    switch error {
                    case .unexpectedIdentifierType:
                        assertionFailure()
                    case .fetchedObjectsIsNil:
                        assertionFailure()
                    case .groupMemberIsNil:
                        // This happens when the user is removed from the group.
                        // This user will also be removed from the list of identifiers to display,
                        // so there is nothing to do.
                        return
                    }
                } else {
                    assertionFailure()
                }
            }
        }

        enum ObvError: Error {
            case unexpectedIdentifierType
            case fetchedObjectsIsNil
            case groupMemberIsNil
        }

    }
    
}

// MARK: - Stream Manager for OnetoOneInvitableGroupMembersViewModel

extension AppDataSourceForObvUIGroupV2Router {
    
    private final class OnetoOneInvitableGroupMembersViewModelStreamManager: NSObject, NSFetchedResultsControllerDelegate {
        
        let streamUUID = UUID()
        let frcForInvitableMembers: NSFetchedResultsController<PersistedObvContactIdentity>
        let frcForPersistedGroupV2MemberWithNoAssociatedContact: NSFetchedResultsController<PersistedGroupV2Member>
        let frcForMembersThatAreOne2OneAlready: NSFetchedResultsController<PersistedObvContactIdentity>
        private var stream: AsyncStream<ObvUIGroupV2.OnetoOneInvitableGroupMembersViewModel>?
        private var continuation: AsyncStream<ObvUIGroupV2.OnetoOneInvitableGroupMembersViewModel>.Continuation?

        init(groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
            self.frcForInvitableMembers = PersistedObvContactIdentity.getFetchedResultsControllerForGroupV2(groupIdentifier: groupIdentifier, whereOneToOneStatusIs: .nonOneToOne, within: ObvStack.shared.viewContext)
            self.frcForPersistedGroupV2MemberWithNoAssociatedContact = PersistedGroupV2Member.getFetchedResultsControllerForMembersWithNoAssociatedContact(groupV2Identifier: groupIdentifier, within: ObvStack.shared.viewContext)
            self.frcForMembersThatAreOne2OneAlready = PersistedObvContactIdentity.getFetchedResultsControllerForGroupV2(groupIdentifier: groupIdentifier, whereOneToOneStatusIs: .oneToOne, within: ObvStack.shared.viewContext)
            super.init()
        }
     
        private func createModel() throws -> ObvUIGroupV2.OnetoOneInvitableGroupMembersViewModel {
            
            guard let invitableMembers = frcForInvitableMembers.fetchedObjects else { assertionFailure(); throw ObvError.fetchedObjectsIsNil }
            guard let memberWithNoAssociatedContact = frcForPersistedGroupV2MemberWithNoAssociatedContact.fetchedObjects else { assertionFailure(); throw ObvError.fetchedObjectsIsNil }
            guard let membersThatAreOne2OneAlready = frcForMembersThatAreOne2OneAlready.fetchedObjects else { assertionFailure(); throw ObvError.fetchedObjectsIsNil }
            
            let model = ObvUIGroupV2.OnetoOneInvitableGroupMembersViewModel(
                invitableGroupMembers: invitableMembers.map({ .objectIDOfPersistedObvContactIdentity(objectID: $0.objectID) }),
                notInvitableGroupMembers: memberWithNoAssociatedContact.map({ .objectIDOfPersistedGroupV2Member(objectID: $0.objectID) }),
                oneToOneContactsAmongMembers: membersThatAreOne2OneAlready.map({ .objectIDOfPersistedObvContactIdentity(objectID: $0.objectID) }))

            return model
            
        }

        @MainActor
        func startStream() throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.OnetoOneInvitableGroupMembersViewModel>) {
            if let stream {
                return (streamUUID, stream)
            }
            frcForInvitableMembers.delegate = self
            frcForPersistedGroupV2MemberWithNoAssociatedContact.delegate = self
            frcForMembersThatAreOne2OneAlready.delegate = self
            try frcForInvitableMembers.performFetch()
            try frcForPersistedGroupV2MemberWithNoAssociatedContact.performFetch()
            try frcForMembersThatAreOne2OneAlready.performFetch()
            let stream = AsyncStream(ObvUIGroupV2.OnetoOneInvitableGroupMembersViewModel.self) { [weak self] (continuation: AsyncStream<ObvUIGroupV2.OnetoOneInvitableGroupMembersViewModel>.Continuation) in
                guard let self else { return }
                self.continuation = continuation
                do {
                    let model = try createModel()
                    continuation.yield(model)
                } catch {
                    assertionFailure()
                }
            }
            self.stream = stream
            return (streamUUID, stream)
        }

        func finishStream() {
            continuation?.finish()
        }

        func controller(_ controller: NSFetchedResultsController<any NSFetchRequestResult>, didChangeContentWith diff: CollectionDifference<NSManagedObjectID>) {
            guard let continuation else { assertionFailure(); return }
            do {
                let model = try createModel()
                continuation.yield(model)
            } catch {
                assertionFailure()
            }
        }

        enum ObvError: Error {
            case fetchedObjectsIsNil
        }

    }
    
}


// MARK: - Stream Manager for OneToOneInvitableViewModel

extension AppDataSourceForObvUIGroupV2Router {
    
    /// This manager produces a stream feeding the view indicating how many group members are not yet one2one contacts.
    /// To determine this number, we need to consider all group members that have an associated PersistedObvContactIdentity that is not one2one.
    /// Since we also need the number of invitations sent, we also need to fetch `PersistedInvitationOneToOneInvitationSent` and count how many correspond to
    /// the "invitable" members.
    private final class OneToOneInvitableViewModelStreamManager: NSObject, NSFetchedResultsControllerDelegate {
        let streamUUID = UUID()
        let frcForInvitableMembers: NSFetchedResultsController<PersistedObvContactIdentity>
        let frcForAllGroupMembers: NSFetchedResultsController<PersistedGroupV2Member>
        let frcForPersistedGroupV2MemberWithNoAssociatedContact: NSFetchedResultsController<PersistedGroupV2Member>
        let frcForOneToOneInvitation: NSFetchedResultsController<PersistedInvitationOneToOneInvitationSent>
        private var stream: AsyncStream<ObvUIGroupV2.OneToOneInvitableViewModel>?
        private var continuation: AsyncStream<ObvUIGroupV2.OneToOneInvitableViewModel>.Continuation?

        init(groupIdentifier: ObvTypes.ObvGroupV2Identifier) {
            self.frcForInvitableMembers = PersistedObvContactIdentity.getFetchedResultsControllerForGroupV2(groupIdentifier: groupIdentifier, whereOneToOneStatusIs: .nonOneToOne, within: ObvStack.shared.viewContext)
            self.frcForOneToOneInvitation = PersistedInvitationOneToOneInvitationSent.getFetchedResultsControllerForAll(ownedCryptoId: groupIdentifier.ownedCryptoId, within: ObvStack.shared.viewContext)
            self.frcForPersistedGroupV2MemberWithNoAssociatedContact = PersistedGroupV2Member.getFetchedResultsControllerForMembersWithNoAssociatedContact(groupV2Identifier: groupIdentifier, within: ObvStack.shared.viewContext)
            self.frcForAllGroupMembers = PersistedGroupV2Member.getFetchedResultsController(groupV2Identifier: groupIdentifier, within: ObvStack.shared.viewContext)
            super.init()
        }
        
        private func createModel() throws -> ObvUIGroupV2.OneToOneInvitableViewModel {
            guard let invitableMembers = frcForInvitableMembers.fetchedObjects else { assertionFailure(); throw ObvError.fetchedObjectsIsNil }
            guard let oneToOneInvitation = frcForOneToOneInvitation.fetchedObjects else { assertionFailure(); throw ObvError.fetchedObjectsIsNil }
            guard let allMembers = frcForAllGroupMembers.fetchedObjects else { assertionFailure(); throw ObvError.fetchedObjectsIsNil }
            
            let identitiesOfInvitableGroupMembers: Set<ObvCryptoId> = Set(invitableMembers.map(\.cryptoId))
            let invitedIdentities: Set<ObvCryptoId> = Set(oneToOneInvitation.compactMap(\.contactIdentity))
            
            let numberOfGroupMembersThatAreContactsButNotOneToOne = identitiesOfInvitableGroupMembers.count
            let numberOfOneToOneInvitationsSent = invitedIdentities.intersection(identitiesOfInvitableGroupMembers).count
            let numberOfPendingMembersWithNoAssociatedContact = frcForPersistedGroupV2MemberWithNoAssociatedContact.fetchedObjects?.count ?? 0
            
            let groupHasNoOtherMember = allMembers.isEmpty
            
            return ObvUIGroupV2.OneToOneInvitableViewModel(numberOfGroupMembersThatAreContactsButNotOneToOne: numberOfGroupMembersThatAreContactsButNotOneToOne,
                                                           numberOfOneToOneInvitationsSent: numberOfOneToOneInvitationsSent,
                                                           numberOfPendingMembersWithNoAssociatedContact: numberOfPendingMembersWithNoAssociatedContact,
                                                           groupHasNoOtherMember: groupHasNoOtherMember)
        }

        @MainActor
        func startStream() throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.OneToOneInvitableViewModel>) {
            if let stream {
                return (streamUUID, stream)
            }
            frcForInvitableMembers.delegate = self
            frcForOneToOneInvitation.delegate = self
            frcForPersistedGroupV2MemberWithNoAssociatedContact.delegate = self
            frcForAllGroupMembers.delegate = self
            try frcForInvitableMembers.performFetch()
            try frcForOneToOneInvitation.performFetch()
            try frcForPersistedGroupV2MemberWithNoAssociatedContact.performFetch()
            try frcForAllGroupMembers.performFetch()
            let stream = AsyncStream(ObvUIGroupV2.OneToOneInvitableViewModel.self) { [weak self] (continuation: AsyncStream<ObvUIGroupV2.OneToOneInvitableViewModel>.Continuation) in
                guard let self else { return }
                self.continuation = continuation
                do {
                    let model = try createModel()
                    continuation.yield(model)
                } catch {
                    assertionFailure()
                }
            }
            self.stream = stream
            return (streamUUID, stream)
        }

        func finishStream() {
            continuation?.finish()
        }

        func controller(_ controller: NSFetchedResultsController<any NSFetchRequestResult>, didChangeContentWith diff: CollectionDifference<NSManagedObjectID>) {
            guard let continuation else { assertionFailure(); return }
            do {
                let model = try createModel()
                continuation.yield(model)
            } catch {
                assertionFailure()
            }
        }

        enum ObvError: Error {
            case fetchedObjectsIsNil
        }

    }
    
}

// MARK: - Stream Manager for SelectUsersToAddViewModel

extension AppDataSourceForObvUIGroupV2Router {
    
    private final class SelectUsersToAddViewModelStreamManager: NSObject, NSFetchedResultsControllerDelegate {
        
        let mode: ObvUIGroupV2.ObvUIGroupV2RouterDataSourceMode
        let streamUUID = UUID()
        let frc: NSFetchedResultsController<PersistedObvContactIdentity> // IDs of PersistedObvContactIdentity entities
        private var stream: AsyncStream<ObvUIGroupV2.SelectUsersToAddViewModel>?
        private var continuation: AsyncStream<ObvUIGroupV2.SelectUsersToAddViewModel>.Continuation?
        private let textOnEmptySetOfUsers = String(localized: "CHOOSE_THE_USERS_YOU_WANT_TO_ADD_TO_THE_GROUP")

        init(mode: ObvUIGroupV2.ObvUIGroupV2RouterDataSourceMode) {
            self.mode = mode
            switch mode {
            case .creation(let ownedCryptoId):
                self.frc = PersistedObvContactIdentity.getFetchedResultsControllerForAllReachableContactsOfOwnedIdentity(ownedCryptoId: ownedCryptoId, within: ObvStack.shared.viewContext)
            case .edition(let groupIdentifier):
                self.frc = PersistedObvContactIdentity.getFetchedResultsControllerForAllReachableContactsOfOwnedIdentityButExcludingGroupMembers(groupIdentifier: groupIdentifier, within: ObvStack.shared.viewContext)
            }
            super.init()
        }
        
        @MainActor
        func startStream() throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.SelectUsersToAddViewModel>) {
            if let stream {
                return (streamUUID, stream)
            }
            frc.delegate = self
            try frc.performFetch()
            let stream = AsyncStream(ObvUIGroupV2.SelectUsersToAddViewModel.self) { [weak self] (continuation: AsyncStream<ObvUIGroupV2.SelectUsersToAddViewModel>.Continuation) in
                guard let self else { return }
                self.continuation = continuation
                do {
                    let model = try createModel()
                    continuation.yield(model)
                } catch {
                    assertionFailure()
                }
            }
            self.stream = stream
            return (streamUUID, stream)
        }

        func updateWithSearchText(_ searchText: String?) {
            guard let continuation else { assertionFailure(); return }
            let newPredicate: NSPredicate
            switch mode {
            case .creation(let ownedCryptoId):
                newPredicate = PersistedObvContactIdentity.getPredicateForAllReachableContactsOfOwnedIdentity(ownedCryptoId: ownedCryptoId, searchText: searchText)
            case .edition(let groupIdentifier):
                newPredicate = PersistedObvContactIdentity.getPredicateForAllReachableContactsOfOwnedIdentityButExcludingGroupMembers(groupIdentifier: groupIdentifier, searchText: searchText)
            }
            self.frc.fetchRequest.predicate = newPredicate
            do {
                try frc.performFetch()
                let model = try createModel()
                continuation.yield(model)
            } catch {
                assertionFailure()
            }
        }

        func finishStream() {
            continuation?.finish()
        }

        func controller(_ controller: NSFetchedResultsController<any NSFetchRequestResult>, didChangeContentWith diff: CollectionDifference<NSManagedObjectID>) {
            guard let continuation else { assertionFailure(); return }
            do {
                let model = try createModel()
                continuation.yield(model)
            } catch {
                assertionFailure()
            }
        }

        private func createModel() throws -> ObvUIGroupV2.SelectUsersToAddViewModel {
            guard let fetchedObjects = frc.fetchedObjects else { assertionFailure(); throw ObvError.fetchedObjectsIsNil }
            let allUserIdentifiers: [ObvUIGroupV2.SelectUsersToAddViewModel.User.Identifier] = fetchedObjects
                .map { $0.objectID }
                .map { ObvUIGroupV2.SelectUsersToAddViewModel.User.Identifier.objectIDOfPersistedObvContactIdentity(objectID: $0) }
            let model = ObvUIGroupV2.SelectUsersToAddViewModel(textOnEmptySetOfUsers: textOnEmptySetOfUsers,
                                                               allUserIdentifiers: allUserIdentifiers)
            return model
        }
        
        enum ObvError: Error {
            case fetchedObjectsIsNil
        }

    }

    
}

// MARK: - Stream Manager for ListOfSingleGroupMemberViewModel

extension AppDataSourceForObvUIGroupV2Router {
        
    private final class ListOfSingleGroupMemberViewModelStreamManager: NSObject, NSFetchedResultsControllerDelegate {
        
        let groupIdentifier: ObvGroupV2Identifier
        let restrictToAdmins: Bool
        let streamUUID = UUID()
        let frc: NSFetchedResultsController<PersistedGroupV2Member>
        let initialPredicate: NSPredicate
        private var stream: AsyncStream<ObvUIGroupV2.ListOfSingleGroupMemberViewModel>?
        private var continuation: AsyncStream<ObvUIGroupV2.ListOfSingleGroupMemberViewModel>.Continuation?

        @MainActor
        init(groupIdentifier: ObvGroupV2Identifier, restrictToAdmins: Bool) {
            self.groupIdentifier = groupIdentifier
            self.restrictToAdmins = restrictToAdmins
            if restrictToAdmins {
                self.frc = PersistedGroupV2Member.getFetchedResultsControllerForAdmins(groupV2Identifier: groupIdentifier, within: ObvStack.shared.viewContext)
            } else {
                self.frc = PersistedGroupV2Member.getFetchedResultsController(groupV2Identifier: groupIdentifier, within: ObvStack.shared.viewContext)
            }
            assert(self.frc.fetchRequest.predicate != nil, "Very unexpected. We are returning all the members of all the groups, of all the profiles.")
            self.initialPredicate = self.frc.fetchRequest.predicate ?? NSPredicate(value: true)
            super.init()
        }
        
        @MainActor
        func startStream() throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.ListOfSingleGroupMemberViewModel>) {
            if let stream {
                return (streamUUID, stream)
            }
            frc.delegate = self
            try frc.performFetch()
            let stream = AsyncStream(ObvUIGroupV2.ListOfSingleGroupMemberViewModel.self) { [weak self] (continuation: AsyncStream<ObvUIGroupV2.ListOfSingleGroupMemberViewModel>.Continuation) in
                guard let self else { return }
                self.continuation = continuation
                do {
                    let model = try createModel()
                    continuation.yield(model)
                } catch {
                    assertionFailure()
                }
            }
            self.stream = stream
            return (streamUUID, stream)
        }
        
        func finishStream() {
            continuation?.finish()
        }
        
        func controller(_ controller: NSFetchedResultsController<any NSFetchRequestResult>, didChangeContentWith diff: CollectionDifference<NSManagedObjectID>) {
            guard let continuation else { assertionFailure(); return }
            do {
                let model = try createModel()
                continuation.yield(model)
            } catch {
                assertionFailure()
            }
        }
        
        func updateWithSearchText(_ searchText: String?) {
            guard let continuation else { assertionFailure(); return }
            let searchPredicate = PersistedGroupV2Member.getSearchPredicate(searchText)
            let newPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                self.initialPredicate,
                searchPredicate,
            ])
            self.frc.fetchRequest.predicate = newPredicate
            do {
                try frc.performFetch()
                let model = try createModel()
                continuation.yield(model)
            } catch {
                assertionFailure()
            }
        }

        private func createModel() throws -> ObvUIGroupV2.ListOfSingleGroupMemberViewModel {
            guard let fetchedObjects = frc.fetchedObjects else { assertionFailure(); throw ObvError.fetchedObjectsIsNil }
            let otherGroupMembers: [SingleGroupMemberViewModelIdentifier] = fetchedObjects
                .map(\.objectID)
                .map { SingleGroupMemberViewModelIdentifier.objectIDOfPersistedGroupV2Member(groupIdentifier: self.groupIdentifier, objectID: $0) }
            let model = ObvUIGroupV2.ListOfSingleGroupMemberViewModel(otherGroupMembers: otherGroupMembers)
            return model
        }
        
        enum ObvError: Error {
            case fetchedObjectsIsNil
        }
        
    }
    
}


// MARK: - Stream Manager for SingleGroupV2MainViewModelOrNotFound

extension AppDataSourceForObvUIGroupV2Router {
    
    private final class SingleGroupV2MainViewModelStreamManager: NSObject, NSFetchedResultsControllerDelegate {
        let streamUUID = UUID()
        private let frcForPersistedGroupV2: NSFetchedResultsController<PersistedGroupV2>
        private let frcForGroupTrustedDetails: NSFetchedResultsController<PersistedGroupV2Details>
        private let frcForGroupPublishedDetails: NSFetchedResultsController<PersistedGroupV2Details>
        private var stream: AsyncStream<ObvUIGroupV2.SingleGroupV2MainViewModelOrNotFound>?
        private var continuation: AsyncStream<ObvUIGroupV2.SingleGroupV2MainViewModelOrNotFound>.Continuation?
        
        @MainActor
        init(groupV2Identifier: ObvGroupV2Identifier) {
            self.frcForPersistedGroupV2 = PersistedGroupV2.getFetchedResultsController(groupV2Identifier: groupV2Identifier, within: ObvStack.shared.viewContext)
            self.frcForGroupTrustedDetails = PersistedGroupV2Details.getFetchedResultsControllerForTrustedDetails(groupV2Identifier: groupV2Identifier, within: ObvStack.shared.viewContext)
            self.frcForGroupPublishedDetails = PersistedGroupV2Details.getFetchedResultsControllerForPublishedDetails(groupV2Identifier: groupV2Identifier, within: ObvStack.shared.viewContext)
            super.init()
        }
        
        @MainActor
        func startStream() throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.SingleGroupV2MainViewModelOrNotFound>) {
            if let stream {
                return (streamUUID, stream)
            }
            frcForPersistedGroupV2.delegate = self
            frcForGroupTrustedDetails.delegate = self
            frcForGroupPublishedDetails.delegate = self
            try frcForPersistedGroupV2.performFetch()
            try frcForGroupTrustedDetails.performFetch()
            try frcForGroupPublishedDetails.performFetch()
            let stream = AsyncStream(ObvUIGroupV2.SingleGroupV2MainViewModelOrNotFound.self) { [weak self] (continuation: AsyncStream<ObvUIGroupV2.SingleGroupV2MainViewModelOrNotFound>.Continuation) in
                guard let self else { return }
                self.continuation = continuation
                do {
                    let model = try createModel()
                    continuation.yield(model)
                } catch {
                    assertionFailure()
                }
            }
            self.stream = stream
            return (streamUUID, stream)
        }
        
        func finishStream() {
            continuation?.finish()
        }
        
        func controller(_ controller: NSFetchedResultsController<any NSFetchRequestResult>, didChangeContentWith diff: CollectionDifference<NSManagedObjectID>) {
            guard let continuation else { assertionFailure(); return }
            do {
                let model = try createModel()
                continuation.yield(model)
            } catch {
                assertionFailure()
            }
        }
        
        private func createModel() throws -> SingleGroupV2MainViewModelOrNotFound {
            guard let fetchedObjects = frcForPersistedGroupV2.fetchedObjects else {
                assertionFailure()
                throw ObvError.couldNotFetchGroup
            }
            guard let persistedGroup = fetchedObjects.first else {
                return .groupNotFound
            }
            let model = try ObvUIGroupV2.SingleGroupV2MainViewModel(with: persistedGroup)
            return .model(model: model)
        }
        
    }
    
}


// MARK: - Stream Manager for GroupLightweightModel

extension AppDataSourceForObvUIGroupV2Router {
    
    private final class GroupLightweightModelStreamManager: NSObject, NSFetchedResultsControllerDelegate {
        
        let streamUUID = UUID()
        private let frc: NSFetchedResultsController<PersistedGroupV2>
        private var stream: AsyncStream<ObvUIGroupV2.GroupLightweightModel>?
        private var continuation: AsyncStream<ObvUIGroupV2.GroupLightweightModel>.Continuation?
        
        @MainActor
        init(groupV2Identifier: ObvGroupV2Identifier) {
            self.frc = PersistedGroupV2.getFetchedResultsController(groupV2Identifier: groupV2Identifier, within: ObvStack.shared.viewContext)
            super.init()
        }

        @MainActor
        func startStream() throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.GroupLightweightModel>) {
            if let stream {
                return (streamUUID, stream)
            }
            frc.delegate = self
            try frc.performFetch()
            let stream = AsyncStream(ObvUIGroupV2.GroupLightweightModel.self) { [weak self] (continuation: AsyncStream<ObvUIGroupV2.GroupLightweightModel>.Continuation) in
                guard let self else { return }
                self.continuation = continuation
                do {
                    let model: GroupLightweightModel = try createModel()
                    continuation.yield(model)
                } catch {
                    assertionFailure()
                }
            }
            self.stream = stream
            return (streamUUID, stream)
        }
        
        func finishStream() {
            continuation?.finish()
        }

        func controller(_ controller: NSFetchedResultsController<any NSFetchRequestResult>, didChangeContentWith diff: CollectionDifference<NSManagedObjectID>) {
            guard let continuation else { assertionFailure(); return }
            do {
                let model = try createModel()
                continuation.yield(model)
            } catch {
                assertionFailure()
            }
        }
        
        private func createModel() throws -> GroupLightweightModel {
            guard let fetchedObjects = frc.fetchedObjects else {
                assertionFailure()
                throw ObvError.couldNotFetchGroup
            }
            guard let persistedGroup = fetchedObjects.first else {
                return .init(ownedIdentityIsAdmin: false, groupType: nil, updateInProgressDuringGroupEdition: false, isKeycloakManaged: false)
            }
            let model = try ObvUIGroupV2.GroupLightweightModel(with: persistedGroup)
            return model
        }

    }
    
}


// MARK: - Stream Manager for SelectUsersToAddViewModel.User

extension AppDataSourceForObvUIGroupV2Router {
    
    private final class SelectUsersToAddViewModelUserStreamManager: NSObject, NSFetchedResultsControllerDelegate {
        
        let streamUUID = UUID()
        private let frc: NSFetchedResultsController<PersistedObvContactIdentity>
        private(set) var stream: AsyncStream<ObvUIGroupV2.SelectUsersToAddViewModel.User>?
        private var continuation: AsyncStream<ObvUIGroupV2.SelectUsersToAddViewModel.User>.Continuation?
        
        init(contactIdentifier: ObvUIGroupV2.SelectUsersToAddViewModel.User.Identifier) throws {
            let objectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>
            switch contactIdentifier {
            case .contactIdentifier(contactIdentifier: _):
                assertionFailure()
                throw ObvError.unexpectedIdentifier
            case .objectIDOfPersistedObvContactIdentity(objectID: let _objectID):
                objectID = .init(objectID: _objectID)
            }
            self.frc = PersistedObvContactIdentity.getFetchedResultsController(objectID: objectID, within: ObvStack.shared.viewContext)
            super.init()
        }
        
        
        @MainActor
        func startStream() throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.SelectUsersToAddViewModel.User>) {
            if let stream {
                return (streamUUID, stream)
            }
            frc.delegate = self
            try frc.performFetch()
            let stream = AsyncStream(ObvUIGroupV2.SelectUsersToAddViewModel.User.self) { [weak self] (continuation: AsyncStream<ObvUIGroupV2.SelectUsersToAddViewModel.User>.Continuation) in
                guard let self else { return }
                self.continuation = continuation
                do {
                    let model = try createModel()
                    continuation.yield(model)
                } catch {
                    // Do nothing, this can happen when removing a member
                }
            }
            self.stream = stream
            return (streamUUID, stream)
        }
        
        
        func finishStream() {
            continuation?.finish()
        }

        
        private func createModel() throws -> ObvUIGroupV2.SelectUsersToAddViewModel.User {
            guard let fetchedObjects = frc.fetchedObjects else { assertionFailure(); throw ObvError.fetchedObjectsIsNil }
            guard let persistedContact = fetchedObjects.first else {
                assertionFailure()
                throw ObvError.contactNotFound
            }
            let model = try ObvUIGroupV2.SelectUsersToAddViewModel.User(persistedContact: persistedContact)
            return model
        }

        
        func controller(_ controller: NSFetchedResultsController<any NSFetchRequestResult>, didChangeContentWith diff: CollectionDifference<NSManagedObjectID>) {
            guard let continuation else { assertionFailure(); return }
            do {
                let model = try createModel()
                continuation.yield(model)
            } catch {
                // Do nothing, this can happen when removing a member
            }
        }

        
        enum ObvError: Error {
            case unexpectedIdentifier
            case fetchedObjectsIsNil
            case contactNotFound
        }

    }
    
}

// MARK: - Stream Manager for SingleGroupMemberViewModel

extension AppDataSourceForObvUIGroupV2Router {
    
    private final class SingleGroupMemberViewModelStreamManager: NSObject, NSFetchedResultsControllerDelegate {

        private enum Mode {
            case groupEdition(frc: NSFetchedResultsController<PersistedGroupV2Member>, frcForOneToOneInvitation: NSFetchedResultsController<PersistedInvitationOneToOneInvitationSent>?)
            case groupCreation(frc: NSFetchedResultsController<PersistedObvContactIdentity>)
        }
        
        private let mode: Mode
        let streamUUID = UUID()
        private(set) var stream: AsyncStream<ObvUIGroupV2.SingleGroupMemberViewModel>?
        private var continuation: AsyncStream<ObvUIGroupV2.SingleGroupMemberViewModel>.Continuation?
        
        @MainActor
        init(memberIdentifier: ObvUIGroupV2.SingleGroupMemberViewModelIdentifier) throws {
            do {
                switch memberIdentifier {

                case .objectIDOfPersistedContact(objectID: let _objectID):

                    let objectID = TypeSafeManagedObjectID<PersistedObvContactIdentity>(objectID: _objectID)
                    let frc = PersistedObvContactIdentity.getFetchedResultsController(objectID: objectID, within: ObvStack.shared.viewContext)
                    self.mode = .groupCreation(frc: frc)

                case .objectIDOfPersistedGroupV2Member(groupIdentifier: _, objectID: let _objectID):
                    
                    // Instantiate the NSFetchedResultsController for the group member

                    let objectID = TypeSafeManagedObjectID<PersistedGroupV2Member>(objectID: _objectID)
                    let frc = PersistedGroupV2Member.getFetchedResultsController(objectID: objectID, within: ObvStack.shared.viewContext)

                    // Instantiate the NSFetchedResultsController for one2one invitation
                    let frcForOneToOneInvitation: NSFetchedResultsController<PersistedInvitationOneToOneInvitationSent>?
                    do {
                        switch memberIdentifier {
                        case .contactIdentifierForExistingGroup(groupIdentifier: _, contactIdentifier: _):
                            assertionFailure()
                            throw ObvError.unexpectedIdentifier
                        case .objectIDOfPersistedGroupV2Member(groupIdentifier: _, objectID: let objectID):
                            if let groupMember = try PersistedGroupV2Member.get(objectID: objectID, within: ObvStack.shared.viewContext) {
                                let ownedCryptoId = try groupMember.persistedGroup.ownCryptoId
                                let remoteCryptoId = groupMember.cryptoId
                                frcForOneToOneInvitation = PersistedInvitationOneToOneInvitationSent.getFetchedResultsController(ownedCryptoId: ownedCryptoId, remoteCryptoId: remoteCryptoId, within: ObvStack.shared.viewContext)
                            } else {
                                // This happens if the member was just removed from the group
                                frcForOneToOneInvitation = nil
                            }
                        case .contactIdentifierForCreatingGroup(contactIdentifier: _):
                            assertionFailure()
                            throw ObvError.unexpectedIdentifier
                        case .objectIDOfPersistedContact(objectID: _):
                            assertionFailure("This identifier shall only be used when creating a new group, not when updating an existing one.")
                            throw ObvError.unexpectedIdentifier
                        }
                    } catch {
                        assertionFailure() // Do not fail in production
                        frcForOneToOneInvitation = nil
                    }
                    self.mode = .groupEdition(frc: frc, frcForOneToOneInvitation: frcForOneToOneInvitation)
                    
                case .contactIdentifierForCreatingGroup(contactIdentifier: _):
                    
                    assertionFailure()
                    throw ObvError.unexpectedIdentifier

                case .contactIdentifierForExistingGroup(groupIdentifier: _, contactIdentifier: _):
                    
                    assertionFailure()
                    throw ObvError.unexpectedIdentifier
                    
                }
            }
            super.init()
        }

        deinit {
            debugPrint("SingleGroupMemberViewModelStreamManager deinit")
        }
        
        @MainActor
        func startStream() throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.SingleGroupMemberViewModel>) {
            if let stream {
                return (streamUUID, stream)
            }
            
            switch mode {
                
            case .groupEdition(frc: let frc, frcForOneToOneInvitation: let frcForOneToOneInvitation):
                
                frc.delegate = self
                try frc.performFetch()
                frcForOneToOneInvitation?.delegate = self
                try? frcForOneToOneInvitation?.performFetch() // Do not fail in production
                let stream = AsyncStream(ObvUIGroupV2.SingleGroupMemberViewModel.self) { [weak self] (continuation: AsyncStream<ObvUIGroupV2.SingleGroupMemberViewModel>.Continuation) in
                    guard let self else { return }
                    self.continuation = continuation
                    do {
                        let model = try createModel()
                        continuation.yield(model)
                    } catch {
                        // Do nothing, this can happen when removing a member
                    }
                }
                self.stream = stream
                return (streamUUID, stream)

            case .groupCreation(frc: let frc):
                
                frc.delegate = self
                try frc.performFetch()

                let stream = AsyncStream(ObvUIGroupV2.SingleGroupMemberViewModel.self) { [weak self] (continuation: AsyncStream<ObvUIGroupV2.SingleGroupMemberViewModel>.Continuation) in
                    guard let self else { return }
                    self.continuation = continuation
                    do {
                        let model = try createModel()
                        continuation.yield(model)
                    } catch {
                        // Do nothing, this can happen when removing a member
                    }
                }
                self.stream = stream
                return (streamUUID, stream)
                
            }
            
        }
        
        func finishStream() {
            continuation?.finish()
        }
        
        func controller(_ controller: NSFetchedResultsController<any NSFetchRequestResult>, didChangeContentWith diff: CollectionDifference<NSManagedObjectID>) {
            guard let continuation else { assertionFailure(); return }
            do {
                let model = try createModel()
                continuation.yield(model)
            } catch {
                // Do nothing, this can happen when removing a member
            }
        }
        
        private func createModel() throws -> SingleGroupMemberViewModel {
            
            switch mode {
                
            case .groupEdition(frc: let frc, frcForOneToOneInvitation: let frcForOneToOneInvitation):
                
                guard let fetchedObjects = frc.fetchedObjects else { assertionFailure(); throw ObvError.fetchedObjectsIsNil }
                guard let persistedMember = fetchedObjects.first else {
                    // Happens when removing a member
                    throw ObvError.memberNotFound
                }
                let oneToOneInvitationSentToMember = frcForOneToOneInvitation?.fetchedObjects?.first
                let model = try ObvUIGroupV2.SingleGroupMemberViewModel(persistedMember: persistedMember, oneToOneInvitationSentToMember: oneToOneInvitationSentToMember)
                return model

                
            case .groupCreation(let frc):
                
                guard let fetchedObjects = frc.fetchedObjects else { assertionFailure(); throw ObvError.fetchedObjectsIsNil }
                guard let persistedContact = fetchedObjects.first else {
                    assertionFailure()
                    throw ObvError.contactNoFound
                }
                let model = try ObvUIGroupV2.SingleGroupMemberViewModel(persistedContact: persistedContact)
                return model
                
            }
            
        }
        
        enum ObvError: Error {
            case unexpectedIdentifier
            case fetchedObjectsIsNil
            case memberNotFound
            case contactNoFound
        }
        
    }

}





// MARK: - Implementing ObvUIGroupV2RouterDataSource

extension AppDataSourceForObvUIGroupV2Router: ObvUIGroupV2RouterDataSource {
                
    func getAsyncSequenceOfSingleGroupMemberViewModels(_ router: ObvUIGroupV2.ObvUIGroupV2Router, memberIdentifier: ObvUIGroupV2.SingleGroupMemberViewModelIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.SingleGroupMemberViewModel>) {
        
        let streamManager = try SingleGroupMemberViewModelStreamManager(memberIdentifier: memberIdentifier)
        let (streamUUID, stream) = try streamManager.startStream()
        self.singleGroupMemberViewModelStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
        
    }
    
    
    func finishAsyncSequenceOfSingleGroupMemberViewModels(_ router: ObvUIGroupV2.ObvUIGroupV2Router, memberIdentifier: ObvUIGroupV2.SingleGroupMemberViewModelIdentifier, streamUUID: UUID) {
        guard let streamManager = singleGroupMemberViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        streamManager.finishStream()
    }
    
    
    func getAsyncSequenceOfListOfSingleGroupMemberViewModel(_ router: ObvUIGroupV2.ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.ListOfSingleGroupMemberViewModel>) {
        
        let streamManager = ListOfSingleGroupMemberViewModelStreamManager(groupIdentifier: groupIdentifier, restrictToAdmins: false)
        let (streamUUID, stream) = try streamManager.startStream()
        self.listOfSingleGroupMemberViewModelStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)

    }
    
    
    func filterAsyncSequenceOfListOfSingleGroupMemberViewModel(_ router: ObvUIGroupV2.ObvUIGroupV2Router, streamUUID: UUID, searchText: String?) {
        guard let streamManager = listOfSingleGroupMemberViewModelStreamManagerForStreamUUID[streamUUID] else { return }
        streamManager.updateWithSearchText(searchText)
    }

    
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModel(_ router: ObvUIGroupV2.ObvUIGroupV2Router, streamUUID: UUID) {
        guard let streamManager = listOfSingleGroupMemberViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        streamManager.finishStream()
    }

    
    func getAsyncSequenceOfListOfSingleGroupAdminsMemberViewModel(_ router: ObvUIGroupV2.ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.ListOfSingleGroupMemberViewModel>) {
        
        let streamManager = ListOfSingleGroupMemberViewModelStreamManager(groupIdentifier: groupIdentifier, restrictToAdmins: true)
        let (streamUUID, stream) = try streamManager.startStream()
        self.listOfSingleGroupMemberViewModelStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)

    }
    
    
    func finishAsyncSequenceOfListOfSingleGroupAdminsMemberViewModel(_ router: ObvUIGroupV2.ObvUIGroupV2Router, streamUUID: UUID) {
        guard let streamManager = listOfSingleGroupMemberViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        streamManager.finishStream()
    }
    
    
    /// Called when displaying the single group v2 view.
    func getAsyncSequenceOfSingleGroupV2MainViewModel(_ router: ObvUIGroupV2.ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.SingleGroupV2MainViewModelOrNotFound>) {

        let streamManager = SingleGroupV2MainViewModelStreamManager(groupV2Identifier: groupIdentifier)
        let (streamUUID, stream) = try streamManager.startStream()
        self.singleGroupV2MainViewModelStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)

    }
    
    
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(_ router: ObvUIGroupV2.ObvUIGroupV2Router, streamUUID: UUID) {
        guard let streamManager = singleGroupV2MainViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        streamManager.finishStream()
    }
    
    
    func getAsyncSequenceOfGroupLightweightModel(_ router: ObvUIGroupV2.ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.GroupLightweightModel>) {

        let streamManager = GroupLightweightModelStreamManager(groupV2Identifier: groupIdentifier)
        let (streamUUID, stream) = try streamManager.startStream()
        self.groupLightweightModelStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)

    }
    
    
    func finishAsyncSequenceOfGroupLightweightModel(_ router: ObvUIGroupV2.ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier, streamUUID: UUID) {
        guard let streamManager = groupLightweightModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        streamManager.finishStream()
    }
    
    
    /// Called when displaying a list of contacts that can be added to a group. We display both one2one and non-one2one contacts. We remove the contacts that are already parts of the group members.
    func getAsyncSequenceOfSelectUsersToAddViewModel(_ router: ObvUIGroupV2.ObvUIGroupV2Router, mode: ObvUIGroupV2.ObvUIGroupV2RouterDataSourceMode) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.SelectUsersToAddViewModel>) {
        let streamManager = SelectUsersToAddViewModelStreamManager(mode: mode)
        let (streamUUID, stream) = try streamManager.startStream()
        self.selectUsersToAddViewModelStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }

    
    func filterAsyncSequenceOfSelectUsersToAddViewModel(_ router: ObvUIGroupV2Router, streamUUID: UUID, searchText: String?) {
        guard let streamManager = selectUsersToAddViewModelStreamManagerForStreamUUID[streamUUID] else { return }
        streamManager.updateWithSearchText(searchText)
    }

    
    func finishAsyncSequenceOfSelectUsersToAddViewModel(_ router: ObvUIGroupV2.ObvUIGroupV2Router, streamUUID: UUID) {
        guard let streamManager = selectUsersToAddViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        streamManager.finishStream()
    }
    
    
    func getAsyncSequenceOfSelectUsersToAddViewModelUser(_ router: ObvUIGroupV2.ObvUIGroupV2Router, withIdentifier identifier: ObvUIGroupV2.SelectUsersToAddViewModel.User.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.SelectUsersToAddViewModel.User>) {

        let streamManager = try SelectUsersToAddViewModelUserStreamManager(contactIdentifier: identifier)
        let (streamUUID, stream) = try streamManager.startStream()
        self.selectUsersToAddViewModelUserStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)

    }
    
    
    func finishAsyncSequenceOfSelectUsersToAddViewModelUser(_ router: ObvUIGroupV2.ObvUIGroupV2Router, withIdentifier identifier: ObvUIGroupV2.SelectUsersToAddViewModel.User.Identifier, streamUUID: UUID) {
        guard let streamManager = selectUsersToAddViewModelUserStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        streamManager.finishStream()
    }
    
    
    func fetchAvatarImage(_ router: ObvUIGroupV2.ObvUIGroupV2Router, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.fetchAvatarImage(self, localPhotoURL: photoURL, avatarSize: avatarSize)
    }


    func getContactIdentifierOfUser(_ router: ObvUIGroupV2.ObvUIGroupV2Router, contactIdentifier: ObvUIGroupV2.SelectUsersToAddViewModel.User.Identifier) async throws -> ObvTypes.ObvContactIdentifier {
        switch contactIdentifier {
        case .contactIdentifier(let contactIdentifier):
            return contactIdentifier
        case .objectIDOfPersistedObvContactIdentity(let objectID):
            guard let persistedContact = try PersistedObvContactIdentity.get(objectID: objectID, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                throw ObvError.couldNotFindContact
            }
            return try persistedContact.obvContactIdentifier
        }
    }
    
    
    func getContactIdentifierOfGroupMember(_ router: ObvUIGroupV2Router, contactIdentifier: SingleGroupMemberViewModelIdentifier) async throws -> ObvContactIdentifier {
        switch contactIdentifier {
        case .contactIdentifierForExistingGroup(groupIdentifier: _, contactIdentifier: let contactIdentifier):
            return contactIdentifier
        case .objectIDOfPersistedGroupV2Member(groupIdentifier: _, objectID: let objectID):
            guard let persistedMember = try PersistedGroupV2Member.get(objectID: objectID, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                throw ObvError.couldNotFindGroupMember
            }
            let memberCryptoId = persistedMember.cryptoId
            let ownedCryptoId = try persistedMember.persistedGroup.ownCryptoId
            return ObvContactIdentifier(contactCryptoId: memberCryptoId, ownedCryptoId: ownedCryptoId)
        case .contactIdentifierForCreatingGroup(contactIdentifier: let contactIdentifier):
            return contactIdentifier
        case .objectIDOfPersistedContact(objectID: let objectID):
            guard let persistedContact = try PersistedObvContactIdentity.get(objectID: objectID, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                throw ObvError.couldNotFindContact
            }
            return try persistedContact.obvContactIdentifier
        }
    }
    
    
    func getContactIdentifierOfGroupMember(_ router: ObvUIGroupV2.ObvUIGroupV2Router, contactIdentifier: ObvUIGroupV2.SelectUsersToAddViewModel.User.Identifier) async throws -> ObvTypes.ObvContactIdentifier {
        switch contactIdentifier {
        case .contactIdentifier(contactIdentifier: let contactIdentifier):
            return contactIdentifier
        case .objectIDOfPersistedObvContactIdentity(objectID: let objectID):
            guard let persistedContact = try PersistedObvContactIdentity.get(objectID: objectID, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                throw ObvError.couldNotFindContact
            }
            return try persistedContact.contactIdentifier
        }
    }

    
    func getGroupType(_ router: ObvUIGroupV2Router, groupIdentifier: ObvGroupV2Identifier) async throws -> ObvGroupType {
        guard let persistedGroup = try PersistedGroupV2.getWithPrimaryKey(ownCryptoId: groupIdentifier.ownedCryptoId, groupIdentifier: groupIdentifier.identifier.appGroupIdentifier, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            throw ObvError.couldNotFetchGroup
        }
        guard let groupType = persistedGroup.groupType else {
            assertionFailure()
            throw ObvError.couldNotFetchGroupType
        }
        return groupType
    }
    

    /// This is called during group creation, when the user performs a search on the screen allowing to choose admins. We receive a list of all the peristed contacts choosen during the group creation. We must return a subset
    /// of these contacts, restricting to those matching the search text.
    func filterUsersWithSearchText(users: [SelectUsersToAddViewModel.User.Identifier], searchText: String?) -> [SelectUsersToAddViewModel.User.Identifier] {
        
        let sanitizedSearchText = searchText?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sanitizedSearchText, !sanitizedSearchText.isEmpty else {
            return users
        }

        do {
            
            let objectIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>] = try users.map { user in
                switch user {
                case .contactIdentifier(contactIdentifier: _):
                    assertionFailure()
                    throw ObvError.unexpectedIdentifier
                case .objectIDOfPersistedObvContactIdentity(objectID: let objectID):
                    return .init(objectID: objectID)
                }
            }
            
            let filteredObjectIDs = try PersistedObvContactIdentity.filterAll(objectIDs: objectIDs, searchText: searchText, within: ObvStack.shared.viewContext)
            
            let filteredUsers: [SelectUsersToAddViewModel.User.Identifier] = filteredObjectIDs.map { objectID in
                return SelectUsersToAddViewModel.User.Identifier.objectIDOfPersistedObvContactIdentity(objectID: objectID.objectID)
            }
            
            return filteredUsers
            
        } catch {
            assertionFailure()
            return users
        }
        
    }
    
    
    /// Called when displaying the group details, for the view showing the number of group members that are:
    /// - contacts
    /// - but not yet one-to-one.
    /// These are the contacts that can be invited to a one-to-one discussion.
    func getAsyncSequenceOfOneToOneInvitableViewModel(_ router: ObvUIGroupV2.ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.OneToOneInvitableViewModel>) {
        let streamManager = OneToOneInvitableViewModelStreamManager(groupIdentifier: groupIdentifier)
        let (streamUUID, stream) = try streamManager.startStream()
        self.oneToOneInvitableViewModelStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }
    
    
    func finishAsyncSequenceOfOneToOneInvitableViewModel(_ router: ObvUIGroupV2.ObvUIGroupV2Router, streamUUID: UUID) {
        guard let streamManager = oneToOneInvitableViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        streamManager.finishStream()
    }

    
    /// Called when displaying the list of group members split in 3 sections:
    /// - Group members that are not yet one2one contacts but that can be invited.
    /// - Group members that are not yet one2one contacts but that must accept the group invitation before they can be invited
    /// - Group members that are one2one contacts already.
    /// Note that since we only return members identifiers in the model, we don't need to know whether invitable group members have already been invited.
    func getAsyncSequenceOfOnetoOneInvitableGroupMembersViewModel(_ router: ObvUIGroupV2.ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.OnetoOneInvitableGroupMembersViewModel>) {
        let streamManager = OnetoOneInvitableGroupMembersViewModelStreamManager(groupIdentifier: groupIdentifier)
        let (streamUUID, stream) = try streamManager.startStream()
        self.onetoOneInvitableGroupMembersViewModelStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }
    
    func finishAsyncSequenceOfOnetoOneInvitableGroupMembersViewModel(_ router: ObvUIGroupV2.ObvUIGroupV2Router, streamUUID: UUID) {
        guard let streamManager = onetoOneInvitableGroupMembersViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        streamManager.finishStream()
    }

    
    /// Called when displaying the list of group members split in 3 sections (set also `getAsyncSequenceOfOnetoOneInvitableGroupMembersViewModel`).
    /// This is called for each cell, to obtain a stream of updates correponding to a particular group member.
    func getAsyncSequenceOfOnetoOneInvitableGroupMembersViewCellModels(_ router: ObvUIGroupV2.ObvUIGroupV2Router, identifier: ObvUIGroupV2.OnetoOneInvitableGroupMembersViewModel.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.OnetoOneInvitableGroupMembersViewCellModel>) {
        let streamManager = try OnetoOneInvitableGroupMembersViewCellModelStreamManager(memberIdentifier: identifier)
        let (streamUUID, stream) = try streamManager.startStream()
        self.onetoOneInvitableGroupMembersViewCellModelStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }
    
    
    func finishAsyncSequenceOfOnetoOneInvitableGroupMembersViewCellModels(_ router: ObvUIGroupV2.ObvUIGroupV2Router, identifier: ObvUIGroupV2.OnetoOneInvitableGroupMembersViewModel.Identifier, streamUUID: UUID) {
        guard let streamManager = onetoOneInvitableGroupMembersViewCellModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        streamManager.finishStream()
    }

    
    /// Called during the cloning of an existing group, to get all the initial values of the new group.
    func getValuesOfGroupToClone(_ router: ObvUIGroupV2.ObvUIGroupV2Router, identifierOfGroupToClone: ObvTypes.ObvGroupV2Identifier) async throws -> ObvUIGroupV2.ObvUIGroupV2Router.ValuesOfClonedGroup {
        guard let persistedGroup = try PersistedGroupV2.get(ownIdentity: identifierOfGroupToClone.ownedCryptoId, appGroupIdentifier: identifierOfGroupToClone.identifier.appGroupIdentifier, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            throw ObvError.groupIsNil
        }
        let valuesOfClonedGroup = try ObvUIGroupV2.ObvUIGroupV2Router.ValuesOfClonedGroup(persistedGroup: persistedGroup)
        return valuesOfClonedGroup
    }

    
    func getContactIdentifiers(_ router: ObvUIGroupV2.ObvUIGroupV2Router, identifiers: [ObvUIGroupV2.OnetoOneInvitableGroupMembersViewModel.Identifier]) async throws -> [ObvTypes.ObvContactIdentifier] {
        var contactIdentifiers = [ObvTypes.ObvContactIdentifier]()
        for identifier in identifiers {
            switch identifier {
            case .contactIdentifier(contactIdentifier: let contactIdentifier):
                contactIdentifiers.append(contactIdentifier)
            case .objectIDOfPersistedGroupV2Member(objectID: let objectID):
                guard let groupMember = try PersistedGroupV2Member.get(objectID: objectID, within: ObvStack.shared.viewContext) else {
                    assertionFailure()
                    continue
                }
                if let contactIdentifier: ObvContactIdentifier = try groupMember.contact?.contactIdentifier {
                    contactIdentifiers.append(contactIdentifier)
                }
            case .objectIDOfPersistedObvContactIdentity(objectID: let objectID):
                guard let contact = try PersistedObvContactIdentity.get(objectID: objectID, within: ObvStack.shared.viewContext) else {
                    assertionFailure()
                    continue
                }
                let contactIdentifier: ObvContactIdentifier = try contact.contactIdentifier
                contactIdentifiers.append(contactIdentifier)
            }
        }
        return contactIdentifiers
    }

    
    func getAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ router: ObvUIGroupV2.ObvUIGroupV2Router, groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.OwnedIdentityAsGroupMemberViewModel>) {
        let streamManager = OwnedIdentityAsGroupMemberViewModelStreamManager(groupIdentifier: groupIdentifier)
        let (streamUUID, stream) = try streamManager.startStream()
        self.ownedIdentityAsGroupMemberViewModelStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }
    
    
    func finishAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ router: ObvUIGroupV2.ObvUIGroupV2Router, groupIdentifier: ObvGroupV2Identifier, streamUUID: UUID) {
        guard let streamManager = ownedIdentityAsGroupMemberViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        streamManager.finishStream()
    }

}


// MARK: - Other methods, called from the app directly

extension AppDataSourceForObvUIGroupV2Router {
    
    func getValuesOfGroupToClone(persistedContactGroup: PersistedContactGroup) async throws -> ObvUIGroupV2.ObvUIGroupV2Router.ValuesOfClonedGroup {
        let valuesOfClonedGroup = try ObvUIGroupV2.ObvUIGroupV2Router.ValuesOfClonedGroup(persistedContactGroup: persistedContactGroup)
        return valuesOfClonedGroup
    }
    
}


// MARK: - Errors

extension AppDataSourceForObvUIGroupV2Router {
    
    enum ObvError: Error {
        case delegateIsNil
        case couldNotFetchGroup
        case couldNotFindContact
        case couldNotFoundOwnedIdentity
        case couldNotFetchGroupType
        case couldNotFindGroupMember
        case unexpectedIdentifier
        case groupIsNil
        case groupCannotBeFound
    }
 
}


// MARK: - GroupLightweightModel from PersistedGroupV2

extension GroupLightweightModel {
    
    init(with persistedGroup: PersistedGroupV2) throws {
        self.init(ownedIdentityIsAdmin: persistedGroup.ownedIdentityIsAdmin,
                  groupType: persistedGroup.groupType,
                  updateInProgressDuringGroupEdition: persistedGroup.updateInProgress,
                  isKeycloakManaged: persistedGroup.keycloakManaged)
    }
    
}


// MARK: SingleGroupV2MainViewModel from a PersistedGroupV2

extension SingleGroupV2MainViewModel {
    
    init(with persistedGroup: PersistedGroupV2) throws {
        
        let ownedIdentityCanLeaveGroup: SingleGroupV2MainViewModel.CanLeaveGroup
        switch persistedGroup.ownedIdentityCanLeaveGroup {
        case .canLeaveGroup:
            ownedIdentityCanLeaveGroup = .canLeaveGroup
        case .cannotLeaveGroupAsThisIsKeycloakGroup:
            ownedIdentityCanLeaveGroup = .cannotLeaveGroupAsThisIsKeycloakGroup
        case .cannotLeaveGroupAsWeAreTheOnlyAdmin:
            ownedIdentityCanLeaveGroup = .cannotLeaveGroupAsWeAreTheOnlyAdmin
        }
        
        let publishedDetailsForValidation: PublishedDetailsValidationViewModel?
        if let detailsPublished = persistedGroup.detailsPublished {
            var differences = DifferencesBetweenTrustedAndPublished()
            if persistedGroup.detailsPublished?.name != persistedGroup.detailsTrusted?.name {
                differences.insert(.name)
            }
            if persistedGroup.detailsPublished?.groupDescription != persistedGroup.detailsTrusted?.groupDescription {
                differences.insert(.description)
            }
            switch (persistedGroup.detailsPublished?.photoURLFromEngine, persistedGroup.detailsTrusted?.photoURLFromEngine) {
            case (nil, nil):
                break
            case (.some, nil), (nil, .some):
                differences.insert(.photo)
            case (.some(let publishedURL), .some(let trustedURL)):
                if publishedURL != trustedURL && !FileManager.default.contentsEqual(atPath: publishedURL.path, andPath: trustedURL.path) {
                    differences.insert(.photo)
                }
            }
            if differences.isEmpty {
                publishedDetailsForValidation = nil
            } else {
                publishedDetailsForValidation = .init(groupIdentifier: try persistedGroup.obvGroupIdentifier,
                                                      publishedName: detailsPublished.name ?? persistedGroup.displayName,
                                                      publishedDescription: detailsPublished.groupDescription,
                                                      publishedPhotoURL: detailsPublished.photoURLFromEngine,
                                                      circleColors: .init(background: persistedGroup.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                                                          foreground: persistedGroup.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                                                      differences: differences,
                                                      isKeycloakManaged: persistedGroup.keycloakManaged)
            }
        } else {
            publishedDetailsForValidation = nil
        }

        self.init(groupIdentifier: try persistedGroup.obvGroupIdentifier,
                  trustedName: persistedGroup.displayName,
                  trustedDescription: persistedGroup.trustedDescription,
                  trustedPhotoURL: persistedGroup.trustedPhotoURL,
                  customPhotoURL: persistedGroup.customPhotoURL,
                  nickname: persistedGroup.customNameSanitized,
                  isKeycloakManaged: persistedGroup.keycloakManaged,
                  circleColors: .init(background: persistedGroup.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                      foreground: persistedGroup.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                  updateInProgress: persistedGroup.updateInProgress,
                  ownedIdentityIsAdmin: persistedGroup.ownedIdentityIsAdmin,
                  ownedIdentityCanLeaveGroup: ownedIdentityCanLeaveGroup,
                  publishedDetailsForValidation: publishedDetailsForValidation,
                  personalNote: persistedGroup.personalNote,
                  groupType: persistedGroup.groupType)
    }

}


// MARK: - SingleGroupMemberViewModel from a PersistedGroupV2Member

extension SingleGroupMemberViewModel {
 
    init(persistedMember: PersistedGroupV2Member, oneToOneInvitationSentToMember: PersistedInvitationOneToOneInvitationSent?) throws {
                
        if let persistedContact = persistedMember.contact {
        
            let isOneToOneContact: SingleGroupMemberViewModel.IsOneToOneContact
            if persistedContact.isOneToOne {
                isOneToOneContact = .yes
            } else {
                let canSendOneToOneInvitation: Bool = oneToOneInvitationSentToMember == nil
                isOneToOneContact = .no(canSendOneToOneInvitation: canSendOneToOneInvitation)
            }

            self.init(contactIdentifier: try persistedContact.contactIdentifier,
                      permissions: persistedMember.permissions,
                      isKeycloakManaged: persistedContact.isCertifiedByOwnKeycloak,
                      profilePictureInitial: persistedContact.circledInitialsConfiguration.initials?.text,
                      circleColors: .init(background: persistedContact.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                          foreground: persistedContact.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                      identityDetails: try persistedContact.identityDetails,
                      isOneToOneContact: isOneToOneContact,
                      isRevokedAsCompromised: false,
                      isPending: persistedMember.isPending,
                      detailedProfileCanBeShown: true,
                      customDisplayName: persistedContact.customDisplayNameSanitized,
                      customPhotoURL: persistedContact.customPhotoURL)
            
        } else {
            
            let contactIdentifier = ObvContactIdentifier(contactCryptoId: persistedMember.cryptoId, ownedCryptoId: try persistedMember.persistedGroup.ownCryptoId)
            self.init(contactIdentifier: contactIdentifier,
                      permissions: persistedMember.permissions,
                      isKeycloakManaged: persistedMember.isKeycloakManaged,
                      profilePictureInitial: persistedMember.circledInitialsConfiguration.initials?.text,
                      circleColors: .init(background: persistedMember.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                          foreground: persistedMember.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                      identityDetails: try persistedMember.identityDetails,
                      isOneToOneContact: .no(canSendOneToOneInvitation: false), // We cannot invite a pending member who is not part of our contacts
                      isRevokedAsCompromised: false,
                      isPending: persistedMember.isPending,
                      detailedProfileCanBeShown: false,
                      customDisplayName: nil,
                      customPhotoURL: nil)
            
        }
    }
    
    
    /// Called when creating a `SingleGroupMemberViewModel` during a group creation.
    init(persistedContact: PersistedObvContactIdentity) throws {
        
        let isOneToOneContact: IsOneToOneContact
        if persistedContact.isOneToOne {
            isOneToOneContact = .yes
        } else {
            isOneToOneContact = .no(canSendOneToOneInvitation: false)
        }
        
        // Note that we do not specify any permission here. This is not required during a group creation.
        self.init(contactIdentifier: try persistedContact.contactIdentifier,
                  permissions: Set<ObvGroupV2.Permission>(),
                  isKeycloakManaged: persistedContact.isCertifiedByOwnKeycloak,
                  profilePictureInitial: persistedContact.circledInitialsConfiguration.initials?.text,
                  circleColors: .init(background: persistedContact.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                      foreground: persistedContact.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                  identityDetails: try persistedContact.identityDetails,
                  isOneToOneContact: isOneToOneContact,
                  isRevokedAsCompromised: false,
                  isPending: false,
                  detailedProfileCanBeShown: false,
                  customDisplayName: persistedContact.customDisplayNameSanitized,
                  customPhotoURL: persistedContact.customPhotoURL)
        
    }

}


// MARK: - ObvUIGroupV2.SelectUsersToAddViewModel.User from a PersistedObvContactIdentity

extension ObvUIGroupV2.SelectUsersToAddViewModel.User {
    
    init(persistedContact: PersistedObvContactIdentity) throws {
        self.init(identifier: .objectIDOfPersistedObvContactIdentity(objectID: persistedContact.objectID),
                  isKeycloakManaged: persistedContact.isCertifiedByOwnKeycloak,
                  profilePictureInitial: persistedContact.circledInitialsConfiguration.initials?.text,
                  circleColors: .init(background: persistedContact.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                      foreground: persistedContact.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                  identityDetails: try persistedContact.identityDetails,
                  isRevokedAsCompromised: false,
                  customDisplayName: persistedContact.customDisplayNameSanitized,
                  customPhotoURL: persistedContact.customPhotoURL)
    }
    
}


// MARK: - ObvUIGroupV2.ObvUIGroupV2Router.ValuesOfClonedGroup from PersistedGroupV2

extension ObvUIGroupV2.ObvUIGroupV2Router.ValuesOfClonedGroup {
    
    init(persistedGroup: PersistedGroupV2) throws {
        
        // We only keep persisted contacts (instances of PersistedObvContactIdentity)
        let contactsAmongMembers: [PersistedObvContactIdentity] = persistedGroup.otherMembers.compactMap(\.contact)
        let userIdentifiersOfAddedUsers: [SelectUsersToAddViewModel.User.Identifier] = contactsAmongMembers.map({ .objectIDOfPersistedObvContactIdentity(objectID: $0.objectID) })
        
        let admins: [PersistedObvContactIdentity] = persistedGroup.otherMembers.filter({ $0.isAnAdmin }).compactMap(\.contact)
        let selectedAdmins: [SingleGroupMemberViewModelIdentifier] = admins.map({ .objectIDOfPersistedContact(objectID: $0.objectID) })
        
        let selectedPhoto: UIImage?
        if let trustedPhotoURL = persistedGroup.trustedPhotoURL {
            selectedPhoto = UIImage(contentsOfFile: trustedPhotoURL.path)
        } else {
            selectedPhoto = nil
        }
        
        self.init(userIdentifiersOfAddedUsers: userIdentifiersOfAddedUsers,
                  selectedAdmins: Set(selectedAdmins),
                  selectedGroupType: persistedGroup.groupType,
                  selectedPhoto: selectedPhoto,
                  selectedGroupName: persistedGroup.trustedName,
                  selectedGroupDescription: persistedGroup.trustedDescription)
        
    }
    
}


// MARK: - ObvUIGroupV2.ObvUIGroupV2Router.ValuesOfClonedGroup from PersistedContactGroup

extension ObvUIGroupV2.ObvUIGroupV2Router.ValuesOfClonedGroup {
    
    init(persistedContactGroup: PersistedContactGroup) throws {
        
        guard let ownedIdentity = persistedContactGroup.ownedIdentity else { assertionFailure(); throw ObvErrorForInitBaseOnPersistedContactGroup.ownedIdentityIsNil }

        // userIdentifiersOfAddedUsers
        
        let contactsAmongPendingMembers = Set(persistedContactGroup.pendingMembers
            .map({ $0.cryptoId })
            .compactMap({ try? PersistedObvContactIdentity.get(cryptoId: $0, ownedIdentity: ownedIdentity, whereOneToOneStatusIs: .any) }))
        let candidates = persistedContactGroup.contactIdentities.union(contactsAmongPendingMembers)

        let userIdentifiersOfAddedUsers: [SelectUsersToAddViewModel.User.Identifier] = candidates
            .map({ .objectIDOfPersistedObvContactIdentity(objectID: $0.objectID) })
        
        // selectedPhoto
        
        let selectedPhoto: UIImage?
        if let trustedPhotoURL = persistedContactGroup.displayPhotoURL {
            selectedPhoto = UIImage(contentsOfFile: trustedPhotoURL.path)
        } else {
            selectedPhoto = nil
        }

        self.init(userIdentifiersOfAddedUsers: userIdentifiersOfAddedUsers,
                  selectedAdmins: Set<SingleGroupMemberViewModelIdentifier>(),
                  selectedGroupType: .standard,
                  selectedPhoto: selectedPhoto,
                  selectedGroupName: persistedContactGroup.groupName,
                  selectedGroupDescription: nil) // The description of a group v1 is only available at the engine level, we don't fetch it here
        
    }
    
    enum ObvErrorForInitBaseOnPersistedContactGroup: Error {
        case ownedIdentityIsNil
    }
    
}


// MARK: - ObvUIGroupV2.OwnedIdentityAsGroupMemberViewModel from PersistedGroupV2 (and assoicated owned identity)

extension ObvUIGroupV2.OwnedIdentityAsGroupMemberViewModel {
    
    init(persistedGroup: PersistedGroupV2) throws {
        
        guard let ownedIdentity = persistedGroup.persistedOwnedIdentity else {
            // This happens when leaving a group
            throw ObvErrorForInitBasedOnPersistedGroupV2.persistedOwnedIdentityMissing
        }
        
        self.init(ownedCryptoId: ownedIdentity.ownedCryptoId,
                  isKeycloakManaged: ownedIdentity.isKeycloakManaged,
                  profilePictureInitial: ownedIdentity.circledInitialsConfiguration.initials?.text,
                  circleColors: .init(background: ownedIdentity.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                      foreground: ownedIdentity.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                  identityDetails: ownedIdentity.identityDetails,
                  permissions: persistedGroup.ownPermissions,
                  customDisplayName: ownedIdentity.customDisplayName,
                  customPhotoURL: nil)
    }
    
    enum ObvErrorForInitBasedOnPersistedGroupV2: Error {
        case persistedOwnedIdentityMissing
    }
    
}
