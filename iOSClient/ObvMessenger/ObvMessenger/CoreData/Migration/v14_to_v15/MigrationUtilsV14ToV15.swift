/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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


final class MigrationUtilsV14ToV15 {
    
    struct ReplyToJSONForMigrationV14ToV15: Codable {
        
        let senderSequenceNumber: Int
        let senderThreadIdentifier: UUID
        let senderIdentifier: Data
        
        enum CodingKeys: String, CodingKey {
            case senderSequenceNumber = "ssn"
            case senderThreadIdentifier = "sti"
            case senderIdentifier = "si"
        }
        
        init(senderSequenceNumber: Int, senderThreadIdentifier: UUID, senderIdentifier: Data) {
            self.senderSequenceNumber = senderSequenceNumber
            self.senderThreadIdentifier = senderThreadIdentifier
            self.senderIdentifier = senderIdentifier
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(senderSequenceNumber, forKey: .senderSequenceNumber)
            try container.encode(senderThreadIdentifier, forKey: .senderThreadIdentifier)
            try container.encode(senderIdentifier, forKey: .senderIdentifier)
        }
        
    }
    
    

    static func mapReplyToToReplyToJSON(replyToAsAny: Any, errorDomain: String) throws -> ReplyToJSONForMigrationV14ToV15 {
        
        guard let replyTo = replyToAsAny as? NSManagedObject else {
            let message = "Could not turn the replyToAsAny into a NSManagedObject"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        
        guard let senderSequenceNumber = replyTo.value(forKey: "senderSequenceNumber") as? Int else {
            let message = "Could not extract the senderSequenceNumber from the replyTo"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        
        let senderThreadIdentifier: UUID
        let senderIdentifier: Data
        
        
        if replyTo.entity.name == "PersistedMessageReceived" {
            
            // The replyTo is a PersistedMessageReceived, it contains a `senderThreadIdentifier`
            guard let _senderThreadIdentifier = replyTo.value(forKey: "senderThreadIdentifier") as? UUID else {
                let message = "Could not extract the senderThreadIdentifier from the replyTo"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            senderThreadIdentifier = _senderThreadIdentifier
            // The senderIdentifier is the identity of the contact who send the replyTo
            guard let contactIdentity = replyTo.value(forKey: "contactIdentity") as? NSManagedObject else {
                let message = "Could not extract the contactIdentity from the replyTo"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            guard let identity = contactIdentity.value(forKey: "identity") as? Data else {
                let message = "Could not extract the identity from the contactIdentity"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            senderIdentifier = identity
            
        } else if replyTo.entity.name == "PersistedMessageSent" {
            
            // The replyTo is a PersistedMessageSent since it does not contain a `senderThreadIdentifier`.
            // This identifier can be found within the `discussion` relationship.
            guard let discussion = replyTo.value(forKey: "discussion") as? NSManagedObject else {
                let message = "Could not extract the discussion from the replyTo"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            guard let _senderThreadIdentifier = discussion.value(forKey: "senderThreadIdentifier") as? UUID else {
                let message = "Could not extract the senderThreadIdentifier from the discussion"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            senderThreadIdentifier = _senderThreadIdentifier
            // The sendIdentifier is the identity of the owned identity of the discussion
            guard let ownedIdentity = discussion.value(forKey: "ownedIdentity") as? NSManagedObject else {
                let message = "Could not extract the ownedIdentity from the discussion"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            guard let identity = ownedIdentity.value(forKey: "identity") as? Data else {
                let message = "Could not extract the identity from the ownedIdentity"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            senderIdentifier = identity
            
        } else {
            
            let message = "Could not determine the message type (sent or received)"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            
        }
        
        // Create the replyToJSON and set the appropriate value on the destination object
        
        let replyToJSON = MigrationUtilsV14ToV15.ReplyToJSONForMigrationV14ToV15(senderSequenceNumber: senderSequenceNumber,
                                                                                 senderThreadIdentifier: senderThreadIdentifier,
                                                                                 senderIdentifier: senderIdentifier)

        return replyToJSON
        
    }
}
