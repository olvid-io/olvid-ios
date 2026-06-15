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
import OSLog
import ObvAppCoreConstants


final class PersistedGroupV2MemberToPersistedGroupV2MemberV78ToV79: NSEntityMigrationPolicy {
    
    private static let errorDomain = "MessengerMigrationV78ToV79"
    private static let debugPrintPrefix = "[\(errorDomain)][PersistedGroupV2MemberToPersistedGroupV2MemberV78ToV79]"

    let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "PersistedGroupV2MemberToPersistedGroupV2MemberV78ToV79")
            
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        do {
            
            debugPrint("\(Self.debugPrintPrefix) createDestinationInstances starts")
            defer {
                debugPrint("\(Self.debugPrintPrefix) createDestinationInstances ends")
            }
            
            let dInstance = try initializeDestinationInstance(forEntityName: "PersistedGroupV2Member",
                                                              forSource: sInstance,
                                                              in: mapping,
                                                              manager: manager,
                                                              errorDomain: Self.errorDomain)
            defer {
                manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
            }

            // rawDateCreated was added and is non-optional. Set it to now.
            
            let now = Date.now
            dInstance.setValue(now, forKey: "rawDateCreated")

            // rawDateUnpended was added. If the member is non-pending, we set it to now.
            
            guard let isPending = dInstance.value(forKey: "isPending") as? Bool else {
                assertionFailure()
                throw ObvError.couldNotDetermineWhetherIsPending
            }
            
            if isPending {
                dInstance.setValue(nil, forKey: "rawDateUnpended")
            } else {
                dInstance.setValue(now, forKey: "rawDateUnpended") // Same as rawDateCreated
            }
            
            // rawNeedsReplayOfPastEvents was added. We always set it to false during migration.
            
            dInstance.setValue(false, forKey: "rawNeedsReplayOfPastEvents")

        } catch {
            assertionFailure()
            throw error
        }
        
    }

    enum ObvError: Error {
        case couldNotDetermineWhetherIsPending
    }
    
}
