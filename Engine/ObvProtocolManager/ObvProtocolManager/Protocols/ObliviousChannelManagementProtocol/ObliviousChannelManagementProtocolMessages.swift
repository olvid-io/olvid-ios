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
import ObvEncoder
import ObvTypes
import ObvCrypto
import ObvMetaManager


// MARK: - Protocol Messages

extension ObliviousChannelManagementProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        
        case InitiateContactDeletion = 0
        case ContactDeletionNotification = 1
        case PropagateContactDeletion = 2
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .InitiateContactDeletion     : return InitiateContactDeletionMessage.self
            case .ContactDeletionNotification : return ContactDeletionNotificationMessage.self
            case .PropagateContactDeletion    : return PropagateContactDeletionMessage.self
            }
        }
    }
    
    
    // MARK: - InitiateContactDeletionMessage
    
    struct InitiateContactDeletionMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.InitiateContactDeletion
        let coreProtocolMessage: CoreProtocolMessage
        
        let contactIdentity: ObvCryptoIdentity
        
        var encodedInputs: [ObvEncoded] { return [contactIdentity.encode()] }
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            contactIdentity = try message.encodedInputs.decode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
        }
        
    }

    
    // MARK: - ContactDeletionNotificationMessage
    
    struct ContactDeletionNotificationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.ContactDeletionNotification
        let coreProtocolMessage: CoreProtocolMessage
        
        var encodedInputs: [ObvEncoded] { return [] }
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }
        
    }

    
    // MARK: - PropagateContactDeletionMessage
    
    struct PropagateContactDeletionMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.PropagateContactDeletion
        let coreProtocolMessage: CoreProtocolMessage
        
        let contactIdentity: ObvCryptoIdentity

        var encodedInputs: [ObvEncoded] { return [contactIdentity.encode()] }
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            contactIdentity = try message.encodedInputs.decode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
        }
        
    }

}
