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
import CoreData
import OlvidUtils


final class ContactIdentityToContactIdentityV52ToV53: NSEntityMigrationPolicy, ObvErrorMaker {
    
    static let errorDomain = "ContactIdentity"
    static let debugPrintPrefix = "[\(errorDomain)][ContactIdentityToContactIdentityV52ToV53]"
    
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        do {
            
            debugPrint("\(Self.debugPrintPrefix) createDestinationInstances starts")
            defer {
                debugPrint("\(Self.debugPrintPrefix) createDestinationInstances ends")
            }
            
            let dInstance = try initializeDestinationInstance(forEntityName: "ContactIdentity",
                                                              forSource: sInstance,
                                                              in: mapping,
                                                              manager: manager,
                                                              errorDomain: Self.errorDomain)
            defer {
                manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
            }
            
            // Get the isOneToOne Boolean value from the source instance
            
            guard let isOneToOne = sInstance.value(forKey: "isOneToOne") as? Bool else {
                assertionFailure()
                throw Self.makeError(message: "Could not obtain the isOneToOne value of a ContactIdentity instance")
            }
            
            // Set the one2one status of the destination object
            
            let rawOneToOneStatus: Int16 = isOneToOne ? 1 : 0
            dInstance.setValue(rawOneToOneStatus, forKey: "rawOneToOneStatus")
            
        } catch {
            assertionFailure()
            throw error
        }
        
    }
    
}
