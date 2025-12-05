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

@MainActor
final class SingleGroupMemberViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }

    private var singleGroupMemberViewModelStreamManagerForGroupEditionForStreamUUID = [UUID: SingleGroupMemberViewModelStreamManagerForGroupEdition]()
    private var singleGroupMemberViewModelStreamManagerForGroupCreationForStreamUUID = [UUID: SingleGroupMemberViewModelStreamManagerForGroupCreation]()
    private var singleGroupMemberViewModelStreamManagerFromPersistedContactAndGroupV1ForStreamUUID = [UUID: SingleGroupMemberViewModelStreamManagerFromPersistedContactAndGroupV1]()
    private var singleGroupMemberViewModelStreamManagerFromPendingGroupMemberForStreamUUID = [UUID: SingleGroupMemberViewModelStreamManagerFromPendingGroupMember]()

    enum ObvError: Error {
        case unexpectedIdentifier
    }
    
}


extension SingleGroupMemberViewAppDataSource: SingleGroupMemberViewDataSource {
    
    func getAsyncSequenceOfSingleGroupMemberViewModels(_ view: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView, withIdentifier identifier: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model.Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model>) {
        switch identifier {
        case .contactIdentifierForExistingGroupForPreviews, .contactIdentifierForCreatingGroupForPreviews:
            assertionFailure("This identifier kind should only be used in previews")
            throw ObvError.unexpectedIdentifier
        case .objectIDOfPersistedGroupV2Member(_, objectID: let objectID):
            let objectID = TypeSafeManagedObjectID<PersistedGroupV2Member>(objectID: objectID)
            let streamManager = try SingleGroupMemberViewModelStreamManagerForGroupEdition(objectID: objectID, context: backgroundContext, viewContext: viewContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.singleGroupMemberViewModelStreamManagerForGroupEditionForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        case .objectIDOfPersistedContact(objectID: let objectID, usageContext: let usageContext):
            let objectID = TypeSafeManagedObjectID<PersistedObvContactIdentity>(objectID: objectID)
            switch usageContext {
            case .groupCreation:
                let streamManager = SingleGroupMemberViewModelStreamManagerForGroupCreation(objectID: objectID, context: backgroundContext)
                let (streamUUID, stream) = try await streamManager.startStream()
                self.singleGroupMemberViewModelStreamManagerForGroupCreationForStreamUUID[streamUUID] = streamManager
                return (streamUUID, stream)
            case .groupV1Display(groupV1Identifier: let groupV1Identifier):
                let streamManager = SingleGroupMemberViewModelStreamManagerFromPersistedContactAndGroupV1(objectID: objectID, groupV1Identifier: groupV1Identifier, context: backgroundContext)
                let (streamUUID, stream) = try await streamManager.startStream()
                self.singleGroupMemberViewModelStreamManagerFromPersistedContactAndGroupV1ForStreamUUID[streamUUID] = streamManager
                return (streamUUID, stream)
            }
        case .objectIDOfPersistedPendingGroupMember(objectID: let objectID):
            let objectID = TypeSafeManagedObjectID<PersistedPendingGroupMember>(objectID: objectID)
            let streamManager = SingleGroupMemberViewModelStreamManagerFromPendingGroupMember(objectID: objectID, context: backgroundContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.singleGroupMemberViewModelStreamManagerFromPendingGroupMemberForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        }
    }
    
    func finishAsyncSequenceOfSingleGroupMemberViewModels(_ view: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView, withIdentifier identifier: ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model.Identifier, streamUUID: UUID) {
        if let streamManager = singleGroupMemberViewModelStreamManagerForGroupCreationForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
        if let streamManager = singleGroupMemberViewModelStreamManagerForGroupEditionForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
        if let streamManager = singleGroupMemberViewModelStreamManagerFromPersistedContactAndGroupV1ForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
        if let streamManager = singleGroupMemberViewModelStreamManagerFromPendingGroupMemberForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
    }

}


extension SingleGroupMemberViewAppDataSource {
    
    private final class SingleGroupMemberViewModelStreamManagerFromPendingGroupMember: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model, PersistedPendingGroupMember>, @unchecked Sendable {
        
        init(objectID: TypeSafeManagedObjectID<PersistedPendingGroupMember>, context: NSManagedObjectContext) {
            let frc = PersistedPendingGroupMember.getFetchedResultsController(objectID: objectID, within: context)
            super.init(frc: frc)
        }
        
        override func createModel(fetchedObjects: [PersistedPendingGroupMember]) throws -> SingleGroupMemberView.Model {
            guard let pendingMember = fetchedObjects.first else {
                throw ObvError.pendingMemberNotFound
            }
            let model = try ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model(pendingGroupMember: pendingMember)
            return model
        }
        
        enum ObvError: Error {
            case pendingMemberNotFound
        }
        
    }
    
}


extension SingleGroupMemberViewAppDataSource {
    
    private final class SingleGroupMemberViewModelStreamManagerFromPersistedContactAndGroupV1: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model, PersistedObvContactIdentity, PersistedContactGroup>, @unchecked Sendable {
        
        init(objectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, groupV1Identifier: ObvGroupV1Identifier, context: NSManagedObjectContext) {
            let frc1 = PersistedObvContactIdentity.getFetchedResultsController(objectID: objectID, within: context)
            let frc2 = PersistedContactGroup.getFetchedResultsController(groupV1Identifier: groupV1Identifier, within: context)
            super.init(frc1: frc1, frc2: frc2)
        }
        
        override func createModel(fetchedObjects1: [PersistedObvContactIdentity], fetchedObjects2: [PersistedContactGroup]) throws -> SingleGroupMemberView.Model {
            guard let contact = fetchedObjects1.first else { throw ObvError.contactNotFound }
            guard let groupV1 = fetchedObjects2.first else { throw ObvError.groupNotFound }
            let model = try ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model(persistedContact: contact, usageContext: .groupV1Display(groupV1: groupV1))
            return model
        }
        
        enum ObvError: Error {
            case contactNotFound
            case groupNotFound
        }

    }
    
}


// MARK: - Stream Manager for SingleGroupMemberViewModel during group creation (where a contact is identified by their PersistedObvContactIdentity objectID)

extension SingleGroupMemberViewAppDataSource {
    
    private final class SingleGroupMemberViewModelStreamManagerForGroupCreation: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model, PersistedObvContactIdentity>, @unchecked Sendable {
        
        init(objectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, context: NSManagedObjectContext) {
            let frc = PersistedObvContactIdentity.getFetchedResultsController(objectID: objectID, within: context)
            super.init(frc: frc)
        }
        
        override func createModel(fetchedObjects: [PersistedObvContactIdentity]) throws -> SingleGroupMemberView.Model {
            guard let persistedContact = fetchedObjects.first else {
                assertionFailure()
                throw ObvError.contactNoFound
            }
            let model = try ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model(persistedContact: persistedContact, usageContext: .groupCreation)
            return model
        }
        
        enum ObvError: Error {
            case contactNoFound
        }
        
    }
    
}

// MARK: - Stream Manager for SingleGroupMemberViewModel during group edition (where a contact is identified by their PersistedGroupV2Member objectID)
 
extension SingleGroupMemberViewAppDataSource {
    
    private final class SingleGroupMemberViewModelStreamManagerForGroupEdition: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model, PersistedGroupV2Member, PersistedInvitationOneToOneInvitationSent>, @unchecked Sendable {
        
        @MainActor
        init(objectID: TypeSafeManagedObjectID<PersistedGroupV2Member>, context: NSManagedObjectContext, viewContext: NSManagedObjectContext) throws {
            assert(Thread.isMainThread, "This must be called on the main thread as we use the main contact to build the PersistedInvitationOneToOneInvitationSent frc")
            
            // Instantiate the NSFetchedResultsController for the group member

            let frc1 = PersistedGroupV2Member.getFetchedResultsController(objectID: objectID, within: viewContext)

            // Instantiate the NSFetchedResultsController for one2one invitation

            guard let groupMember = try PersistedGroupV2Member.get(objectID: objectID.objectID, within: viewContext) else {
                throw ObvError.couldNotFindGroupMember
            }
            
            let ownedCryptoId = try groupMember.persistedGroup.ownCryptoId
            let remoteCryptoId = groupMember.cryptoId
            let frc2 = PersistedInvitationOneToOneInvitationSent.getFetchedResultsController(ownedCryptoId: ownedCryptoId, remoteCryptoId: remoteCryptoId, within: viewContext)

            super.init(frc1: frc1, frc2: frc2)
        }

        override func createModel(fetchedObjects1: [PersistedGroupV2Member], fetchedObjects2: [PersistedInvitationOneToOneInvitationSent]) throws -> SingleGroupMemberView.Model {
            
            guard let persistedMember = fetchedObjects1.first else {
                // Happens when removing a member
                throw ObvError.couldNotFindGroupMember
            }
            let oneToOneInvitationSentToMember = fetchedObjects2.first
            let model = try ObvUIGroupSharedBetweenV1AndV2.SingleGroupMemberView.Model(persistedMember: persistedMember, oneToOneInvitationSentToMember: oneToOneInvitationSentToMember)
            return model

        }
        
        enum ObvError: Error {
            case couldNotFindGroupMember
        }

    }
    
}


// MARK: - SingleGroupMemberViewModel from a PersistedGroupV2Member

extension SingleGroupMemberView.Model {
 
    init(persistedMember: PersistedGroupV2Member, oneToOneInvitationSentToMember: PersistedInvitationOneToOneInvitationSent?) throws {
                
        if let persistedContact = persistedMember.contact {
        
            let isOneToOneContact: SingleGroupMemberView.Model.IsOneToOneContact
            if persistedContact.isOneToOne {
                isOneToOneContact = .yes
            } else {
                let canSendOneToOneInvitation: Bool = oneToOneInvitationSentToMember == nil
                isOneToOneContact = .no(canSendOneToOneInvitation: canSendOneToOneInvitation)
            }

            self.init(contactIdentifier: try persistedContact.obvContactIdentifier,
                      isGroupAdmin: persistedMember.permissions.contains(.groupAdmin),
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
                      isGroupAdmin: persistedMember.permissions.contains(.groupAdmin),
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
    
    
    enum UsageContext {
        case groupCreation
        case groupV1Display(groupV1: PersistedContactGroup)
    }

    /// Called when creating a `SingleGroupMemberViewModel` during a group creation.
    init(persistedContact: PersistedObvContactIdentity, usageContext: UsageContext) throws {
        
        let isOneToOneContact: IsOneToOneContact
        if persistedContact.isOneToOne {
            isOneToOneContact = .yes
        } else {
            isOneToOneContact = .no(canSendOneToOneInvitation: false)
        }
        
        let isRevokedAsCompromised = !persistedContact.isActive

        switch usageContext {
            
        case .groupCreation:
            
            // Note that we do not specify any permission here. This is not required during a group creation.
            self.init(contactIdentifier: try persistedContact.obvContactIdentifier,
                      isGroupAdmin: false,
                      isKeycloakManaged: persistedContact.isCertifiedByOwnKeycloak,
                      profilePictureInitial: persistedContact.circledInitialsConfiguration.initials?.text,
                      circleColors: .init(background: persistedContact.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                          foreground: persistedContact.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                      identityDetails: try persistedContact.identityDetails,
                      isOneToOneContact: isOneToOneContact,
                      isRevokedAsCompromised: isRevokedAsCompromised,
                      isPending: false,
                      detailedProfileCanBeShown: false,
                      customDisplayName: persistedContact.customDisplayNameSanitized,
                      customPhotoURL: persistedContact.customPhotoURL)
            
        case .groupV1Display(groupV1: let groupV1):
            
            let isGroupAdmin: Bool
            if let joinedGroup = groupV1 as? PersistedContactGroupJoined {
                if joinedGroup.ownerIdentity == persistedContact.cryptoId.getIdentity() {
                    isGroupAdmin = true
                } else {
                    isGroupAdmin = false
                }
            } else {
                isGroupAdmin = false
            }
            
            let isPending: Bool = groupV1.pendingMembers.map({ $0.cryptoId }).contains(where: { $0 == persistedContact.cryptoId })
            
            self.init(contactIdentifier: try persistedContact.obvContactIdentifier,
                      isGroupAdmin: isGroupAdmin,
                      isKeycloakManaged: persistedContact.isCertifiedByOwnKeycloak,
                      profilePictureInitial: persistedContact.circledInitialsConfiguration.initials?.text,
                      circleColors: .init(background: persistedContact.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                          foreground: persistedContact.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                      identityDetails: try persistedContact.identityDetails,
                      isOneToOneContact: isOneToOneContact,
                      isRevokedAsCompromised: isRevokedAsCompromised,
                      isPending: isPending,
                      detailedProfileCanBeShown: true,
                      customDisplayName: persistedContact.customDisplayNameSanitized,
                      customPhotoURL: persistedContact.customPhotoURL)

        }
        
    }

    
    /// Called when displaying a group v1, but only if the pending member is not already a `PersistedObvContactIdentity`
    init(pendingGroupMember: PersistedPendingGroupMember) throws {
        
        let contactIdentifier = ObvContactIdentifier(contactCryptoId: pendingGroupMember.cryptoId, ownedCryptoId: try pendingGroupMember.ownedCryptoId)
        
        self.init(contactIdentifier: contactIdentifier,
                  isGroupAdmin: false, // A pending member cannot be an admin
                  isKeycloakManaged: false,
                  profilePictureInitial: pendingGroupMember.circledInitialsConfiguration.initials?.text,
                  circleColors: .init(background: pendingGroupMember.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                      foreground: pendingGroupMember.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                  identityDetails: pendingGroupMember.identityDetails,
                  isOneToOneContact: .no(canSendOneToOneInvitation: false),
                  isRevokedAsCompromised: false,
                  isPending: true,
                  detailedProfileCanBeShown: false,
                  customDisplayName: nil,
                  customPhotoURL: nil)

    }
    
    enum SingleGroupMemberViewModelInitError: Error {
        case inconsistentIdentifiers
    }
    
}
