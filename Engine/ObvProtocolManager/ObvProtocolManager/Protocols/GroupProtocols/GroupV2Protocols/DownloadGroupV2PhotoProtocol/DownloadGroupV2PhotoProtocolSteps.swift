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
import OlvidUtils
import ObvMetaManager
import ObvCrypto


// MARK: - Protocol Steps

extension DownloadGroupV2PhotoProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {
        
        case queryServer = 0
        case processPhoto = 1

        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            switch self {
            case .queryServer:
                let step = QueryServerStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .processPhoto:
                let step = ProcessPhotoStep(from: concreteProtocol, and: receivedMessage)
                return step
            }
        }
    }

    
    // MARK: - QueryServerStep

    final class QueryServerStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitialMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: DownloadGroupV2PhotoProtocol.InitialMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {

            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let groupIdentifier = receivedMessage.groupIdentifier
            let serverPhotoInfo = receivedMessage.serverPhotoInfo
            
            let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.ServerQuery(ownedIdentity: ownedIdentity))
            let concreteMessage = ServerGetPhotoMessage.init(coreProtocolMessage: coreMessage)

            let serverQueryType: ObvChannelServerQueryMessageToSend.QueryType
            switch groupIdentifier.category {
            case .server:
                guard let serverPhotoInfoIdentity = serverPhotoInfo.identity else {
                    assertionFailure()
                    return CancelledState()
                }
                serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.getUserData(of: serverPhotoInfoIdentity, label: receivedMessage.serverPhotoInfo.photoServerKeyAndLabel.label)
            case .keycloak:
                serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.getKeycloakData(serverURL: groupIdentifier.serverURL, serverLabel: receivedMessage.serverPhotoInfo.photoServerKeyAndLabel.label)
            }

            guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

            return DownloadingPhotoState(groupIdentifier: groupIdentifier, serverPhotoInfo: serverPhotoInfo)
            
        }

    }

    
    // MARK: - DownloadingPhotoStep

    final class ProcessPhotoStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: DownloadingPhotoState
        let receivedMessage: ServerGetPhotoMessage

        init?(startState: DownloadingPhotoState, receivedMessage: DownloadGroupV2PhotoProtocol.ServerGetPhotoMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {

            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let groupIdentifier = startState.groupIdentifier
            let serverPhotoInfo = startState.serverPhotoInfo
            
            guard let encryptedPhoto = receivedMessage.encryptedPhoto else {
                // Photo was deleted from the server
                return PhotoDownloadedState()
            }
            
            let authEnc = ObvCryptoSuite.sharedInstance.authenticatedEncryption()
            let decryptedPhoto = try authEnc.decrypt(encryptedPhoto, with: serverPhotoInfo.photoServerKeyAndLabel.key)
            
            try identityDelegate.setDownloadedPhotoOfGroupV2(withGroupWithIdentifier: groupIdentifier,
                                                             of: ownedIdentity,
                                                             serverPhotoInfo: serverPhotoInfo,
                                                             photo: decryptedPhoto,
                                                             within: obvContext)
            
            let downloadedUserData = delegateManager.downloadedUserData
            if let photoPathToDelete = receivedMessage.photoPathToDelete {
                let url = downloadedUserData.appendingPathComponent(photoPathToDelete)
                try? FileManager.default.removeItem(at: url)
            }
            
            return PhotoDownloadedState()
            
        }

    }


}
