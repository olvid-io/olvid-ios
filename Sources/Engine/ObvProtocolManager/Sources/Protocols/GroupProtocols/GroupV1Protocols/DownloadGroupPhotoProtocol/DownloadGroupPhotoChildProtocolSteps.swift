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
import os.log
import ObvTypes
import ObvMetaManager
import ObvCrypto
import ObvEncoder
import OlvidUtils

// MARK: - Protocol Steps

extension DownloadGroupPhotoChildProtocol {

    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {

        case queryServer = 0
        case downloadingPhoto = 1

        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {

            switch self {
            case .queryServer:
                let step = QueryServerStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .downloadingPhoto:
                let step = ProcessPhotoStep(from: concreteProtocol, and: receivedMessage)
                return step
            }
        }
    }

    // MARK: - QueryServerStep

    final class QueryServerStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitialMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: DownloadGroupPhotoChildProtocol.InitialMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {

            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let log = OSLog(subsystem: delegateManager.logSubsystem, category: DownloadIdentityPhotoChildProtocol.logCategory)

            guard let label = receivedMessage.groupInformation.groupDetailsElements.photoServerKeyAndLabel?.label else {
                os_log("The server label is not set", log: log, type: .fault)
                return nil
            }

            // Get the encrypted photo

            let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.serverQuery(ownedIdentity: ownedIdentity))
            let concreteMessage = ServerGetPhotoMessage.init(coreProtocolMessage: coreMessage)
            let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.getUserData(of: receivedMessage.groupInformation.groupOwnerIdentity, label: label)
            guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
            _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)

            return DownloadingPhotoState(groupInformation: receivedMessage.groupInformation)
        }

    }


    // MARK: - DownloadingPhotoStep

    final class ProcessPhotoStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: DownloadingPhotoState
        let receivedMessage: ServerGetPhotoMessage

        init?(startState: DownloadingPhotoState, receivedMessage: DownloadGroupPhotoChildProtocol.ServerGetPhotoMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {

            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let log = OSLog(subsystem: delegateManager.logSubsystem, category: DownloadIdentityPhotoChildProtocol.logCategory)

            guard let encryptedPhotoData = receivedMessage.encryptedPhoto else {
                // Photo was deleted from the server
                return PhotoDownloadedState()
            }

            let groupInformation = startState.groupInformation
            guard let photoServerKeyAndLabel = groupInformation.groupDetailsElements.photoServerKeyAndLabel else {
                os_log("Could not get photo label and key", log: log, type: .fault)
                return CancelledState()
            }

            let authEnc = ObvCryptoSuite.sharedInstance.authenticatedEncryption()

            guard let photo = try? authEnc.decrypt(encryptedPhotoData, with: photoServerKeyAndLabel.key) else {
                os_log("Could not decrypt the photo", log: log, type: .fault)
                return CancelledState()
            }

            if groupInformation.groupOwnerIdentity == ownedIdentity {
                try identityDelegate.updateDownloadedPhotoOfContactGroupOwned(
                    ownedIdentity: ownedIdentity,
                    groupUid: groupInformation.groupUid,
                    version: groupInformation.groupDetailsElements.version,
                    photo: photo,
                    within: obvContext)
            } else {
                try identityDelegate.updateDownloadedPhotoOfContactGroupJoined(
                    ownedIdentity: ownedIdentity,
                    groupOwner: groupInformation.groupOwnerIdentity,
                    groupUid: groupInformation.groupUid,
                    version: groupInformation.groupDetailsElements.version,
                    photo: photo,
                    within: obvContext)
            }

            let downloadedUserData = delegateManager.downloadedUserData
            if let photoFilenameToDelete = receivedMessage.photoFilenameToDelete {
                let url = downloadedUserData.appendingPathComponent(photoFilenameToDelete)
                try? FileManager.default.removeItem(at: url)
            }

            return PhotoDownloadedState()
        }

    }


}
