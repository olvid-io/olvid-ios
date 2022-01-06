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

final class MigrationUtilsV11ToV12 {
    
    static func sanityzeSectionsIdentifiersOfMessage(discussionEntityName: String, manager: NSMigrationManager, errorDomain: String) throws {
        
        let dContext = manager.destinationContext
        let request: NSFetchRequest<NSManagedObject> = NSFetchRequest<NSManagedObject>(entityName: discussionEntityName)
        let dDiscussions = try dContext.fetch(request)
        
        for discussion in dDiscussions {
            
            guard let dMessages = discussion.value(forKey: "messages") as? Set<NSManagedObject> else {
                let message = "Could not get messages within discussion"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            
            let sortedMessages = try dMessages.sorted { (msg1, msg2) -> Bool in
                guard let sortIndex1 = msg1.value(forKey: "sortIndex") as? Double else {
                    let message = "Could not get sort index"
                    let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                    throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
                }
                guard let sortIndex2 = msg2.value(forKey: "sortIndex") as? Double else {
                    let message = "Could not get sort index"
                    let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                    throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
                }
                return sortIndex1 < sortIndex2
            }
            
            var previousMessage: NSObject? = nil
            for message in sortedMessages {
                
                if let previousMessage = previousMessage {
                    
                    guard let previousMessageSectionIdentifier = previousMessage.value(forKey: "sectionIdentifier") as? String else {
                        let message = "Could not get section identifier of previous message"
                        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                        throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
                    }
                    
                    guard let currentSectionIdentifier = message.value(forKey: "sectionIdentifier") as? String else {
                        let message = "Could not get section identifier"
                        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                        throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
                    }
                    
                    if previousMessageSectionIdentifier > currentSectionIdentifier {
                        // There is an issue within the discussion. We correct the issue
                        message.setValue(previousMessageSectionIdentifier, forKey: "sectionIdentifier")
                    }
                    
                }
                
                previousMessage = message
                
                
            }
            
        }
        
        
    }

    
}
