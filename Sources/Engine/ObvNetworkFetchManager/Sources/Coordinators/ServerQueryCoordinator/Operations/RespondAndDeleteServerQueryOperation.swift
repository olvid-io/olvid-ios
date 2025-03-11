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
import CoreData
import ObvMetaManager
import ObvCrypto
import OlvidUtils
import ObvEncoder


final class RespondAndDeleteServerQueryOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private static let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    private static let logCategory = "RespondAndDeleteServerQueryOperation"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)

    private let objectIdOfPendingServerQuery: NSManagedObjectID
    private let prng: PRNGService
    private let delegateManager: ObvNetworkFetchDelegateManager
    private let channelDelegate: ObvChannelDelegate
    
    init(objectIdOfPendingServerQuery: NSManagedObjectID, prng: PRNGService, delegateManager: ObvNetworkFetchDelegateManager, channelDelegate: ObvChannelDelegate) {
        self.objectIdOfPendingServerQuery = objectIdOfPendingServerQuery
        self.prng = prng
        self.delegateManager = delegateManager
        self.channelDelegate = channelDelegate
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let serverQuery = try PendingServerQuery.get(objectId: objectIdOfPendingServerQuery, delegateManager: delegateManager, within: obvContext) else {
                os_log("Could not find pending server query in database", log: Self.log, type: .error)
                return
            }

            guard let serverResponseType = serverQuery.responseType else {
                os_log("The server response type is not set", log: Self.log, type: .fault)
                assertionFailure()
                return
            }

            let channelServerResponseType: ObvChannelServerResponseMessageToSend.ResponseType
            switch serverResponseType {
//            case .deviceDiscovery(of: let contactIdentity, deviceUids: let deviceUids):
//                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.deviceDiscovery(of: contactIdentity, deviceUids: deviceUids)
            case .deviceDiscovery(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.deviceDiscovery(result: result)
            case .putUserData:
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.putUserData
            case .getUserData(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.getUserData(result: result)
            case .checkKeycloakRevocation(verificationSuccessful: let verificationSuccessful):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.checkKeycloakRevocation(verificationSuccessful: verificationSuccessful)
            case .createGroupBlob(uploadResult: let uploadResult):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.createGroupBlob(uploadResult: uploadResult)
            case .getGroupBlob(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.getGroupBlob(result: result)
            case .deleteGroupBlob(let groupDeletionWasSuccessful):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.deleteGroupBlob(groupDeletionWasSuccessful: groupDeletionWasSuccessful)
            case .putGroupLog:
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.putGroupLog
            case .requestGroupBlobLock(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.requestGroupBlobLock(result: result)
            case .updateGroupBlob(uploadResult: let uploadResult):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.updateGroupBlob(uploadResult: uploadResult)
            case .getKeycloakData(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.getKeycloakData(result: result)
            case .ownedDeviceDiscovery(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.ownedDeviceDiscovery(result: result)
            case .actionPerformedAboutOwnedDevice(success: let success):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.actionPerformedAboutOwnedDevice(success: success)
            case .sourceGetSessionNumberMessage(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.sourceGetSessionNumberMessage(result: result)
            case .targetSendEphemeralIdentity(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.targetSendEphemeralIdentity(result: result)
            case .transferRelay(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.transferRelay(result: result)
            case .transferWait(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.transferWait(result: result)
            case .sourceWaitForTargetConnection(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.sourceWaitForTargetConnection(result: result)
            case .uploadPreKeyForCurrentDevice(result: let result):
                channelServerResponseType = ObvChannelServerResponseMessageToSend.ResponseType.uploadPreKeyForCurrentDevice(result: result)
            }

            let aResponseMessageShouldBePosted: Bool
            if let listOfEncoded = [ObvEncoded](serverQuery.encodedElements), listOfEncoded.count == 0 {
                // This server query was built in ServerUserDataCoordinator#urlSession(session, task, ...) and not from a protocol, a response is not expected.
                // This happens, e.g., when refreshing an owned profile picture that expired on the server. In that case, we know there is no ongoing protocol to notify.
                aResponseMessageShouldBePosted = false
            } else {
                // This happens when the server query was created by a protocol. We need notify this protocol that it can now proceed.
                aResponseMessageShouldBePosted = true
            }

            let ownedCryptoIdentity = try serverQuery.ownedIdentity
            
            if aResponseMessageShouldBePosted {
                let serverTimestamp = Date()
                let responseMessage = ObvChannelServerResponseMessageToSend(toOwnedIdentity: ownedCryptoIdentity,
                                                                            serverTimestamp: serverTimestamp,
                                                                            responseType: channelServerResponseType,
                                                                            encodedElements: serverQuery.encodedElements,
                                                                            flowId: obvContext.flowId)

                do {
                    _ = try channelDelegate.postChannelMessage(responseMessage, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not process response to server query", log: Self.log, type: .fault)
                    return
                }
            }

            serverQuery.deletePendingServerQuery(within: obvContext)
            
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
