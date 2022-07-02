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
        
        case Initial = 0
        case ServerPutPhoto = 1
        case SendDetails = 2
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .Initial        : return InitialMessage.self
            case .ServerPutPhoto : return ServerPutPhotoMessage.self
            case .SendDetails    : return SendDetailsMessage.self
            }
        }
    }

    
    // MARK: - InitialMessage
    
    struct InitialMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.Initial
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
        
        let id: ConcreteProtocolMessageId = MessageId.ServerPutPhoto
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
        
        let id: ConcreteProtocolMessageId = MessageId.SendDetails
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
}
