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
import OlvidUtils


final class DataSourceForObvContactIdentity {
    
    let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        context.automaticallyMergesChangesFromParent = true
        self.context = context
    }
    
    private var contactIdentityStreamManagerForStreamUUID = [UUID: ObvContactIdentityStreamManager]()

}


extension DataSourceForObvContactIdentity {
    
    func getAsyncStreamOfObvContactIdentity(for contactIdentifier: ObvContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvContactIdentity>) {
        let manager = ObvContactIdentityStreamManager(contactIdentifier: contactIdentifier, context: context)
        contactIdentityStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
 
    
    func finishAsyncStreamOfObvContactIdentity(streamUUID: UUID) {
        guard let manager = contactIdentityStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }

}


extension DataSourceForObvContactIdentity {
    
    private final class ObvContactIdentityStreamManager: ObvDataSourceStreamManagerWithThreeFetchedResultsController<ObvContactIdentity, ContactIdentity, ContactIdentityDetailsPublished, ContactIdentityDetailsTrusted>, @unchecked Sendable {
        
        private let contactIdentifier: ObvContactIdentifier
        private let context: NSManagedObjectContext
        
        init(contactIdentifier: ObvContactIdentifier, context: NSManagedObjectContext) {
            context.automaticallyMergesChangesFromParent = true
            self.context = context
            self.contactIdentifier = contactIdentifier
            let frc1 = ContactIdentity.getFetchedResultsController(contactIdentifier: contactIdentifier, within: context)
            let frc2 = ContactIdentityDetailsPublished.getFetchedResultsController(contactIdentifier: contactIdentifier, within: context)
            let frc3 = ContactIdentityDetailsTrusted.getFetchedResultsController(contactIdentifier: contactIdentifier, within: context)
            super.init(frc1: frc1, frc2: frc2, frc3: frc3)
        }
        
        override func createModel(fetchedObjects1: [ContactIdentity], fetchedObjects2: [ContactIdentityDetailsPublished], fetchedObjects3: [ContactIdentityDetailsTrusted]) throws -> ObvContactIdentity {
            assert(fetchedObjects1.count <= 1)
            assert(fetchedObjects2.count <= 2)
            guard let contact = fetchedObjects1.first else {
                // This happens when permanently deleting a contact
                throw ObvError.couldNotFetchContact
            }
            guard contact.ownedIdentityIdentity == contactIdentifier.ownedCryptoId.getIdentity() else {
                assertionFailure()
                throw ObvError.inconsistentIdentifier
            }
            guard contact.identity == contactIdentifier.contactCryptoId.getIdentity() else {
                assertionFailure()
                throw ObvError.inconsistentIdentifier
            }
            let model = try ObvContactIdentity(contactIdentity: contact)
            return model
        }
        
        enum ObvError: Error {
            case couldNotFetchContact
            case inconsistentIdentifier
            case trustedContactDetailsAreNil
        }
        
    }
    
}


// MARK: ObvIdentityDetails from ContactIdentityDetails

extension ObvIdentityDetails {
    
    init(contactDetails: ContactIdentityDetails) throws {
        let coreDetails = try ObvIdentityCoreDetails(contactDetails.serializedIdentityCoreDetails)
        self.init(coreDetails: coreDetails,
                  photoURL: try contactDetails.getPhotoURL())
    }
    
}


// MARK: - ObvContactIdentity from ContactIdentity

extension ObvContactIdentity {
    
    init(contactIdentity contact: ContactIdentity) throws {
        
        guard let trustedContactDetails = contact.trustedIdentityDetails else {
            assertionFailure()
            throw ObvContactIdentityFromContactIdentityError.trustedContactDetailsAreNil
        }
        let trustedIdentityDetails = try ObvIdentityDetails(contactDetails: trustedContactDetails)
        let publishedIdentityDetails: ObvIdentityDetails?
        if let publishedContactDetails = contact.publishedIdentityDetails {
            publishedIdentityDetails = try ObvIdentityDetails(contactDetails: publishedContactDetails)
        } else {
            publishedIdentityDetails = nil
        }
        let isOneToOne: Bool
        switch contact.oneToOneStatus {
        case .notOneToOne, .toBeDefined:
            isOneToOne = false
        case .oneToOne:
            isOneToOne = true
        }
        guard let contactCryptoIdentity = contact.cryptoIdentity else {
            assertionFailure()
            throw ObvContactIdentityFromContactIdentityError.contactCryptoIdIsNil
        }
        let ownedCryptoId = try ObvCryptoId(identity: contact.ownedIdentityIdentity)
        self.init(cryptoIdentity: contactCryptoIdentity,
                  trustedIdentityDetails: trustedIdentityDetails,
                  publishedIdentityDetails: publishedIdentityDetails,
                  ownedCryptoId: ownedCryptoId,
                  isCertifiedByOwnKeycloak: contact.isCertifiedByOwnKeycloak,
                  isActive: contact.isNotRevokedAsCompromisedOrIsForcefullyTrustedByUser,
                  isRevokedAsCompromised: contact.isRevokedAsCompromised,
                  isOneToOne: isOneToOne,
                  wasRecentlyOnline: contact.wasContactRecentlyOnline)
        
    }
    
    enum ObvContactIdentityFromContactIdentityError: Error {
        case trustedContactDetailsAreNil
        case contactCryptoIdIsNil
    }
    
}
