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
            let encodedContactIdentityDetailsElements = try! contactIdentityDetailsElements.jsonEncode()
            return [contactIdentity.obvEncode(), encodedContactIdentityDetailsElements.obvEncode()]
        }
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.contactIdentity = try message.encodedInputs[0].obvDecode()
            let encodedContactIdentityDetailsElements: Data = try message.encodedInputs[1].obvDecode()
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

        let encryptedPhoto: EncryptedData?
        let photoFilenameToDelete: String?
        
        var encodedInputs: [ObvEncoded] { return [] }
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs

            if let photoFilenameToDelete = String(encodedElements[0]) {

                // Legacy decoding (changed on 2022-08-05)

                self.photoFilenameToDelete = photoFilenameToDelete
                guard let downloadedUserData = message.delegateManager?.downloadedUserData else {
                    throw Self.makeError(message: "Could not get downloaded user data")
                }
                
                if let photoFilenameToDelete = self.photoFilenameToDelete, !photoFilenameToDelete.isEmpty {
                    let url = downloadedUserData.appendingPathComponent(photoFilenameToDelete)
                    self.encryptedPhoto = EncryptedData(data: try Data(contentsOf: url))
                } else {
                    // If the photo was deleted from the server, the GetUserDataServerMethod return an empty String
                    self.encryptedPhoto = nil
                }

            } else if let result = GetUserDataResult(encodedElements[0]) {

                // Current decoding
                
                switch result {
                case .deletedFromServer:
                    self.encryptedPhoto = nil
                    self.photoFilenameToDelete = nil
                case .downloaded(userDataFilename: let userDataFilename):
                    self.photoFilenameToDelete = userDataFilename
                    guard let downloadedUserData = message.delegateManager?.downloadedUserData else {
                        throw Self.makeError(message: "Could not get downloaded user data")
                    }
                    
                    if let photoFilenameToDelete = self.photoFilenameToDelete, !photoFilenameToDelete.isEmpty {
                        let url = downloadedUserData.appendingPathComponent(photoFilenameToDelete)
                        self.encryptedPhoto = EncryptedData(data: try Data(contentsOf: url))
                    } else {
                        // If the photo was deleted from the server, the GetUserDataServerMethod return an empty String
                        self.encryptedPhoto = nil
                    }
                }

            } else {
                
                assertionFailure()
                self.encryptedPhoto = nil
                self.photoFilenameToDelete = nil

            }
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.encryptedPhoto = nil
            self.photoFilenameToDelete = nil
        }
        
    }

    
}
