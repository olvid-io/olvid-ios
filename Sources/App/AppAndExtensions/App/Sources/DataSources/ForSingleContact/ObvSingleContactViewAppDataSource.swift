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
import ObvTypes
import ObvSingleContact
import OlvidUtils
import ObvUICoreData
import ObvDesignSystem
import ObvEngine

protocol ObvSingleContactViewAppDataSourceDelegate: AnyObject {
    func getAsyncStreamOfObvContactIdentity(_ dataSource: ObvSingleContactViewAppDataSource, for contactIdentifier: ObvContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvContactIdentity>)
    func finishAsyncSequenceOfObvContactIdentity(_ dataSource: ObvSingleContactViewAppDataSource, streamUUID: UUID)
    func freshContactIdentityReceivedWhileShowingSingleContactView(_ dataSource: ObvSingleContactViewAppDataSource, contactIdentity: ObvContactIdentity) async
}


final class ObvSingleContactViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    private weak var delegate: ObvSingleContactViewAppDataSourceDelegate?
    
    private var singleContactViewModelStreamManagerForStreamUUID: [UUID: SingleContactViewModelStreamManager] = [:]
    
    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext, delegate: ObvSingleContactViewAppDataSourceDelegate) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
        self.delegate = delegate
    }
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}


// MARK: - Implementing ObvSingleContactViewDataSource

extension ObvSingleContactViewAppDataSource: ObvSingleContactViewDataSource {
    
    func getAsyncSequenceOfSingleContactViewModel(_ view: ObvSingleContactView, contactIdentifier: ObvContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvSingleContactView.ModelOrDeleted>) {
        let manager = SingleContactViewModelStreamManager(contactIdentifier: contactIdentifier, context: backgroundContext, delegate: self)
        singleContactViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncSequenceOfSingleContactViewModel(_ view: ObvSingleContact.ObvSingleContactView, streamUUID: UUID) {
        guard let manager = singleContactViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
}


// MARK: - Implementing SingleContactViewModelStreamManagerDelegate

extension ObvSingleContactViewAppDataSource: ObvSingleContactViewAppDataSource.SingleContactViewModelStreamManagerDelegate {
    
    func getAsyncStreamOfObvContactIdentity(for contactIdentifier: ObvTypes.ObvContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvTypes.ObvContactIdentity>) {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.getAsyncStreamOfObvContactIdentity(self, for: contactIdentifier)
    }
    
    func finishAsyncSequenceOfObvContactIdentity(streamUUID: UUID) {
        assert(delegate != nil)
        delegate?.finishAsyncSequenceOfObvContactIdentity(self, streamUUID: streamUUID)
    }
    
    func freshContactIdentityReceivedWhileShowingSingleContactView(contactIdentity: ObvContactIdentity) async {
        assert(delegate != nil)
        await delegate?.freshContactIdentityReceivedWhileShowingSingleContactView(self, contactIdentity: contactIdentity)
    }
    
}


// MARK: - Internal managers

extension ObvSingleContactViewAppDataSource {
    
    protocol SingleContactViewModelStreamManagerDelegate: AnyObject {
        func getAsyncStreamOfObvContactIdentity(for contactIdentifier: ObvContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvContactIdentity>)
        func finishAsyncSequenceOfObvContactIdentity(streamUUID: UUID)
        func freshContactIdentityReceivedWhileShowingSingleContactView(contactIdentity: ObvContactIdentity) async
    }
    
    private final class SingleContactViewModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvSingleContact.ObvSingleContactView.ModelOrDeleted, PersistedObvContactIdentity, PersistedInvitationOneToOneInvitationSent>, @unchecked Sendable {
        
        private let contactIdentifier: ObvContactIdentifier
        private var contactIdentity: ObvContactIdentity?
        private var engineStreamUUID: UUID?
        private weak var delegate: SingleContactViewModelStreamManagerDelegate?
        
        init(contactIdentifier: ObvTypes.ObvContactIdentifier, context: NSManagedObjectContext, delegate: SingleContactViewModelStreamManagerDelegate?) {
            self.contactIdentifier = contactIdentifier
            self.delegate = delegate
            let frc1 = PersistedObvContactIdentity.getFetchedResultsControllerForContactIdentifier(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: context)
            let frc2 = PersistedInvitationOneToOneInvitationSent.getFetchedResultsController(ownedCryptoId: contactIdentifier.ownedCryptoId, remoteCryptoId: contactIdentifier.contactCryptoId, within: context)
            super.init(frc1: frc1, frc2: frc2)
        }
        
        
        override func startStream() async throws -> (streamUUID: UUID, stream: AsyncStream<ObvSingleContactView.ModelOrDeleted>) {
            let result = try await super.startStream()
            Task { await streamContactIdentityFromEngine() }
            return result
        }
        
        override func finishStream() {
            if let engineStreamUUID {
                delegate?.finishAsyncSequenceOfObvContactIdentity(streamUUID: engineStreamUUID)
            }
            super.finishStream()
        }
        
        private func streamContactIdentityFromEngine() async {
            do {
                assert(engineStreamUUID == nil)
                guard let delegate else {
                    assertionFailure()
                    throw ObvError.delegateIsNil
                }
                let (engineStreamUUID, streamFromEngine) = try await delegate.getAsyncStreamOfObvContactIdentity(for: contactIdentifier)
                self.engineStreamUUID = engineStreamUUID
                for await contactIdentity in streamFromEngine {
                    if self.contactIdentity != contactIdentity {
                        self.contactIdentity = contactIdentity
                        do {
                            try await getFetchedObjectsAndYieldModelIfNeeded()
                        } catch {
                            assertionFailure() // Continue with next value
                        }
                        // This call eventually ensures that the app database is in sync with the engine database
                        Task { await delegate.freshContactIdentityReceivedWhileShowingSingleContactView(contactIdentity: contactIdentity) }
                    }
                }
            } catch {
                assertionFailure()
            }
        }
        
        
        override func createModel(fetchedObjects1: [PersistedObvContactIdentity], fetchedObjects2: [PersistedInvitationOneToOneInvitationSent]) throws -> ObvSingleContactView.ModelOrDeleted {
            
            assert(fetchedObjects1.count <= 1)
            
            guard let contact = fetchedObjects1.first else {
                return .deleted
            }
            
            guard let fetchedObjects2 = frc2.fetchedObjects else {
                assertionFailure()
                throw ObvError.couldNotFetchObjects
            }
            
            assert(fetchedObjects2.count <= 1)
            
            let invitation = fetchedObjects2.first
            
            let model: ObvSingleContactView.Model = try .init(contact: contact,
                                                              contactIdentity: contactIdentity,
                                                              invitation: invitation)
            
            return .model(model)
            
        }
        
        enum ObvError: Error {
            case couldNotFetchObjects
            case delegateIsNil
        }
        
    }
    
}



// MARK: - ObvSingleContactView.Model from PersistedObvContactIdentity, PersistedInvitationOneToOneInvitationSent, and ObvContactIdentity (from the engine)

extension ObvSingleContact.ObvSingleContactView.Model {
    
    /// Both `publishedIdentityDetails` and `isRevokedAsCompromised` come from the engine.
    init(contact: PersistedObvContactIdentity, contactIdentity: ObvContactIdentity?, invitation: PersistedInvitationOneToOneInvitationSent?) throws {
        
        let contactIdentifier: ObvContactIdentifier = try contact.obvContactIdentifier
        let trustedIdentityDetails: ObvIdentityDetails = try contact.identityDetails
        
        if let contactIdentity {
            guard contact.cryptoId == contactIdentity.cryptoId else {
                assertionFailure()
                throw ObvSingleContactObvSingleContactViewModelError.inconsistentIdentity
            }
        }
        
        let customDetails: CustomDetails? = .init(contact: contact)
        
        let avatarModelFromPublishedDetails: ObvAvatarViewModel?
        if let contactIdentity, let publishedIdentityDetails = contactIdentity.publishedIdentityDetails {
            avatarModelFromPublishedDetails = .init(contactCryptoId: contactIdentity.cryptoId, publishedIdentityDetails: publishedIdentityDetails)
        } else {
            avatarModelFromPublishedDetails = nil
        }
        
        let contactDeletionType: ContactDeletionType
        do {
            if contact.supportsCapability(.oneToOneContacts) {
                if contact.isOneToOne {
                    contactDeletionType = .downgradeToNonOneToOne
                } else {
                    // If the contact is part of a common group (or pending in a group), we cannot delete them
                    if contact.contactGroups.isEmpty && contact.asGroupV2Member.isEmpty {
                        contactDeletionType = .fullDeletion
                    } else {
                        contactDeletionType = .fullDeletionImpossibleAsContactInCommonGroup
                    }
                }
            } else {
                // If the contact is part of a common group (or pending in a group), we cannot delete them
                if contact.contactGroups.isEmpty && contact.asGroupV2Member.isEmpty {
                    contactDeletionType = .legacyFullDeletion
                } else {
                    contactDeletionType = .fullDeletionImpossibleAsContactInCommonGroup
                }
            }
        }
        
        let oneToOneInvitationSent: Bool
        if invitation == nil {
            oneToOneInvitationSent = false
        } else {
            oneToOneInvitationSent = true
        }
        
        let showReblockView: Bool = contact.isActive && (contactIdentity?.isRevokedAsCompromised == true)
        
        let numberOfGroupsInCommon = contact.contactGroups.count + contact.asGroupV2Member.count
        
        self.init(contactIdentifier: contactIdentifier,
                  trustedIdentityDetails: trustedIdentityDetails,
                  publishedIdentityDetails: contactIdentity?.publishedIdentityDetails,
                  customDetails: customDetails,
                  personalNote: contact.note,
                  avatarModelFromTrustedDetails: .init(contact: contact),
                  avatarModelFromPublishedDetails: avatarModelFromPublishedDetails,
                  countOfContactDevices: contact.devices.count,
                  contactDeletionType: contactDeletionType,
                  atLeastOneDeviceAllowsThisContactToReceiveMessages: contact.atLeastOneDeviceAllowsThisContactToReceiveMessages,
                  showReblockView: showReblockView,
                  oneToOneInvitationSent: oneToOneInvitationSent,
                  numberOfGroupsInCommon: numberOfGroupsInCommon,
                  isActive: contact.isActive,
                  wasRecentlyOnline: contactIdentity?.wasRecentlyOnline ?? true,
                  isOneToOne: contact.isOneToOne)
        
    }
    
    enum ObvSingleContactObvSingleContactViewModelError: Error {
        case inconsistentIdentity
    }
    
}


// MARK: - ObvSingleContact.ObvSingleContactView.Model.CustomDetails from PersistedObvContactIdentity

extension ObvSingleContact.ObvSingleContactView.Model.CustomDetails {
    
    init?(contact: PersistedObvContactIdentity) {
        
        let nickname: String? = contact.customDisplayName
        let avatarModel: ObvAvatarViewModel?
        if let customPhotoURL = contact.customPhotoURL {
            let colors = ObvDesignSystem.AppTheme.shared.identityColors(for: contact.cryptoId, using: .hue)
            avatarModel = .init(characterOrIcon: .icon(.person),
                                colors: .init(foreground: colors.text, background: colors.background),
                                photoURL: customPhotoURL)
        } else {
            avatarModel = nil
        }

        if nickname == nil && avatarModel == nil {
            return nil
        } else {
            self.init(nickname: nickname,
                      avatarModel: avatarModel)
        }

    }
    
}

extension ObvDesignSystem.ObvAvatarViewModel {
    
    init(contactCryptoId: ObvCryptoId, publishedIdentityDetails: ObvIdentityDetails) {
        
        let character = publishedIdentityDetails.coreDetails.getFullDisplayName().first
        let characterOrIcon: CharacterOrIcon
        if let character {
            characterOrIcon = .character(character)
        } else {
            characterOrIcon = .icon(.person)
        }

        let colors = ObvDesignSystem.AppTheme.shared.identityColors(for: contactCryptoId, using: .hue)

        self.init(characterOrIcon: characterOrIcon,
                  colors: .init(foreground: colors.text, background: colors.background),
                  photoURL: publishedIdentityDetails.photoURL)
        
    }
    
}
