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
import ObvInvitationFlow
import ObvUICoreData
import OlvidUtils
import ObvDesignSystem
import ObvTypes


final class ObvContactInvitationViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var contactInvitationViewModelStreamManagerForStreamUUID = [UUID: ContactInvitationViewModelStreamManager]()

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
    
}


// MARK: -

extension ObvContactInvitationViewAppDataSource: ObvContactInvitationViewDataSource {
    
    func getAsyncStreamOfContactInvitationViewModel(_ view: ObvInvitationFlow.ContactInvitationView, contactIdentifier: ObvInvitationFlow.ContactInvitationViewModel.ContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvInvitationFlow.ContactInvitationViewModel>) {
        let manager = try ContactInvitationViewModelStreamManager(contactIdentifier: contactIdentifier, context: backgroundContext)
        contactInvitationViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }

    
    func finishAsyncStreamOfContactInvitationViewModel(_ view: ObvInvitationFlow.ContactInvitationView, streamUUID: UUID) {
        guard let manager = contactInvitationViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
}


// MARK: - Internal managers

extension ObvContactInvitationViewAppDataSource {
    
    private final class ContactInvitationViewModelStreamManager: ObvDataSourceStreamManagerWithThreeFetchedResultsController<ContactInvitationViewModel, PersistedObvContactIdentity, PersistedInvitationOneToOneInvitationSent, PersistedOneToOneDiscussion>, @unchecked Sendable {

        let contactIdentifier: ContactInvitationViewModel.ContactIdentifier
            
        init(contactIdentifier: ContactInvitationViewModel.ContactIdentifier, context: NSManagedObjectContext) throws {
            self.contactIdentifier = contactIdentifier
            
            let frc1 = PersistedObvContactIdentity.getFetchedResultsControllerForContactIdentifier(persisted: contactIdentifier.contactIdentifier, whereOneToOneStatusIs: .any, within: context)
            let frc2 = PersistedInvitationOneToOneInvitationSent.getFetchedResultsController(ownedCryptoId: contactIdentifier.contactIdentifier.ownedCryptoId,
                                                                                             remoteCryptoId: contactIdentifier.contactIdentifier.contactCryptoId,
                                                                                             within: context)
            let frc3 = PersistedOneToOneDiscussion.getFetchedResultControllerOfPersistedDiscussionOneToOneContactID(contactId: contactIdentifier.contactIdentifier, within: context)
            super.init(frc1: frc1, frc2: frc2, frc3: frc3)
        }
        
        private var persistedContactIdentity: PersistedObvContactIdentity? {
            get throws {
                let frc = self.frc1
                
                guard let fetchedObjects = frc.fetchedObjects else {
                    assertionFailure()
                    throw ObvError.couldNotFetchObjects
                }
                
                assert(fetchedObjects.count <= 1)
                
                guard let persistedContactIdentity = fetchedObjects.first else {
                    return nil
                }
                
                return persistedContactIdentity
            }
        }
        
        private var persistedInvitationOneToOneInvitationSent: PersistedInvitationOneToOneInvitationSent? {
            get throws {
                let frc = self.frc2
                
                guard let fetchedObjects = frc.fetchedObjects else {
                    assertionFailure()
                    throw ObvError.couldNotFetchObjects
                }
                
                assert(fetchedObjects.count <= 1)
                
                guard let persistedInvitationOneToOneInvitationSent = fetchedObjects.first else {
                    return nil
                }
                
                return persistedInvitationOneToOneInvitationSent
            }
        }
        
        private var persistedDiscussion: PersistedOneToOneDiscussion? {
            get throws {
                let frc = self.frc3
                
                guard let fetchedObjects = frc.fetchedObjects else {
                    assertionFailure()
                    throw ObvError.couldNotFetchObjects
                }
                
                assert(fetchedObjects.count <= 1)
                
                guard let persistedOneToOneDiscussion = fetchedObjects.first else {
                    return nil
                }
                
                return persistedOneToOneDiscussion
            }
        }
        
        override func createModel(fetchedObjects1: [PersistedObvContactIdentity], fetchedObjects2: [PersistedInvitationOneToOneInvitationSent], fetchedObjects3: [PersistedOneToOneDiscussion]) throws -> ContactInvitationViewModel {
            
            let persistedContactIdentity = try persistedContactIdentity
            let sentInvitation = try persistedInvitationOneToOneInvitationSent
            let invitationAlreadySent = sentInvitation != nil
            
            if let persistedContactIdentity, let model = ContactInvitationViewModel(persistedContactIdentity: persistedContactIdentity, inviteHasBeenSent: invitationAlreadySent) {
                return model
            } else if let keycloakUserDetails = self.contactIdentifier.keycloakUserDetails, let model = ContactInvitationViewModel(keycloakUserDetails: keycloakUserDetails, inviteHasBeenSent: invitationAlreadySent) {
                return model
            }
            
            assertionFailure()
            throw ObvError.couldNotCreateModel
        }
        
        enum ObvError: Error {
            case couldNotFetchObjects
            case objectDoesNotExist
            case couldNotCreateModel
            case unexpectedIdentifierKind
        }
    }
}


extension ContactInvitationViewModel {
    
    init?(persistedContactIdentity: PersistedObvContactIdentity, inviteHasBeenSent: Bool) {
        let avatarModel = ObvAvatarViewModel(contact: persistedContactIdentity)
        let title: String
        let subtitle: String
        if persistedContactIdentity.isOneToOne {
            title = persistedContactIdentity.fullDisplayName
            subtitle = String(localized: "CONTACT_ALREADY_ADDED")
        } else if inviteHasBeenSent {
            title = String(localized: "CONTACT_INVITE_SENT")
            subtitle = String(localized: "CONTACT_\(persistedContactIdentity.customOrShortDisplayName)_WAIT_FOR_RESPONSE")
        } else {
            title = persistedContactIdentity.fullDisplayName
            subtitle = String(localized: "CONTACT_NOT_ADDED_YET")
        }
        
        let groupAvatarModel: [ObvAvatarViewModel] = []
        let groupTitle: String? = nil
        
        self.init(avatarModel: avatarModel,
                  isKeycloakManaged: persistedContactIdentity.isCertifiedByOwnKeycloak,
                  title: title,
                  subtitle: subtitle,
                  inviteHasBeenSent: inviteHasBeenSent,
                  groupsAvatarModel: groupAvatarModel,
                  groupTitle: groupTitle,
                  isOneToOne: persistedContactIdentity.isOneToOne)
    }

    
    init?(keycloakUserDetails: ObvKeycloakUserDetails, inviteHasBeenSent: Bool) {
        let firstName = keycloakUserDetails.firstName ?? ""
        let lastName = keycloakUserDetails.lastName ?? ""
        
        let firstNameThenLastName = [firstName, lastName].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        
        let character = keycloakUserDetails.circledText([firstName, lastName])
        
        let avatarModel = ObvAvatarViewModel(characterOrIcon: character != nil ? .character(character!) : .icon(.person),
                                             colors: .init(foreground: AppTheme.shared.colorScheme.secondaryLabel, background: AppTheme.shared.colorScheme.systemFill),
                                             photoURL: nil)
        
        self.init(avatarModel: avatarModel,
                  isKeycloakManaged: true,
                  title: firstNameThenLastName,
                  subtitle: String(localized: "CONTACT_NOT_ADDED_YET"),
                  inviteHasBeenSent: inviteHasBeenSent,
                  groupsAvatarModel: [],
                  groupTitle: nil,
                  isOneToOne: false)
    }

}


// MARK: - ObvKeycloakUserDetails from string components

extension ObvKeycloakUserDetails {
    
    func circledText(_ components: [String?]) -> Character? {
        let component = components
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
            .first
        if let char = component?.first {
            return char
        } else {
            return nil
        }
    }
    
}

