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
import ObvUIGroupSharedBetweenV1AndV2
import ObvTypes
import ObvAppTypes
import ObvUICoreData
import ObvDesignSystem
import OlvidUtils
import ObvCircleAndTitlesView


@MainActor
final class OnetoOneInvitableGroupMembersViewCellAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var onetoOneInvitableGroupMembersViewCellModelBasedOnPersistedGroupV2MemberStreamManagerForStreamUUID = [UUID: OnetoOneInvitableGroupMembersViewCellModelBasedOnPersistedGroupV2MemberStreamManager]()
    private var onetoOneInvitableGroupMembersViewCellModelBasedOnPersistedContactStreamManagerForStreamUUID = [UUID: OnetoOneInvitableGroupMembersViewCellModelBasedOnPersistedContactStreamManager]()
    private var onetoOneInvitableGroupMembersViewCellModelBasedOnPersistedPendingGroupMemberStreamManagerForStreamUUID = [UUID: OnetoOneInvitableGroupMembersViewCellModelBasedOnPersistedPendingGroupMemberStreamManager]()
    

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }

    enum ObvError: Error {
        case unexpectedIdentifier
    }
    
}


extension OnetoOneInvitableGroupMembersViewCellAppDataSource: OnetoOneInvitableGroupMembersViewCellDataSource {
    
    /// Called when displaying the list of group members split in 3 sections (set also `getAsyncSequenceOfOnetoOneInvitableGroupMembersViewModel`).
    /// This is called for each cell, to obtain a stream of updates correponding to a particular group member.
    func getAsyncSequenceOfOnetoOneInvitableGroupMembersViewCellModels(_ view: ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersViewCell, identifier: ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersViewModel.Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersViewCellModel>) {
        switch identifier {
        case .contactIdentifier:
            assertionFailure("This identifier kind should only be used in previews")
            throw ObvError.unexpectedIdentifier
        case .objectIDOfPersistedGroupV2Member(objectID: let objectID):
            let objectID = TypeSafeManagedObjectID<PersistedGroupV2Member>(objectID: objectID)
            let streamManager = try OnetoOneInvitableGroupMembersViewCellModelBasedOnPersistedGroupV2MemberStreamManager(objectID: objectID, context: backgroundContext, viewContext: viewContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.onetoOneInvitableGroupMembersViewCellModelBasedOnPersistedGroupV2MemberStreamManagerForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        case .objectIDOfPersistedObvContactIdentity(objectID: let objectID):
            let objectID = TypeSafeManagedObjectID<PersistedObvContactIdentity>(objectID: objectID)
            let streamManager = try OnetoOneInvitableGroupMembersViewCellModelBasedOnPersistedContactStreamManager(objectID: objectID, context: backgroundContext, viewContext: viewContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.onetoOneInvitableGroupMembersViewCellModelBasedOnPersistedContactStreamManagerForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        case .objectIDOfPersistedPendingGroupMember(objectID: let objectID):
            let objectID = TypeSafeManagedObjectID<PersistedPendingGroupMember>(objectID: objectID)
            let streamManager = try OnetoOneInvitableGroupMembersViewCellModelBasedOnPersistedPendingGroupMemberStreamManager(objectID: objectID, context: backgroundContext, viewContext: viewContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.onetoOneInvitableGroupMembersViewCellModelBasedOnPersistedPendingGroupMemberStreamManagerForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        }
    }
    
    func finishAsyncSequenceOfOnetoOneInvitableGroupMembersViewCellModels(_ view: ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersViewCell, identifier: ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersViewModel.Identifier, streamUUID: UUID) {
        if let streamManager = onetoOneInvitableGroupMembersViewCellModelBasedOnPersistedGroupV2MemberStreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
        if let streamManager = onetoOneInvitableGroupMembersViewCellModelBasedOnPersistedContactStreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
        if let streamManager = onetoOneInvitableGroupMembersViewCellModelBasedOnPersistedPendingGroupMemberStreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
    }
    
}


// MARK: - Stream Manager for OnetoOneInvitableGroupMembersViewCellModel

extension OnetoOneInvitableGroupMembersViewCellAppDataSource {
    
    /// Stream manager used to feed a cell displaying a group member in the view showing all the group members that can be invited to a one2one discussion.
    /// A group member can be identified by one of three possible identifiers: an ObjectID to a persisted contact, ObjectID to a group member, or ObjectID of a PersistedPendingGroupMember..
    ///
    /// This manager is used when the identifier is an `ObjectID` of a `PersistedPendingGroupMember`.
    ///
    /// We also need to observe persisted one to one invitation sent, as we need to know whether a non-one2one contact can be invited or not (we disallow a second
    /// invitation to be sent).
    private final class OnetoOneInvitableGroupMembersViewCellModelBasedOnPersistedPendingGroupMemberStreamManager: ObvDataSourceStreamManagerWithThreeFetchedResultsController<ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersViewCellModel, PersistedPendingGroupMember, PersistedInvitationOneToOneInvitationSent, PersistedObvContactIdentity>, @unchecked Sendable {
        
        @MainActor
        init(objectID: TypeSafeManagedObjectID<PersistedPendingGroupMember>, context: NSManagedObjectContext, viewContext: NSManagedObjectContext) throws {
            assert(Thread.isMainThread, "We need to fetch the group member on the view context to instantiate the second frc")
            let frc1 = PersistedPendingGroupMember.getFetchedResultsController(objectID: objectID, within: context)
            guard let pendingMember = try PersistedPendingGroupMember.get(objectID: objectID, within: viewContext) else {
                assertionFailure()
                throw ObvError.couldNotFindPendingGroupMember
            }
            let frcPersistedInvitationOneToOneInvitationSent = PersistedInvitationOneToOneInvitationSent.getFetchedResultsController(
                ownedCryptoId: try pendingMember.ownedCryptoId,
                remoteCryptoId: pendingMember.cryptoId,
                within: context)
            let contactIdentifier = ObvContactIdentifier(contactCryptoId: pendingMember.cryptoId, ownedCryptoId: try pendingMember.ownedCryptoId)
            let frc3 = PersistedObvContactIdentity.getFetchedResultsControllerForContactIdentifier(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: context)
            super.init(frc1: frc1, frc2: frcPersistedInvitationOneToOneInvitationSent, frc3: frc3)
        }

        override func createModel(fetchedObjects1: [PersistedPendingGroupMember], fetchedObjects2: [PersistedInvitationOneToOneInvitationSent], fetchedObjects3: [PersistedObvContactIdentity]) throws -> OnetoOneInvitableGroupMembersViewCellModel {

            assert(fetchedObjects1.count <= 1)
            assert(fetchedObjects2.count <= 1)
            assert(fetchedObjects3.count <= 1)
            guard let pendingMember = fetchedObjects1.first else { throw ObvError.couldNotFindPendingGroupMember }
            
            let contactIdentifier = ObvContactIdentifier(contactCryptoId: pendingMember.cryptoId, ownedCryptoId: try pendingMember.ownedCryptoId)

            let kind: OnetoOneInvitableGroupMembersViewCellModel.Kind
            let detailedProfileCanBeShown: Bool
            let isKeycloakManaged: Bool
            let circleColors: InitialCircleView.Model.Colors
            let identityDetails: ObvIdentityDetails
            let profilePictureInitial: String?
            let customDisplayName: String?
            let customPhotoURL: URL?
            if let persistedContact = fetchedObjects3.first {
                if persistedContact.isOneToOne {
                    kind = .oneToOneContactsAmongMembers
                } else {
                    let sentInvitation = fetchedObjects2.first
                    let invitationSentAlready = sentInvitation != nil
                    kind = .invitableGroupMembers(invitationSentAlready: invitationSentAlready)
                }
                detailedProfileCanBeShown = true
                isKeycloakManaged = persistedContact.isCertifiedByOwnKeycloak
                circleColors = .init(background: persistedContact.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                     foreground: persistedContact.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared))
                identityDetails = try persistedContact.identityDetails
                profilePictureInitial = persistedContact.circledInitialsConfiguration.initials?.text
                customDisplayName = persistedContact.customDisplayNameSanitized
                customPhotoURL = persistedContact.customPhotoURL
            } else {
                kind = .notInvitableGroupMembers
                detailedProfileCanBeShown = false
                isKeycloakManaged = false
                circleColors = .init(background: pendingMember.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                     foreground: pendingMember.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared))
                identityDetails = pendingMember.identityDetails
                profilePictureInitial = pendingMember.circledInitialsConfiguration.initials?.text
                customDisplayName = nil
                customPhotoURL = nil
            }
                        
            let model = ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersViewCellModel(
                contactIdentifier: contactIdentifier,
                isKeycloakManaged: isKeycloakManaged,
                profilePictureInitial: profilePictureInitial,
                circleColors: circleColors,
                identityDetails: identityDetails,
                kind: kind,
                isRevokedAsCompromised: false,
                detailedProfileCanBeShown: detailedProfileCanBeShown,
                customDisplayName: customDisplayName,
                customPhotoURL: customPhotoURL)
            
            return model

        }
        
        enum ObvError: Error {
            case couldNotFindPendingGroupMember
        }
        
    }
    
}

extension OnetoOneInvitableGroupMembersViewCellAppDataSource {
    
    /// Stream manager used to feed a cell displaying a group member in the view showing all the group members that can be invited to a one2one discussion.
    /// A group member can be identified by one of three possible identifiers: an ObjectID to a persisted contact, ObjectID to a group member, or ObjectID of a PersistedPendingGroupMember..
    ///
    /// This manager is used when the identifier is an `ObjectID` of a `PersistedGroupV2Member`.
    ///
    /// We also need to observe persisted one to one invitation sent, as we need to know whether a non-one2one contact can be invited or not (we disallow a second
    /// invitation to be sent).
    private final class OnetoOneInvitableGroupMembersViewCellModelBasedOnPersistedGroupV2MemberStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersViewCellModel, PersistedGroupV2Member, PersistedInvitationOneToOneInvitationSent>, @unchecked Sendable {
        
        @MainActor
        init(objectID: TypeSafeManagedObjectID<PersistedGroupV2Member>, context: NSManagedObjectContext, viewContext: NSManagedObjectContext) throws {
            assert(Thread.isMainThread, "We need to fetch the group member on the view context to instantiate the second frc")
            let frc1 = PersistedGroupV2Member.getFetchedResultsController(objectID: .init(objectID: objectID.objectID), within: context)
            guard let groupMember = try PersistedGroupV2Member.get(objectID: objectID.objectID, within: viewContext) else {
                assertionFailure()
                throw ObvError.couldNotFindGroupMember
            }
            let contactIdentifier = try groupMember.userIdentifier
            let frcPersistedInvitationOneToOneInvitationSent = PersistedInvitationOneToOneInvitationSent.getFetchedResultsController(
                ownedCryptoId: contactIdentifier.ownedCryptoId,
                remoteCryptoId: contactIdentifier.contactCryptoId,
                within: context)
            super.init(frc1: frc1, frc2: frcPersistedInvitationOneToOneInvitationSent)
        }
        
        override func createModel(fetchedObjects1: [PersistedGroupV2Member], fetchedObjects2: [PersistedInvitationOneToOneInvitationSent]) throws -> OnetoOneInvitableGroupMembersViewCellModel {

            let fetchedObjects = fetchedObjects1
            assert(fetchedObjects.count == 1 || fetchedObjects.count == 0)
            guard let persistedMember = fetchedObjects.first else { throw ObvError.couldNotFindGroupMember }
            
            let contactIdentifier = ObvContactIdentifier(contactCryptoId: persistedMember.cryptoId, ownedCryptoId: try persistedMember.persistedGroup.ownCryptoId)
            
            let kind: OnetoOneInvitableGroupMembersViewCellModel.Kind
            if let persistedContact = persistedMember.contact {
                if persistedContact.isOneToOne {
                    kind = .oneToOneContactsAmongMembers
                } else {
                    let sentInvitation = fetchedObjects2.first
                    let invitationSentAlready = sentInvitation != nil
                    kind = .invitableGroupMembers(invitationSentAlready: invitationSentAlready)
                }
            } else {
                kind = .notInvitableGroupMembers
            }

            let detailedProfileCanBeShown: Bool = (persistedMember.contact != nil)
            
            let model = ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersViewCellModel(
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

        }
        
        enum ObvError: Error {
            case couldNotFindGroupMember
        }
        
    }
    
    
    /// Stream manager used to feed a cell displaying a group member in the view showing all the group members that can be invited to a one2one discussion.
    /// A group member can be identified by one of three possible identifiers: an ObjectID to a persisted contact, ObjectID to a group member, or ObjectID of a PersistedPendingGroupMember..
    ///
    /// This manager is used when the identifier is an `ObjectID` of a `PersistedObvContactIdentity`.
    ///
    /// We also need to observe persisted one to one invitation sent, as we need to know whether a non-one2one contact can be invited or not (we disallow a second
    /// invitation to be sent).
    private final class OnetoOneInvitableGroupMembersViewCellModelBasedOnPersistedContactStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersViewCellModel, PersistedObvContactIdentity, PersistedInvitationOneToOneInvitationSent>, @unchecked Sendable {

        @MainActor
        init(objectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, context: NSManagedObjectContext, viewContext: NSManagedObjectContext) throws {
            assert(Thread.isMainThread, "We need to fetch the contact on the view context to instantiate the second frc")
            let frc1 = PersistedObvContactIdentity.getFetchedResultsController(objectID: .init(objectID: objectID.objectID), within: context)
            guard let contact = try PersistedObvContactIdentity.get(objectID: objectID, within: viewContext) else {
                assertionFailure()
                throw ObvError.couldNotFindContact
            }
            let contactIdentifier = try contact.obvContactIdentifier
            let frcPersistedInvitationOneToOneInvitationSent = PersistedInvitationOneToOneInvitationSent.getFetchedResultsController(
                ownedCryptoId: contactIdentifier.ownedCryptoId,
                remoteCryptoId: contactIdentifier.contactCryptoId,
                within: context)
            super.init(frc1: frc1, frc2: frcPersistedInvitationOneToOneInvitationSent)
        }
        
        override func createModel(fetchedObjects1: [PersistedObvContactIdentity], fetchedObjects2: [PersistedInvitationOneToOneInvitationSent]) throws -> OnetoOneInvitableGroupMembersViewCellModel {
            
            let fetchedObjects = fetchedObjects1
            assert(fetchedObjects.count <= 1)
            guard let persistedContact = fetchedObjects.first else {
                // Happens when a contact is removed from a group
                throw ObvError.couldNotFindContact
            }

            let kind: OnetoOneInvitableGroupMembersViewCellModel.Kind
            if persistedContact.isOneToOne {
                kind = .oneToOneContactsAmongMembers
            } else {
                let sentInvitation = fetchedObjects2.first
                let invitationSentAlready = sentInvitation != nil
                kind = .invitableGroupMembers(invitationSentAlready: invitationSentAlready)
            }
            
            let model = ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersViewCellModel(
                contactIdentifier: try persistedContact.obvContactIdentifier,
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
        
        enum ObvError: Error {
            case couldNotFindContact
        }
        
    }
        
}
