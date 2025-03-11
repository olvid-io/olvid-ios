/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import os.log
import ObvAppCoreConstants

fileprivate let errorDomain = "MessengerMigrationV30ToV31"
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedMessageSystemToPersistedMessageSystemV30ToV31]"


final class PersistedMessageSystemToPersistedMessageSystemV30ToV31: NSEntityMigrationPolicy {

    private func makeError(message: String) -> Error {
        let message = [debugPrintPrefix, message].joined(separator: " ")
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "PersistedMessageSystemToPersistedMessageSystemV30ToV31")
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {

        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }

        // We do not want to fail the whole migration because of an issue related to migrating a call system message, so we wrap the migration in a do/catch and simply drop the source instance if the migration fails.
        
        do {
            
            let entityName = "PersistedMessageSystem"
            let dInstance = try initializeDestinationInstance(forEntityName: entityName,
                                                              forSource: sInstance,
                                                              in: mapping,
                                                              manager: manager,
                                                              errorDomain: errorDomain)
            
            // If the source category is 5 or in [8,...,14], it corresponds to a call and should be mapped to 5.
            // Note that a default value was already set in `initializeDestinationInstance`.
            
            guard let sRawCategory = sInstance.value(forKey: "rawCategory") as? Int else {
                throw makeError(message: "Could not get the source raw category")
            }
            
            if [5, 8, 9, 10, 11, 12, 13, 14].contains(sRawCategory) {
                
                let dRawCategory = 5
                dInstance.setValue(dRawCategory, forKey: "rawCategory")
                
                // In that case, we create a `PersistedCallLogItem` instance
                
                let isIncoming = [9, 11, 12, 13, 14].contains(sRawCategory)
                guard let messageTimestamp = sInstance.value(forKey: "timestamp") as? Date else {
                    throw makeError(message: "Could not extract timestamp from source system message")
                }
                
                guard let sDiscussion = sInstance.value(forKey: "discussion") as? NSManagedObject else {
                    throw makeError(message: "Could not extract discussion from source system message")
                }
                
                let sContactIdentity: NSManagedObject?
                if sDiscussion.entity.name == "PersistedOneToOneDiscussion" {
                    guard let _sContactIdentity = sDiscussion.value(forKey: "contactIdentity") as? NSManagedObject else {
                        throw makeError(message: "Could not extract contact from source discussion (expected to be a one2one discussion)")
                    }
                    sContactIdentity = _sContactIdentity
                } else {
                    sContactIdentity = nil
                }
                
                guard let sOwnedIdentity = sDiscussion.value(forKey: "ownedIdentity") as? NSManagedObject else {
                    throw makeError(message: "Could not extract owned identity from source discussion")
                }
                
                guard let sOwnedIdentity = sOwnedIdentity.value(forKey: "identity") as? Data else {
                    throw makeError(message: "Could not extract identity from source owned identity")
                }
                                
                let rawReportKind: Int
                switch sRawCategory {
                case 5: rawReportKind = 0
                case 8: rawReportKind = 2
                case 9: rawReportKind = 3
                case 10: rawReportKind = 1
                case 11: rawReportKind = 4
                case 12: rawReportKind = 5
                case 13: rawReportKind = 6
                case 14: rawReportKind = 7
                default:
                    throw makeError(message: "Unexpected system message category for a call: \(sRawCategory)")
                }
                
                let dPersistedCallLogItem = try createPersistedCallLogItemInstance(manager: manager,
                                                                                   endDate: messageTimestamp,
                                                                                   isIncoming: isIncoming,
                                                                                   rawOwnedCryptoId: sOwnedIdentity,
                                                                                   rawReportKind: rawReportKind,
                                                                                   startDate: messageTimestamp,
                                                                                   dMessageSystem: dInstance)
                
                var sourceContactForDestinationPersistedCallLogItem = [NSManagedObject: NSManagedObject]()
                if let _table = manager.userInfo?["sourceContactForDestinationPersistedCallLogItem"] as? [NSManagedObject: NSManagedObject] {
                    sourceContactForDestinationPersistedCallLogItem = _table
                } else {
                    manager.userInfo = ["sourceContactForDestinationPersistedCallLogItem": sourceContactForDestinationPersistedCallLogItem]
                }
                
                if let sContactIdentity = sContactIdentity {
                    sourceContactForDestinationPersistedCallLogItem[dPersistedCallLogItem] = sContactIdentity
                    manager.userInfo?["sourceContactForDestinationPersistedCallLogItem"] = sourceContactForDestinationPersistedCallLogItem
                }
                
            }
            
            // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
            
            manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
            
        } catch {
            os_log("Failed to migrate a system message: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }

    }

    
    
    override func createRelationships(forDestination dInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        // In `createDestinationInstances()`, we created a `PersistedCallLogItem` associated with this message system, in case this message is related to a call.
        // There is still one missing piece: this `PersistedCallLogItem` should be related to a contact. This is what we will do now.
        // Just as in the previous step, we do not want the whole process to fail if this mapping cannot be set. So we wrap this procedure in a do/catch.
        
        do {
            
            guard let dRawCategory = dInstance.value(forKey: "rawCategory") as? Int else {
                throw makeError(message: "Could not extract the raw category from the destination system message")
            }
            
            guard dRawCategory == 5 else {
                os_log("No custom association needed for a system message the current system message", log: log, type: .info)
                return
            }
            
            guard let dPersistedCallLogItem = dInstance.value(forKey: "optionalCallLogItem") as? NSManagedObject else {
                throw makeError(message: "Could not extract Call log item from system message during relationship phase")
            }
            
            guard let sourceContactForDestinationPersistedCallLogItem = manager.userInfo?["sourceContactForDestinationPersistedCallLogItem"] as? [NSManagedObject: NSManagedObject] else {
                throw makeError(message: "Could not recover the sourceContactForDestinationPersistedCallLogItem array from the manager user info")
            }
            
            let dContactIdentity: NSManagedObject?
            if let sContactIdentity = sourceContactForDestinationPersistedCallLogItem[dPersistedCallLogItem] {
                // Happens when the discussion was a one2one discussion (not locked)
                guard let _dContactIdentity = manager.destinationInstances(forEntityMappingName: "PersistedObvContactIdentityToPersistedObvContactIdentity", sourceInstances: [sContactIdentity]).first else {
                    throw makeError(message: "Could not recover the source contact associated to the call log item")
                }
                dContactIdentity = _dContactIdentity
            } else {
                // Happens when the discussion was a locked one2one discussion
                dContactIdentity = nil
            }
            
            guard let rawReportKind = dPersistedCallLogItem.value(forKey: "rawReportKind") as? Int else {
                throw makeError(message: "Could not recover the report kind from the call log item during the relationship phase")
            }
            
            let isCaller = [0, 1, 2].contains(rawReportKind)
            
            try createPersistedCallLogContact(manager: manager,
                                              isCaller: isCaller,
                                              rawReportKind: rawReportKind,
                                              dCallLogItem: dPersistedCallLogItem,
                                              dContactIdentity: dContactIdentity)
            
        } catch {
            os_log("Failed to migrate a system message in the association phase: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
        
    }
    
    

    /// This method creates a `PersistedCallLogItem` instance in the destination context. It assumes that there are no group calls.
    /// It associates this instance we the message system.
    private func createPersistedCallLogItemInstance(manager: NSMigrationManager, endDate: Date, isIncoming: Bool, rawOwnedCryptoId: Data, rawReportKind: Int, startDate: Date, dMessageSystem: NSManagedObject) throws -> NSManagedObject {

        let entityName = "PersistedCallLogItem"

        // Create an instance of the destination object.
        let dObject: NSManagedObject
        do {
            guard let description = NSEntityDescription.entity(forEntityName: entityName, in: manager.destinationContext) else {
                throw makeError(message: "Invalid entity name: \(entityName)")
            }
            dObject = NSManagedObject(entity: description, insertInto: manager.destinationContext)
        }

        dObject.setValue(UUID(), forKey: "callUUID")
        dObject.setValue(endDate, forKey: "endDate")
        dObject.setValue(nil, forKey: "groupOwnerIdentity")
        dObject.setValue(nil, forKey: "groupUidRaw")
        dObject.setValue(isIncoming, forKey: "isIncoming")
        dObject.setValue(1, forKey: "rawInitialParticipantCount")
        dObject.setValue(rawOwnedCryptoId, forKey: "rawOwnedCryptoId")
        dObject.setValue(rawReportKind, forKey: "rawReportKind")
        dObject.setValue(startDate, forKey: "startDate")
        dObject.setValue(0, forKey: "unknownContactsCount")
        
        dMessageSystem.setValue(dObject, forKey: "optionalCallLogItem")
        dObject.setValue(dMessageSystem, forKey: "messageSystem")
        
        return dObject

    }

    
    private func createPersistedCallLogContact(manager: NSMigrationManager, isCaller: Bool, rawReportKind: Int, dCallLogItem: NSManagedObject, dContactIdentity: NSManagedObject?) throws {
        
        let entityName = "PersistedCallLogContact"

        // Create an instance of the destination object.
        let dObject: NSManagedObject
        do {
            guard let description = NSEntityDescription.entity(forEntityName: entityName, in: manager.destinationContext) else {
                throw makeError(message: "Invalid entity name: \(entityName)")
            }
            dObject = NSManagedObject(entity: description, insertInto: manager.destinationContext)
        }
        
        dObject.setValue(isCaller, forKey: "isCaller")
        dObject.setValue(rawReportKind, forKey: "rawReportKind")

        dObject.setValue(dCallLogItem, forKey: "callLogItem")
        dObject.setValue(dContactIdentity, forKey: "contactIdentity")

    }
    
}
