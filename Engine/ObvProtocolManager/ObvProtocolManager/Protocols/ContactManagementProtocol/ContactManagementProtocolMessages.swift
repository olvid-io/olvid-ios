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
import ObvEncoder
import ObvTypes
import ObvCrypto
import ObvMetaManager


// MARK: - Protocol Messages

extension ContactManagementProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        
        case initiateContactDeletion = 0
        case contactDeletionNotification = 1
        case propagateContactDeletion = 2
        case initiateContactDowngrade = 3
        case downgradeNotification = 4
        case propagateDowngrade = 5
        case performContactDeviceDiscovery = 6
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .initiateContactDeletion      : return InitiateContactDeletionMessage.self
            case .contactDeletionNotification  : return ContactDeletionNotificationMessage.self
            case .propagateContactDeletion     : return PropagateContactDeletionMessage.self
            case .initiateContactDowngrade     : return InitiateContactDowngradeMessage.self
            case .downgradeNotification        : return DowngradeNotificationMessage.self
            case .propagateDowngrade           : return PropagateDowngradeMessage.self
            case .performContactDeviceDiscovery: return PerformContactDeviceDiscoveryMessage.self
            }
        }
    }
    
    
    // MARK: - InitiateContactDeletionMessage
    
    struct InitiateContactDeletionMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initiateContactDeletion
        let coreProtocolMessage: CoreProtocolMessage
        
        let contactIdentity: ObvCryptoIdentity
        
        var encodedInputs: [ObvEncoded] { return [contactIdentity.obvEncode()] }
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            contactIdentity = try message.encodedInputs.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
        }
        
    }

    
    // MARK: - ContactDeletionNotificationMessage
    
    struct ContactDeletionNotificationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.contactDeletionNotification
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
        
        let id: ConcreteProtocolMessageId = MessageId.propagateContactDeletion
        let coreProtocolMessage: CoreProtocolMessage
        
        let contactIdentity: ObvCryptoIdentity

        var encodedInputs: [ObvEncoded] { return [contactIdentity.obvEncode()] }
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            contactIdentity = try message.encodedInputs.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
        }
        
    }

    
    // MARK: - DowngradeContactMessage
    
    struct InitiateContactDowngradeMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initiateContactDowngrade
        let coreProtocolMessage: CoreProtocolMessage
        
        let contactIdentity: ObvCryptoIdentity

        var encodedInputs: [ObvEncoded] { return [contactIdentity.obvEncode()] }
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            contactIdentity = try message.encodedInputs.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
        }
        
    }

    
    // MARK: - DowngradeNotificationMessage
    
    struct DowngradeNotificationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.downgradeNotification
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
        
        let id: ConcreteProtocolMessageId = MessageId.propagateDowngrade
        let coreProtocolMessage: CoreProtocolMessage
        
        let contactIdentity: ObvCryptoIdentity

        var encodedInputs: [ObvEncoded] { return [contactIdentity.obvEncode()] }
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            contactIdentity = try message.encodedInputs.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
        }
        
    }

    
    // MARK: - PerformContactDeviceDiscoveryMessage
    
    struct PerformContactDeviceDiscoveryMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.performContactDeviceDiscovery
        let coreProtocolMessage: CoreProtocolMessage
        
        var encodedInputs: [ObvEncoded] { return [] }

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }
        
    }

}
