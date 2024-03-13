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
import os.log
import ObvCrypto
import ObvEncoder
import ObvTypes
import ObvOperation
import ObvMetaManager
import OlvidUtils



// MARK: - Protocol Messages

extension DeviceDiscoveryForRemoteIdentityProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        case initial = 0
        case serverQuery = 3
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .initial     : return InitialMessage.self
            case .serverQuery : return ServerQueryMessage.self
            }
        }
    }
    
    
    struct InitialMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initial
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let remoteIdentity: ObvCryptoIdentity
        
        var encodedInputs: [ObvEncoded] {
            return [remoteIdentity.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            remoteIdentity = try message.encodedInputs.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, remoteIdentity: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.remoteIdentity = remoteIdentity
        }
    }
    
    
    struct ServerQueryMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.serverQuery
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message

        let contactDeviceDiscoveryResult: ContactDeviceDiscoveryResult? // Only set when the message is sent to this protocol, not when sending this message to the server
        
        var encodedInputs: [ObvEncoded] { return [] }
        
        // Initializers

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded elements") }
            if let result = ContactDeviceDiscoveryResult(encodedElements[0]) {
                self.contactDeviceDiscoveryResult = result
            } else {
                // Try the legacy decoding
                guard let listOfEncodedUids = [ObvEncoded](encodedElements[0]) else { assertionFailure(); throw Self.makeError(message: "Failed to get list of encoded inputs") }
                var uids = [UID]()
                for encodedUid in listOfEncodedUids {
                    guard let uid = UID(encodedUid) else { assertionFailure(); throw Self.makeError(message: "Failed to decode UID") }
                    uids.append(uid)
                }
                self.contactDeviceDiscoveryResult = .success(deviceUIDs: uids)
            }
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactDeviceDiscoveryResult = nil
        }
    }
        
}

