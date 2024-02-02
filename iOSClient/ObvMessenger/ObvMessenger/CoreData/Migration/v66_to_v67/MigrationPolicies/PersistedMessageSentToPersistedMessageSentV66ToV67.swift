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
import CoreData
import os.log


final class PersistedMessageSentToPersistedMessageSentV66ToV67: NSEntityMigrationPolicy {

    private static let errorDomain = "MessengerMigrationV58ToV59"
    private static let debugPrintPrefix = "[\(errorDomain)][PersistedMessageSentToPersistedMessageSentV66ToV67]"

    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedMessageSentToPersistedMessageSentV66ToV67")
            
    // Tested
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        do {
            
            debugPrint("\(Self.debugPrintPrefix) createDestinationInstances starts")
            defer {
                debugPrint("\(Self.debugPrintPrefix) createDestinationInstances ends")
            }
            
            let dInstance = try initializeDestinationInstance(forEntityName: "PersistedMessageSent",
                                                              forSource: sInstance,
                                                              in: mapping,
                                                              manager: manager,
                                                              errorDomain: Self.errorDomain)
            defer {
                manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
            }
            
            // Until now, all sent messages were sent from the current device.
            // Consequently, the appropriate senderThreadIdentifier of all sent messages are the one found in the discussion.
            
            guard let sDiscussion = sInstance.value(forKey: "discussion") as? NSManagedObject else {
                throw ObvError.couldNotGetAssociatedSourceDiscussion
            }
            
            guard let senderThreadIdentifier = sDiscussion.value(forKey: "senderThreadIdentifier") as? UUID else {
                throw ObvError.couldNotGetSenderThreadIdentifier
            }
            
            dInstance.setValue(senderThreadIdentifier, forKey: "senderThreadIdentifier")
            
        } catch {
            assertionFailure()
            throw error
        }
        
    }
    
    enum ObvError: Error {
        case couldNotGetAssociatedSourceDiscussion
        case couldNotGetSenderThreadIdentifier
    }

}

