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


struct UtilsForAppMigrationV38ToV39 {
    
    static func getRepliedToMessage(discussion: NSManagedObject, replyToValues: (senderSequenceNumber: Int, senderThreadIdentifier: UUID, senderIdentifier: Data), manager: NSMigrationManager) throws -> NSManagedObject? {
        let repliedToMessage: NSManagedObject?
        do {
            
            let requestAmongReceivedMessages = NSFetchRequest<NSManagedObject>(entityName: "PersistedMessageReceived")
            requestAmongReceivedMessages.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "%K == %@", "discussion", discussion),
                NSPredicate(format: "%K == %d AND %K == %@ AND %K == %@",
                            "senderSequenceNumber", replyToValues.senderSequenceNumber,
                            "senderThreadIdentifier", replyToValues.senderThreadIdentifier as CVarArg,
                            "senderIdentifier", replyToValues.senderIdentifier as NSData),
            ])
            requestAmongReceivedMessages.fetchLimit = 1

            let requestAmongSentMessages = NSFetchRequest<NSManagedObject>(entityName: "PersistedMessageSent")
            requestAmongSentMessages.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "%K == %@", "discussion", discussion),
                NSPredicate(format: "%K == %d AND %K == %@ AND %K == %@",
                            "senderSequenceNumber", replyToValues.senderSequenceNumber,
                            "discussion.senderThreadIdentifier", replyToValues.senderThreadIdentifier as CVarArg,
                            "discussion.ownedIdentity.identity", replyToValues.senderIdentifier as NSData),
            ])
            requestAmongSentMessages.fetchLimit = 1

            repliedToMessage = try (manager.destinationContext.fetch(requestAmongReceivedMessages).first ?? manager.destinationContext.fetch(requestAmongSentMessages).first)
            
            return repliedToMessage
        }
    }
    
    
    struct MessageReferenceJSONForMigration: Decodable {
        
        let senderSequenceNumber: Int
        let senderThreadIdentifier: UUID
        let senderIdentifier: Data
        
        enum CodingKeys: String, CodingKey {
            case senderSequenceNumber = "ssn"
            case senderThreadIdentifier = "sti"
            case senderIdentifier = "si"
        }
        
    }

}
