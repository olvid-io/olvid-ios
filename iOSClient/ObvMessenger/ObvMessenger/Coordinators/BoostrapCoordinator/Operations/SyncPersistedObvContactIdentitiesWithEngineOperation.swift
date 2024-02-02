/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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


final class SyncPersistedObvContactIdentitiesWithEngineOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let obvEngine: ObvEngine
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: SyncPersistedObvContactIdentitiesWithEngineOperation.self))

    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        os_log("Syncing Persisted Contacts with Engine Contacts", log: log, type: .info)
        
        let ownedIdentities: [PersistedObvOwnedIdentity]
        do {
            ownedIdentities = try PersistedObvOwnedIdentity.getAll(within: obvContext.context)
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
        ownedIdentities.forEach { ownedIdentity in
            
            let obvContactIdentities: Set<ObvContactIdentity>
            do {
                obvContactIdentities = try obvEngine.getContactsOfOwnedIdentity(with: ownedIdentity.cryptoId)
            } catch {
                os_log("Could not get contacts of owned identity from engine", log: log, type: .fault)
                assertionFailure()
                return
            }
            
            // Split the set of obvContactIdentities into missing and existing contacts
            var missingContacts: Set<ObvContactIdentity> // Contacts that exist within the engine, but not within the app
            var existingContacts: Set<ObvContactIdentity> // Contacts that exist both within the engine and within the app
            do {
                missingContacts = try obvContactIdentities.filter({
                    return (try PersistedObvContactIdentity.get(persisted: $0.contactIdentifier, whereOneToOneStatusIs: .any, within: obvContext.context)) == nil
                })
                existingContacts = obvContactIdentities.subtracting(missingContacts)
            } catch let error {
                os_log("Could not construct a list of missing obv contacts: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }
            
            os_log("Number of contacts existing within the engine but missing within the app: %{public}d", log: log, type: .info, missingContacts.count)
            os_log("Number of contacts existing within the engine and present within the app: %{public}d", log: log, type: .info, existingContacts.count)
            
            // Create a persisted contact for each missing obv contact.
            // Each time a contact is created within the app, add this contact to the list of existing contacts within the app
            
            while let obvContact = missingContacts.popFirst() {
                do {
                    let newContact = try PersistedObvContactIdentity.createPersistedObvContactIdentity(contactIdentity: obvContact, within: obvContext.context)
                    requestSendingOneToOneDiscussionSharedConfiguration(with: newContact, within: obvContext)
                } catch {
                    os_log("Could not create a missing persisted contact: %{public}@", log: log, type: .fault, error.localizedDescription)
                    continue
                }
                // If we reach this line, the insertion of the missing contact was successfull, we add it to the list of existing contacts
                existingContacts.insert(obvContact)
            }
            
            // Remove any persisted contact that does not exist within the engine
            
            do {
                let persistedContacts = try PersistedObvContactIdentity.getAllContactOfOwnedIdentity(with: ownedIdentity.cryptoId, whereOneToOneStatusIs: .any, within: obvContext.context)
                let cryptoIdsToKeep = existingContacts.map { $0.cryptoId }
                let persistedContactsToDelete = persistedContacts.filter { !cryptoIdsToKeep.contains($0.cryptoId) }
                os_log("Number of contacts existing within the app that must be deleted: %{public}d", log: log, type: .info, persistedContactsToDelete.count)
                for contact in persistedContactsToDelete {
                    do {
                        try contact.deleteAndLockOneToOneDiscussion()
                    } catch {
                        os_log("Could not delete a contact during bootstrap: %{public}@", log: log, type: .fault, error.localizedDescription)
                    }
                }
            } catch let error {
                os_log("Could not get a set of all contacts of the owned identity: %{public}@", log: log, type: .error, error.localizedDescription)
                assertionFailure()
                // We continue anyway
            }
            
            // For each existing contact within the app, make sure the information is in sync with the information within the engine
            
            var objectIDsOfContactsToRefreshInViewContext = Set<NSManagedObjectID>()
            
            do {
                let persistedContacts = try PersistedObvContactIdentity.getAllContactOfOwnedIdentity(with: ownedIdentity.cryptoId, whereOneToOneStatusIs: .any, within: obvContext.context)
                for contact in persistedContacts {
                    guard let obvContact = existingContacts.first(where: { contact.cryptoId == $0.cryptoId }) else {
                        assertionFailure()
                        continue
                    }
                    try contact.updateContact(with: obvContact)
                    if !contact.changedValues().isEmpty {
                        objectIDsOfContactsToRefreshInViewContext.insert(contact.typedObjectID.objectID)
                    }
                }
            } catch {
                os_log("Could sync the existing persisted contacts with the information received from the engine: %{public}@", log: log, type: .error, error.localizedDescription)
                assertionFailure()
                // We continue anyway
            }
            
            // For each existing contact within the app, make sure the capabilities are in sync with the information within the engine
            
            do {
                let persistedContacts = try PersistedObvContactIdentity.getAllContactOfOwnedIdentity(with: ownedIdentity.cryptoId, whereOneToOneStatusIs: .any, within: obvContext.context)
                let contactCapabilities = try obvEngine.getCapabilitiesOfAllContactsOfOwnedIdentity(ownedIdentity.cryptoId)
                for contact in persistedContacts {
                    guard let capabilities = contactCapabilities[contact.cryptoId] else {
                        // The contact capabilities are not known yet
                        continue
                    }
                    contact.setContactCapabilities(to: capabilities)
                    if !contact.changedValues().isEmpty {
                        objectIDsOfContactsToRefreshInViewContext.insert(contact.typedObjectID.objectID)
                    }
                }
            } catch {
                os_log("Could sync the existing persisted contacts with the information received from the engine: %{public}@", log: log, type: .error, error.localizedDescription)
                assertionFailure()
                // We continue anyway
            }
            
            
            // The view context may have to refresh certain contacts at this point
            
            if !objectIDsOfContactsToRefreshInViewContext.isEmpty {
                DispatchQueue.main.async {
                    let objectsToRefresh = ObvStack.shared.viewContext.registeredObjects
                        .filter({ objectIDsOfContactsToRefreshInViewContext.contains($0.objectID) })
                    objectsToRefresh.forEach { objectID in
                        ObvStack.shared.viewContext.refresh(objectID, mergeChanges: true)
                    }
                }
            }
            
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
