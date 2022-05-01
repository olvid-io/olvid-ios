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
import ObvEncoder
import ObvTypes
import ObvCrypto
import ObvMetaManager


// MARK: - Protocol Messages

extension ContactManagementProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        
        case InitiateContactDeletion = 0
        case ContactDeletionNotification = 1
        case PropagateContactDeletion = 2
        case InitiateContactDowngrade = 3
        case DowngradeNotification = 4
        case PropagateDowngrade = 5
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .InitiateContactDeletion     : return InitiateContactDeletionMessage.self
            case .ContactDeletionNotification : return ContactDeletionNotificationMessage.self
            case .PropagateContactDeletion    : return PropagateContactDeletionMessage.self
            case .InitiateContactDowngrade    : return InitiateContactDowngradeMessage.self
            case .DowngradeNotification       : return DowngradeNotificationMessage.self
            case .PropagateDowngrade          : return PropagateDowngradeMessage.self
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

    
    // MARK: - DowngradeContactMessage
    
    struct InitiateContactDowngradeMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.InitiateContactDowngrade
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

    
    // MARK: - DowngradeNotificationMessage
    
    struct DowngradeNotificationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.DowngradeNotification
        let coreProtocolMessage: CoreProtocolMessage
        
        var encodedInputs: [ObvEncoded] { return [] }
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }

    }

    
    // MARK: - PropagateDowngradeMessage
    
    struct PropagateDowngradeMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.PropagateDowngrade
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
