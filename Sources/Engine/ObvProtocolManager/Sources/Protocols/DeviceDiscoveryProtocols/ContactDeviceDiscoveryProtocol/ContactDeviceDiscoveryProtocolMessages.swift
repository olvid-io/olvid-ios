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
import ObvCrypto
import ObvEncoder
import ObvTypes
import ObvOperation
import OlvidUtils



// MARK: - Protocol Messages

extension ContactDeviceDiscoveryProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        case initial = 0
        case childProtocolReachedExpectedState = 1
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .initial                           : return InitialMessage.self
            case .childProtocolReachedExpectedState : return ChildProtocolReachedExpectedStateMessage.self
            }
        }
    }
    
    
    struct InitialMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initial
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let contactIdentity: ObvCryptoIdentity

        var encodedInputs: [ObvEncoded] {
            return [contactIdentity.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = try CoreProtocolMessage(with: message)
            contactIdentity = try message.encodedInputs.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
        }
    }
    
    
    struct ChildProtocolReachedExpectedStateMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.childProtocolReachedExpectedState
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let childToParentProtocolMessageInputs: ChildToParentProtocolMessageInputs
        let deviceUidsSentState: DeviceDiscoveryForRemoteIdentityProtocol.DeviceUidsReceivedState
        
        var encodedInputs: [ObvEncoded] {
            return childToParentProtocolMessageInputs.toListOfEncoded()
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = try CoreProtocolMessage(with: message)
            guard let inputs = ChildToParentProtocolMessageInputs(try message.encodedInputs) else { assertionFailure(); throw Self.makeError(message: "Failed to obtain inputs") }
            childToParentProtocolMessageInputs = inputs
            deviceUidsSentState = try DeviceDiscoveryForRemoteIdentityProtocol.DeviceUidsReceivedState(childToParentProtocolMessageInputs.childProtocolInstanceEncodedReachedState)
        }
    }
}
