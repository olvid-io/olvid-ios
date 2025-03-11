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

extension IdentityDetailsPublicationProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        
        case initial = 0
        case serverPutPhoto = 1
        case sendDetails = 2
        case propagateOwnDetails = 3
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .initial             : return InitialMessage.self
            case .serverPutPhoto      : return ServerPutPhotoMessage.self
            case .sendDetails         : return SendDetailsMessage.self
            case .propagateOwnDetails : return PropagateOwnDetailsMessage.self
            }
        }
    }

    
    // MARK: - InitialMessage
    
    struct InitialMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initial
        let coreProtocolMessage: CoreProtocolMessage

        let version: Int
        
        var encodedInputs: [ObvEncoded] {
            return [version.obvEncode()]
        }

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            self.version = try message.encodedInputs.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, version: Int) {
            self.coreProtocolMessage = coreProtocolMessage
            self.version = version
        }
        
    }
    
    
    // MARK: - ServerPutPhotoMessage
    
    struct ServerPutPhotoMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.serverPutPhoto
        let coreProtocolMessage: CoreProtocolMessage

        var encodedInputs: [ObvEncoded] { return [] }
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }

    }
    
    
    // MARK: - SendDetailsMessage
    
    struct SendDetailsMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.sendDetails
        let coreProtocolMessage: CoreProtocolMessage
        
        let contactIdentityDetailsElements: IdentityDetailsElements
        
        var encodedInputs: [ObvEncoded] {
            let encodedContactIdentityDetailsElements = try! contactIdentityDetailsElements.jsonEncode()
            return [encodedContactIdentityDetailsElements.obvEncode()]
        }
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedContactIdentityDetailsElements: Data = try message.encodedInputs.obvDecode()
            self.contactIdentityDetailsElements = try IdentityDetailsElements(encodedContactIdentityDetailsElements)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentityDetailsElements: IdentityDetailsElements) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentityDetailsElements = contactIdentityDetailsElements
        }

    }
    
    
    // MARK: - PropagateOwnDetailsMessage
    
    struct PropagateOwnDetailsMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.propagateOwnDetails
        let coreProtocolMessage: CoreProtocolMessage
        
        let ownedIdentityDetailsElements: IdentityDetailsElements
        
        var encodedInputs: [ObvEncoded] {
            get throws {
                let encodedContactIdentityDetailsElements = try ownedIdentityDetailsElements.jsonEncode()
                return [encodedContactIdentityDetailsElements.obvEncode()]
            }
        }
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedContactIdentityDetailsElements: Data = try message.encodedInputs.obvDecode()
            self.ownedIdentityDetailsElements = try IdentityDetailsElements(encodedContactIdentityDetailsElements)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, ownedIdentityDetailsElements: IdentityDetailsElements) {
            self.coreProtocolMessage = coreProtocolMessage
            self.ownedIdentityDetailsElements = ownedIdentityDetailsElements
        }

    }

}
