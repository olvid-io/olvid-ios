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

extension DownloadIdentityPhotoChildProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        
        case Initial = 0
        case ServerGetPhoto = 1
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .Initial        : return InitialMessage.self
            case .ServerGetPhoto : return ServerGetPhotoMessage.self
            }
        }
    }

    
    // MARK: - InitialMessage
    
    struct InitialMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.Initial
        let coreProtocolMessage: CoreProtocolMessage
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityDetailsElements: IdentityDetailsElements

        var encodedInputs: [ObvEncoded] {
            let encodedContactIdentityDetailsElements = try! contactIdentityDetailsElements.encode()
            return [contactIdentity.encode(), encodedContactIdentityDetailsElements.encode()]
        }
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { throw NSError() }
            self.contactIdentity = try message.encodedInputs[0].decode()
            let encodedContactIdentityDetailsElements: Data = try message.encodedInputs[1].decode()
            self.contactIdentityDetailsElements = try IdentityDetailsElements(encodedContactIdentityDetailsElements)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity, contactIdentityDetailsElements: IdentityDetailsElements) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
            self.contactIdentityDetailsElements = contactIdentityDetailsElements
        }

    }

    
    // MARK: - ServerGetPhotoMessage
    
    struct ServerGetPhotoMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.ServerGetPhoto
        let coreProtocolMessage: CoreProtocolMessage

        let encryptedPhoto: Data?
        let photoPathToDelete: String?
        
        var encodedInputs: [ObvEncoded] { return [] }
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            self.photoPathToDelete = String(encodedElements[0])
            guard let downloadedUserData = message.delegateManager?.downloadedUserData else { throw NSError() }

            if let photoPathToDelete = self.photoPathToDelete, !photoPathToDelete.isEmpty {
                let url = downloadedUserData.appendingPathComponent(photoPathToDelete)
                self.encryptedPhoto = try Data(contentsOf: url)
            } else {
                // If the photo was deleted from the server, the GetUserDataServerMethod return an empty String
                self.encryptedPhoto = nil
            }
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.encryptedPhoto = nil
            self.photoPathToDelete = nil
        }
        
    }

    
}
