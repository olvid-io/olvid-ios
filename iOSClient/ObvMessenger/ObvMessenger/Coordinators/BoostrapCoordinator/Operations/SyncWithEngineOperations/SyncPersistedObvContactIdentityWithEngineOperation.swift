/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import OlvidUtils
import ObvEngine
import os.log
import CoreData
import ObvTypes
import ObvUICoreData


/// This operation updates the app database in order to ensures it is in sync with the engine database for contact identities.
///
/// It leverages the hints provided by the ``ComputeHintsAboutRequiredContactIdentitiesSyncWithEngineOperation``.
final class SyncPersistedObvContactIdentityWithEngineOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let syncType: SyncType
    private let obvEngine: ObvEngine
    
    enum SyncType {
        case addToApp(contactIdentifier: ObvContactIdentifier, isRestoringSyncSnapshotOrBackup: Bool)
        case deleteFromApp(contactIdentifier: ObvContactIdentifier)
        case syncWithEngine(contactIdentifier: ObvContactIdentifier, isRestoringSyncSnapshotOrBackup: Bool)
        var ownedCryptoId: ObvCryptoId {
            switch self {
            case .addToApp(let contactIdentifier, _),
                    .deleteFromApp(let contactIdentifier),
                    .syncWithEngine(let contactIdentifier, _):
                return contactIdentifier.ownedCryptoId
            }
        }
    }

    init(syncType: SyncType, obvEngine: ObvEngine) {
        self.syncType = syncType
        self.obvEngine = obvEngine
        super.init()
    }

    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let persistedOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: syncType.ownedCryptoId, within: obvContext.context) else {
                assertionFailure()
                return
            }

            switch syncType {
                
            case .addToApp(contactIdentifier: let contactIdentifier, isRestoringSyncSnapshotOrBackup: let isRestoringSyncSnapshotOrBackup):
            
                // Make sure the contact still exists within the engine
                guard let contactWithinEngine = try? obvEngine.getContactIdentity(with: contactIdentifier.contactCryptoId, ofOwnedIdentityWith: contactIdentifier.ownedCryptoId) else {
                    assertionFailure()
                    return
                }
                
                let persistedContact = try persistedOwnedIdentity.addOrUpdateContact(with: contactWithinEngine, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)
                
                // Get the contact capabilities within engine
                guard let contactCapabilitiesWithinEngine = try? obvEngine.getCapabilitiesOfContact(with: contactIdentifier) else {
                    // The contact capabilities may not be available yet (happens after a transfer for example)
                    return
                }
                
                _ = try persistedOwnedIdentity.setContactCapabilities(contactCryptoId: contactIdentifier.contactCryptoId, newCapabilities: contactCapabilitiesWithinEngine)
                
                requestSendingOneToOneDiscussionSharedConfiguration(with: persistedContact, within: obvContext)

            case .deleteFromApp(contactIdentifier: let contactIdentifier):
                
                // Make sure the contact still does not exist within the engine
                guard (try? obvEngine.getContactIdentity(with: contactIdentifier.contactCryptoId, ofOwnedIdentityWith: contactIdentifier.ownedCryptoId)) == nil else {
                    assertionFailure()
                    return
                }

                // Delete the contact (if it still exists) within the app
                try persistedOwnedIdentity.deleteContactAndLockOneToOneDiscussion(with: contactIdentifier.contactCryptoId)
                
            case .syncWithEngine(contactIdentifier: let contactIdentifier, isRestoringSyncSnapshotOrBackup: let isRestoringSyncSnapshotOrBackup):
                
                // Make sure the contact still exists within the engine
                guard let contactWithinEngine = try? obvEngine.getContactIdentity(with: contactIdentifier.contactCryptoId, ofOwnedIdentityWith: contactIdentifier.ownedCryptoId) else {
                    assertionFailure()
                    return
                }

                _ = try persistedOwnedIdentity.updateContact(with: contactWithinEngine, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)

                // Get the contact capabilities within engine
                guard let contactCapabilitiesWithinEngine = try? obvEngine.getCapabilitiesOfContact(with: contactIdentifier) else {
                    assertionFailure()
                    return
                }

                // Update the contact within the app
                _ = try persistedOwnedIdentity.setContactCapabilities(contactCryptoId: contactIdentifier.contactCryptoId, newCapabilities: contactCapabilitiesWithinEngine)

                if obvContext.context.hasChanges {
                    if let objectID = obvContext.context.registeredObjects
                        .compactMap({ $0 as? PersistedObvContactIdentity })
                        .first(where: { $0.ownedIdentity?.cryptoId == contactIdentifier.ownedCryptoId && $0.cryptoId == contactIdentifier.contactCryptoId }) {
                        try? obvContext.addContextDidSaveCompletionHandler { error in
                            guard error == nil else { return }
                            ObvStack.shared.viewContext.perform {
                                if let objectToRefresh = ObvStack.shared.viewContext.registeredObjects.first(where: { $0.objectID == objectID }) {
                                    ObvStack.shared.viewContext.refresh(objectToRefresh, mergeChanges: true)
                                }
                            }
                        }
                    }
                }
                
            }
            
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }

    
    // When creating a new contact, we create/unlock a one2one discussion. In that case, we want to (re)send the discussion shared settings to our contact.
    // This allows to make sure those settings are in sync.
    private func requestSendingOneToOneDiscussionSharedConfiguration(with contact: PersistedObvContactIdentity, within obvContext: ObvContext) {
        do {
            // We had to create a contact, meaning we had to create/unlock a one2one discussion. In that case, we want to (re)send the discussion shared settings to our contact.
            // This allows to make sure those settings are in sync.
            let contactIdentifier = try contact.contactIdentifier
            guard let discussionId = try contact.oneToOneDiscussion?.identifier else { return }
            try obvContext.addContextDidSaveCompletionHandler { error in
                guard error == nil else { return }
                ObvMessengerInternalNotification.aDiscussionSharedConfigurationIsNeededByContact(
                    contactIdentifier: contactIdentifier,
                    discussionId: discussionId)
                .postOnDispatchQueue()
            }
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

}
