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
import ObvMetaManager
import ObvEncoder
import ObvCrypto


// MARK: - Protocol Messages

extension DownloadGroupV2PhotoProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        
        case initial = 0
        case serverGetPhoto = 1

        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .initial        : return InitialMessage.self
            case .serverGetPhoto : return ServerGetPhotoMessage.self
            }
        }
    }
    
    
    // MARK: - InitialMessage
    
    struct InitialMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initial
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message

        let groupIdentifier: GroupV2.Identifier
        let serverPhotoInfo: GroupV2.ServerPhotoInfo
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, groupIdentifier: GroupV2.Identifier, serverPhotoInfo: GroupV2.ServerPhotoInfo) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupIdentifier = groupIdentifier
            self.serverPhotoInfo = serverPhotoInfo
        }

        var encodedInputs: [ObvEncoded] {
            [groupIdentifier.obvEncode(), serverPhotoInfo.obvEncode()]
        }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { throw Self.makeError(message: "Unexpected number of encoded elements") }
            self.groupIdentifier = try message.encodedInputs[0].obvDecode()
            self.serverPhotoInfo = try message.encodedInputs[1].obvDecode()
        }

    }

    
    // MARK: - ServerGetPhotoMessage
    
    struct ServerGetPhotoMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.serverGetPhoto
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message

        let encryptedPhoto: EncryptedData?
        let photoPathToDelete: String?

        // Init when sending this message (not used in this specific case)

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.encryptedPhoto = nil
            self.photoPathToDelete = nil
        }

        var encodedInputs: [ObvEncoded] { return [] }

        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs

            if let photoPathToDelete = String(encodedElements[0]) {

                // Legacy decoding (changed on 2022-08-05)

                self.photoPathToDelete = photoPathToDelete
                guard let downloadedUserData = message.delegateManager?.downloadedUserData else {
                    assertionFailure()
                    throw Self.makeError(message: "Could not get downloaded user data")
                }
                
                if let photoPathToDelete = self.photoPathToDelete, !photoPathToDelete.isEmpty {
                    let url = downloadedUserData.appendingPathComponent(photoPathToDelete)
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
                    self.photoPathToDelete = nil
                case .downloaded(let userDataPath):
                    self.photoPathToDelete = userDataPath
                    guard let downloadedUserData = message.delegateManager?.downloadedUserData else {
                        assertionFailure()
                        throw Self.makeError(message: "Could not get downloaded user data")
                    }
                    
                    if let photoPathToDelete = self.photoPathToDelete, !photoPathToDelete.isEmpty {
                        let url = downloadedUserData.appendingPathComponent(photoPathToDelete)
                        self.encryptedPhoto = EncryptedData(data: try Data(contentsOf: url))
                    } else {
                        // If the photo was deleted from the server, the GetUserDataServerMethod return an empty String
                        self.encryptedPhoto = nil
                    }
                }

            } else {
                
                assertionFailure()
                self.encryptedPhoto = nil
                self.photoPathToDelete = nil

            }
        }

    }

}
