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
import os.log
import ObvTypes
import ObvMetaManager
import ObvCrypto
import OlvidUtils


// MARK: - Protocol Steps

extension DownloadIdentityPhotoChildProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {
        
        case QueryServer = 0
        case DownloadingPhoto = 1

        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            
            switch self {
                
            case .QueryServer:
                let step = QueryServerStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .DownloadingPhoto:
                let step = ProcessPhotoStep(from: concreteProtocol, and: receivedMessage)
                return step
            }
        }
    }
    
    
    // MARK: - QueryServerStep
    
    final class QueryServerStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitialMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: DownloadIdentityPhotoChildProtocol.InitialMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let log = OSLog(subsystem: delegateManager.logSubsystem, category: DownloadIdentityPhotoChildProtocol.logCategory)
            os_log("DownloadIdentityPhotoChildProtocol: starting QueryServerStep", log: log, type: .debug)
            defer { os_log("DownloadIdentityPhotoChildProtocol: ending QueryServerStep", log: log, type: .debug) }

            guard let channelDelegate = delegateManager.channelDelegate else {
                os_log("The channel delegate is not set", log: log, type: .fault)
                return nil
            }
            guard let label = receivedMessage.contactIdentityDetailsElements.photoServerKeyAndLabel?.label else {
                os_log("The server label is not set", log: log, type: .fault)
                return nil
            }

            // Get the encrypted photo

            let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.ServerQuery(ownedIdentity: ownedIdentity))
            let concreteMessage = ServerGetPhotoMessage.init(coreProtocolMessage: coreMessage)
            let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.getUserData(of: receivedMessage.contactIdentity, label: label)
            guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

            return DownloadingPhotoState(contactIdentity: receivedMessage.contactIdentity, contactIdentityDetailsElements: receivedMessage.contactIdentityDetailsElements)
        }
        
    }
    
    
    // MARK: - DownloadingPhotoStep
    
    final class ProcessPhotoStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: DownloadingPhotoState
        let receivedMessage: ServerGetPhotoMessage
        
        init?(startState: DownloadingPhotoState, receivedMessage: DownloadIdentityPhotoChildProtocol.ServerGetPhotoMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: DownloadIdentityPhotoChildProtocol.logCategory)
            os_log("DownloadIdentityPhotoChildProtocol: starting ProcessPhotoStep", log: log, type: .debug)
            defer { os_log("DownloadIdentityPhotoChildProtocol: ending ProcessPhotoStep", log: log, type: .debug) }

            guard let identityDelegate = delegateManager.identityDelegate else {
                os_log("Could get identity delegate", log: log, type: .fault)
                return CancelledState()
            }

            guard let encryptedPhotoData = receivedMessage.encryptedPhoto else {
                // Photo was deleted from the server
                return PhotoDownloadedState()
            }

            let identityDetailsElements = startState.contactIdentityDetailsElements
            guard let photoServerKeyAndLabel = identityDetailsElements.photoServerKeyAndLabel else {
                os_log("Could not get photo label and key", log: log, type: .fault)
                return CancelledState()
            }

            let authEnc = ObvCryptoSuite.sharedInstance.authenticatedEncryption()

            let encryptedPhoto = EncryptedData(data: encryptedPhotoData)
            guard let photo = try? authEnc.decrypt(encryptedPhoto, with: photoServerKeyAndLabel.key) else {
                os_log("Could not decrypt the photo", log: log, type: .fault)
                return CancelledState()
            }

            // Check whether you downloaded your own photo or a contact photo
            if startState.contactIdentity == ownedIdentity {
                try identityDelegate.updateDownloadedPhotoOfOwnedIdentity(ownedIdentity, version: startState.contactIdentityDetailsElements.version, photo: photo, within: obvContext)
            } else {
                try identityDelegate.updateDownloadedPhotoOfContactIdentity(startState.contactIdentity, ofOwnedIdentity: ownedIdentity, version: startState.contactIdentityDetailsElements.version, photo: photo, within: obvContext)
            }

            let downloadedUserData = delegateManager.downloadedUserData
            if let photoPathToDelete = receivedMessage.photoPathToDelete {
                let url = downloadedUserData.appendingPathComponent(photoPathToDelete)
                try? FileManager.default.removeItem(at: url)
            }

            return PhotoDownloadedState()
        }
        
    }

}
