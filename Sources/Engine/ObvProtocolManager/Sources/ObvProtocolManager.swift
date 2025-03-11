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
import os.log
import CoreData
import ObvMetaManager
import ObvCrypto
import ObvTypes
import OlvidUtils

public final class ObvProtocolManager: ObvProtocolDelegate, ObvFullRatchetProtocolStarterDelegate {
        
    // MARK: Instance variables
    
    public var logSubsystem: String { return delegateManager.logSubsystem }
    
    public func prependLogSubsystem(with prefix: String) {
        delegateManager.prependLogSubsystem(with: prefix)
    }
    
    lazy private var log = OSLog(subsystem: logSubsystem, category: "ObvProtocolManager")
    
    private let prng: PRNGService
    
    /// Strong reference to the delegate manager, which keeps strong references to all external and internal delegate requirements.
    let delegateManager: ObvProtocolDelegateManager
    
    private static let errorDomain = "ObvProtocolManager"
    
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    // MARK: Initialiser
    public init(prng: PRNGService, downloadedUserData: URL, uploadingUserData: URL) {
        self.prng = prng
        
        let protocolInstanceInputsCoordinator = ReceivedMessageCoordinator(prng: prng)
        let protocolStarterCoordinator = ProtocolStarterCoordinator(prng: prng)
        let contactTrustLevelWatcher = ContactTrustLevelWatcher(prng: prng)
        
        delegateManager = ObvProtocolDelegateManager(downloadedUserData: downloadedUserData,
                                                     uploadingUserData: uploadingUserData,
                                                     receivedMessageDelegate: protocolInstanceInputsCoordinator,
                                                     protocolStarterDelegate: protocolStarterCoordinator,
                                                     contactTrustLevelWatcher: contactTrustLevelWatcher)
        
        protocolInstanceInputsCoordinator.delegateManager = delegateManager
        protocolStarterCoordinator.delegateManager = delegateManager
        contactTrustLevelWatcher.delegateManager = delegateManager
        
    }
    
    enum ObvError: Error {
        case channelDelegateIsNotSet
    }
    
}

// MARK: - Implementing ObvManager

extension ObvProtocolManager {
    
    public var requiredDelegates: [ObvEngineDelegateType] {
        return [ObvEngineDelegateType.ObvCreateContextDelegate,
                ObvEngineDelegateType.ObvChannelDelegate,
                ObvEngineDelegateType.ObvIdentityDelegate,
                ObvEngineDelegateType.ObvSolveChallengeDelegate,
                ObvEngineDelegateType.ObvNotificationDelegate,
                ObvEngineDelegateType.ObvNetworkPostDelegate,
                ObvEngineDelegateType.ObvNetworkFetchDelegate,
                ObvEngineDelegateType.ObvSyncSnapshotDelegate,
        ]
    }
    
    public func fulfill(requiredDelegate delegate: AnyObject, forDelegateType delegateType: ObvEngineDelegateType) throws {
        switch delegateType {
        case .ObvCreateContextDelegate:
            guard let delegate = delegate as? ObvCreateContextDelegate else {
                throw Self.makeError(message: "The ObvCreateContextDelegate is not set")
            }
            delegateManager.contextCreator = delegate
        case .ObvChannelDelegate:
            guard let delegate = delegate as? ObvChannelDelegate else {
                throw Self.makeError(message: "The ObvChannelDelegate is not set")
            }
            delegateManager.channelDelegate = delegate
        case .ObvIdentityDelegate:
            guard let delegate = delegate as? ObvIdentityDelegate else {
                throw Self.makeError(message: "The ObvIdentityDelegate is not set")
            }
            delegateManager.identityDelegate = delegate
        case .ObvNotificationDelegate:
            guard let delegate = delegate as? ObvNotificationDelegate else {
                throw Self.makeError(message: "The ObvNotificationDelegate is not set")
            }
            delegateManager.notificationDelegate = delegate
        case .ObvSolveChallengeDelegate:
            guard let delegate = delegate as? ObvSolveChallengeDelegate else {
                throw Self.makeError(message: "The ObvSolveChallengeDelegate is not set")
            }
            delegateManager.solveChallengeDelegate = delegate
        case .ObvNetworkPostDelegate:
            guard let delegate = delegate as? ObvNetworkPostDelegate else {
                throw Self.makeError(message: "The ObvNetworkPostDelegate is not set")
            }
            delegateManager.networkPostDelegate = delegate
        case .ObvNetworkFetchDelegate:
            guard let delegate = delegate as? ObvNetworkFetchDelegate else {
                throw Self.makeError(message: "The ObvNetworkFetchDelegate is not set")
            }
            delegateManager.networkFetchDelegate = delegate
        case .ObvSyncSnapshotDelegate:
            guard let delegate = delegate as? ObvSyncSnapshotDelegate else {
                throw Self.makeError(message: "The ObvSyncSnapshotDelegate is not set")
            }
            delegateManager.syncSnapshotDelegate = delegate
        default:
            throw Self.makeError(message: "Unexpected delegate type")
        }
    }
    

    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {
        delegateManager.contactTrustLevelWatcher.finalizeInitialization()
        delegateManager.protocolStarterDelegate.finalizeInitialization(flowId: flowId, runningLog: runningLog)
    }
    

    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {

        await delegateManager.contactTrustLevelWatcher.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime, flowId: flowId)

        if forTheFirstTime {
            Task(priority: .low) {
                await deleteOldUploadingUserData()
            }
            delegateManager.receivedMessageDelegate.deleteOwnedIdentityTransferProtocolInstances(flowId: flowId)
            delegateManager.receivedMessageDelegate.deleteReceivedMessagesConcerningAnOwnedIdentityTransferProtocol(flowId: flowId)
            delegateManager.receivedMessageDelegate.deleteProtocolInstancesInAFinalState(flowId: flowId)
            delegateManager.receivedMessageDelegate.deleteObsoleteReceivedMessages(flowId: flowId)
            // Now that we cleaned the databases, we can try to re-process all protocol's `ReceivedMessage`s
            delegateManager.receivedMessageDelegate.processAllReceivedMessages(flowId: flowId)
            // Replay the first step of all instances of the OwnedIdentityDeletionProtocol that are in the FirstDeletionStepPerformedState
            replayFirstStepOfAllOngoingOwnedIdentityDeletionProtocol(flowId: flowId)
        }

    }

    
    /// This method is called during boostrap. It fetches all ``OwnedIdentityDeletionProtocol`` instances in the ``FirstDeletionStepPerformedState`` and post a message
    /// allowing to re-execute this first step. Eventually, the requested deletion of the owned identity will be performed.
    ///
    /// This boostrap is performed in case the execution of the first step of the protocol posted a server query that failed. In that case, the protocol may be "stucked" in the ``FirstDeletionStepPerformedState``.
    /// Posting a message allowing to replay this step (and to re-post a server query to deactivate this device) allows to eventually properly delete the owned identity.
    func replayFirstStepOfAllOngoingOwnedIdentityDeletionProtocol(flowId: FlowIdentifier) {
        
        let delegateManager = self.delegateManager
        let prng = self.prng
        let log = self.log

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        guard let channelDelegate = delegateManager.channelDelegate else {
            os_log("The channel delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
            do {
                
                let protocolInstances = try ProtocolInstance.getAll(cryptoProtocolId: .ownedIdentityDeletionProtocol, delegateManager: delegateManager, within: obvContext)
                    .filter({ $0.currentStateRawId == OwnedIdentityDeletionProtocol.StateId.firstDeletionStepPerformed.rawValue })
                
                guard !protocolInstances.isEmpty else { return }
                
                for protocolInstance in protocolInstances {
                    
                    let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: protocolInstance.ownedCryptoIdentity),
                                                          cryptoProtocolId: .ownedIdentityDeletionProtocol,
                                                          protocolInstanceUid: protocolInstance.uid)
                    let replayMessage = OwnedIdentityDeletionProtocol.ReplayStartDeletionStepMessage(coreProtocolMessage: coreMessage)
                    guard let replayMessageToSend = replayMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        assertionFailure()
                        continue
                    }

                    _ = try channelDelegate.postChannelMessage(replayMessageToSend, randomizedWith: prng, within: obvContext)
                    
                }

                try obvContext.save(logOnFailure: log)
                
            } catch {
                os_log("Could not replay the first step of all ongoing OwnedIdentityDeletion protocols: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }
        
    }

    
    /// When updating the photo of a group v2 (for example), we copy the photo passed by the app to a storage managed by the protocol manager.
    /// This allows to make sure that the photo is available during the upload.
    /// Although the protocols using this storage should properly delete the files when they are not used anymore, we clean this directory from old files.
    private func deleteOldUploadingUserData() async {
        
        let uploadingUserData = delegateManager.uploadingUserData
        let includingPropertiesForKeys = [
            URLResourceKey.creationDateKey,
            URLResourceKey.isWritableKey,
            URLResourceKey.isRegularFileKey,
        ]
        let fileURLs: [URL]
        do {
            fileURLs = try FileManager.default.contentsOfDirectory(at: uploadingUserData, includingPropertiesForKeys: includingPropertiesForKeys, options: .skipsHiddenFiles)
        } catch {
            os_log("Could not clean old uploading user data files: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
        let dateLimit = Date(timeIntervalSinceNow: -TimeInterval(days: 15))
        assert(dateLimit < Date())
        for fileURL in fileURLs {
            guard let attributes = try? fileURL.resourceValues(forKeys: Set(includingPropertiesForKeys)) else { continue }
            guard attributes.isWritable == true else { return }
            guard attributes.isRegularFile == true else { return }
            guard let creationDate = attributes.creationDate, creationDate < dateLimit else { return }
            // If we reach this point, we should delete the file
            try? FileManager.default.removeItem(at: fileURL)
        }

    }
    
}


// MARK: - Implementing ObvFullRatchetProtocolStarterDelegate

extension ObvProtocolManager {
        
    public func startFullRatchetProtocolForObliviousChannelBetween(currentDeviceUid: UID, andRemoteDeviceUid remoteDeviceUid: UID, ofRemoteIdentity remoteIdentity: ObvCryptoIdentity) throws {
        
        os_log("Starting startFullRatchetProtocolForObliviousChannelBetween", log: log, type: .info)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        guard let channelDelegate = delegateManager.channelDelegate else {
            os_log("The channel delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        let flowId = FlowIdentifier()
        
        try contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            
            let ownedIdentity = try identityDelegate.getOwnedIdentityOfCurrentDeviceUid(currentDeviceUid, within: obvContext)
            let protocolInstanceUid = try FullRatchetProtocol.computeProtocolUid(aliceIdentity: ownedIdentity,
                                                                                 bobIdentity: remoteIdentity,
                                                                                 aliceDeviceUid: currentDeviceUid,
                                                                                 bobDeviceUid: remoteDeviceUid)

            let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                                  cryptoProtocolId: .fullRatchet,
                                                  protocolInstanceUid: protocolInstanceUid)

            let initialMessage = FullRatchetProtocol.InitialMessage(coreProtocolMessage: coreMessage,
                                                                    contactIdentity: remoteIdentity,
                                                                    contactDeviceUid: remoteDeviceUid)
            
            guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                os_log("Could create generic protocol message to send", log: log, type: .fault)
                throw ObvProtocolManager.makeError(message: "Could create generic protocol message to send")
            }

            debugPrint("🚨 Will post message for full ratchet \(obvContext.name)")
            _ = try channelDelegate.postChannelMessage(initialMessageToSend, randomizedWith: prng, within: obvContext)
            debugPrint("🚨 Did post message for full ratchet \(obvContext.name)")

            do {
                debugPrint("🚨 Will save context for full ratchet \(obvContext.name)")
                try obvContext.save(logOnFailure: log)
                debugPrint("🚨 Did save context for full ratchet \(obvContext.name)")
            } catch let error {
                debugPrint("🚨 Failed to save context for full ratchet \(obvContext.name)")
                os_log("Could not save context allowing to post a message that would start a full ratchet protocol: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                throw error
            }
             
            debugPrint("🚨 Will reach the end of scope of context \(obvContext.name)")
            
        }
        
    }

}


// MARK: - Implementing ObvProtocolDelegate

extension ObvProtocolManager {
    
    public func processProtocolReceivedMessage(_ obvProtocolReceivedMessage: ObvProtocolReceivedMessage, within obvContext: ObvContext) throws {
        
        guard let genericReceivedMessage = GenericReceivedProtocolMessage(with: obvProtocolReceivedMessage) else {
            os_log("Could not parse the protocol received message", log: log, type: .error)
            throw Self.makeError(message: "Could not parse the protocol received message")
        }
        
        save(genericReceivedMessage, within: obvContext)
        
    }
    
    
    public func process(_ obvProtocolReceivedDialogResponse: ObvProtocolReceivedDialogResponse, within obvContext: ObvContext) throws {
        
        guard let genericReceivedMessage = GenericReceivedProtocolMessage(with: obvProtocolReceivedDialogResponse) else {
            os_log("Could not parse the protocol received dialog response", log: log, type: .error)
            throw Self.makeError(message: "Could not parse the protocol received dialog response ")
        }
        
        save(genericReceivedMessage, within: obvContext)
        
    }
    
    
    public func process(_ obvProtocolReceivedServerResponse: ObvProtocolReceivedServerResponse, within obvContext: ObvContext) throws {
        
        guard let genericReceivedMessage = GenericReceivedProtocolMessage(with: obvProtocolReceivedServerResponse) else {
            os_log("Could not parse the protocol received server response", log: log, type: .error)
            throw Self.makeError(message: "Could not parse the protocol received server response")
        }
        
        save(genericReceivedMessage, within: obvContext)
        
    }
    
    private func save(_ genericReceivedMessage: GenericReceivedProtocolMessage, within obvContext: ObvContext) {
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        /* If the GenericReceivedProtocolMessage has a non-nil receivedMessageUID (which is the case when it was downloaded from the server),
         * we make sure it does not already exist in database before creating it (otherwise, Core Data would raise an error when saving the context,
         * preventing in particular received network messages to be marked for deletion).
         */
        
        let receivedMessage: ReceivedMessage
        
        if let receivedMessageUID = genericReceivedMessage.receivedMessageUID {
            let messageId = ObvMessageIdentifier(ownedCryptoIdentity: genericReceivedMessage.toOwnedIdentity, uid: receivedMessageUID)
            if let existingReceivedMessage = ReceivedMessage.get(messageId: messageId, delegateManager: delegateManager, within: obvContext) {
                os_log("A ReceivedMessage with messageId %{public}@ already exist, we do not try to create a new one", log: log, type: .info, messageId.debugDescription)
                receivedMessage = existingReceivedMessage
            } else {
                os_log("No previous ReceivedMessage with messageId %{public}@ was found, we create it now", log: log, type: .info, messageId.debugDescription)
                let createdReceivedMessage = ReceivedMessage(with: genericReceivedMessage, using: prng, delegateManager: delegateManager, within: obvContext)
                receivedMessage = createdReceivedMessage
            }
        } else {
            os_log("We are processing a generic received message without messageId (thus, not downloaded from the network). We create a new ReceivedMessage in database", log: log, type: .info)
            let createdReceivedMessage = ReceivedMessage(with: genericReceivedMessage, using: prng, delegateManager: delegateManager, within: obvContext)
            receivedMessage = createdReceivedMessage
        }
        
        // We notify that a new received message (due to a protocol received message) needs to be processed
        
        do {
            try obvContext.addContextDidSaveCompletionHandler { (error) in
                guard error == nil else { return }
                ObvProtocolNotification.protocolMessageToProcess(protocolMessageId: receivedMessage.messageId, flowId: obvContext.flowId)
                    .postOnBackgroundQueue(within: notificationDelegate)
            }
        } catch {
            assertionFailure()
            os_log("Could not send ProtocolMessageToProcess notification: %{public}@", log: log, type: .fault, error.localizedDescription)
        }
        
    }
    
    
    public func getInitialMessageForIdentityDetailsPublicationProtocol(ownedIdentity: ObvCryptoIdentity, publishedIdentityDetailsVersion version: Int) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitialMessageForIdentityDetailsPublicationProtocol(ownedIdentity: ownedIdentity, publishedIdentityDetailsVersion: version)
    }
    
    
    public func getInitialMessageForTrustEstablishmentProtocol(of contactIdentity: ObvCryptoIdentity, withFullDisplayName contactFullDisplayName: String, forOwnedIdentity ownedIdentity: ObvCryptoIdentity, withOwnedIdentityCoreDetails ownedIdentityDetails: ObvIdentityCoreDetails) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitialMessageForTrustEstablishmentProtocol(of: contactIdentity,
                                                                                                          withFullDisplayName: contactFullDisplayName,
                                                                                                          forOwnedIdentity: ownedIdentity,
                                                                                                          withOwnedIdentityCoreDetails: ownedIdentityDetails)
    }
    
    
    public func abortProtocol(withProtocolInstanceUid uid: UID, forOwnedIdentity identity: ObvCryptoIdentity) throws {
        delegateManager.receivedMessageDelegate.abortProtocol(withProtocolInstanceUid: uid, forOwnedIdentity: identity)
    }
    
    
    public func getInitiateGroupCreationMessageForGroupManagementProtocol(groupCoreDetails: ObvGroupCoreDetails, photoURL: URL?, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>, ownedIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateGroupCreationMessageForGroupManagementProtocol(
            groupCoreDetails: groupCoreDetails,
            photoURL: photoURL,
            pendingGroupMembers: pendingGroupMembers,
            ownedIdentity: ownedIdentity)
    }
    
    
    public func getDisbandGroupMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getDisbandGroupMessageForGroupManagementProtocol(
            groupUid: groupUid,
            ownedIdentity: ownedIdentity,
            within: obvContext)
    }

    
    public func getInitialMessageForChannelCreationWithContactDeviceProtocol(betweenTheCurrentDeviceOfOwnedIdentity ownedIdentity: ObvCryptoIdentity, andTheDeviceUid contactDeviceUid: UID, ofTheContactIdentity contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitialMessageForChannelCreationWithContactDeviceProtocol(betweenTheCurrentDeviceOfOwnedIdentity: ownedIdentity, andTheDeviceUid: contactDeviceUid, ofTheContactIdentity: contactIdentity)
    }
    
    
    public func getInitialMessageForChannelCreationWithOwnedDeviceProtocol(ownedIdentity: ObvCryptoIdentity, remoteDeviceUid: UID) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitialMessageForChannelCreationWithOwnedDeviceProtocol(ownedIdentity: ownedIdentity, remoteDeviceUid: remoteDeviceUid)
    }

    
    public func getInitialMessageForContactMutualIntroductionProtocol(of identity1: ObvCryptoIdentity, with identity2: ObvCryptoIdentity, byOwnedIdentity ownedIdentity: ObvCryptoIdentity, usingProtocolInstanceUid protocolInstanceUid: UID) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitialMessageForContactMutualIntroductionProtocol(of: identity1,
                                                                                                                 with: identity2,
                                                                                                                 byOwnedIdentity: ownedIdentity,
                                                                                                                 usingProtocolInstanceUid: protocolInstanceUid)
    }
    
    
    public func getOwnedGroupMembersChangedTriggerMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getOwnedGroupMembersChangedTriggerMessageForGroupManagementProtocol(groupUid: groupUid, ownedIdentity: ownedIdentity, within: obvContext)
    }
    
    
    public func getAddGroupMembersMessageForAddingMembersToContactGroupOwned(groupUid: UID, ownedIdentity: ObvCryptoIdentity, newGroupMembers: Set<ObvCryptoIdentity>, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getAddGroupMembersMessageForAddingMembersToContactGroupOwnedUsingGroupManagementProtocol(groupUid: groupUid,
                                                                                                                                                    ownedIdentity: ownedIdentity,
                                                                                                                                                    newGroupMembers: newGroupMembers,
                                                                                                                                                    within: obvContext)
    }
    
    
    public func getRemoveGroupMembersMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, removedGroupMembers: Set<ObvCryptoIdentity>, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getRemoveGroupMembersMessageForGroupManagementProtocol(groupUid: groupUid,
                                                                                                                  ownedIdentity: ownedIdentity,
                                                                                                                  removedGroupMembers: removedGroupMembers,
                                                                                                                  within: obvContext)
    }
    
    
    public func getLeaveGroupJoinedMessageForGroupManagementProtocol(ownedIdentity: ObvCryptoIdentity, groupUid: UID, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getLeaveGroupJoinedMessageForGroupManagementProtocol(ownedIdentity: ownedIdentity,
                                                                                                                groupUid: groupUid,
                                                                                                                groupOwner: groupOwner,
                                                                                                                within: obvContext)
    }
    
    
    public func getInitiateContactDeletionMessageForContactManagementProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentityToDelete contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateContactDeletionMessageForContactManagementProtocol(ownedIdentity: ownedIdentity, contactIdentityToDelete: contactIdentity)
    }
    
    public func getInitiateAddKeycloakContactMessageForKeycloakContactAdditionProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentityToAdd contactIdentity: ObvCryptoIdentity, signedContactDetails: String) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateAddKeycloakContactMessageForKeycloakContactAdditionProtocol(ownedIdentity: ownedIdentity, contactIdentityToAdd: contactIdentity, signedContactDetails: signedContactDetails)
    }
    
    public func getInitiateGroupMembersQueryMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, groupOwner: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateGroupMembersQueryMessageForGroupManagementProtocol(groupUid: groupUid, ownedIdentity: ownedIdentity, groupOwner: groupOwner, within: obvContext)
    }
    
    
    public func getTriggerReinviteMessageForGroupManagementProtocol(groupUid: UID, ownedIdentity: ObvCryptoIdentity, memberIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getTriggerReinviteMessageForGroupManagementProtocol(groupUid: groupUid, ownedIdentity: ownedIdentity, memberIdentity: memberIdentity, within: obvContext)
    }
    
    
    public func getInitialMessageForContactDeviceDiscoveryProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitialMessageForContactDeviceDiscoveryProtocol(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity)
    }
    
    
    public func getAllObliviousChannelIdentifiersHavingARunningChannelCreationWithContactDeviceProtocolInstances(within obvContext: ObvContext) throws -> Set<ObliviousChannelIdentifierAlt> {
        return try ChannelCreationWithContactDeviceProtocolInstance.getAll(within: obvContext)
    }

    public func getAllObliviousChannelIdentifiersHavingARunningChannelCreationWithOwnedDeviceProtocolInstances(within obvContext: ObvContext) throws -> Set<ObliviousChannelIdentifierAlt> {
        return try ChannelCreationWithOwnedDeviceProtocolInstance.getAll(within: obvContext)
    }

    public func getInitialMessageForDownloadIdentityPhotoChildProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactIdentityDetailsElements: IdentityDetailsElements) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitialMessageForDownloadIdentityPhotoChildProtocol(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, contactIdentityDetailsElements: contactIdentityDetailsElements)
    }
    
    public func getInitialMessageForDownloadGroupPhotoChildProtocol(ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitialMessageForDownloadGroupPhotoChildProtocol(ownedIdentity: ownedIdentity, groupInformation: groupInformation)
    }
    
    public func getInitialMessageForTrustEstablishmentWithMutualScanProtocol(ownedIdentity: ObvCryptoIdentity, remoteIdentity: ObvCryptoIdentity, signature: Data) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitialMessageForTrustEstablishmentWithMutualScanProtocol(ownedIdentity: ownedIdentity, remoteIdentity: remoteIdentity, signature: signature)
    }
    
    public func getInitialMessageForAddingOwnCapabilities(ownedIdentity: ObvCryptoIdentity, newOwnCapabilities: Set<ObvCapability>) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitialMessageForAddingOwnCapabilities(
            ownedIdentity: ownedIdentity,
            newOwnCapabilities: newOwnCapabilities)
    }
    
    public func getInitialMessageForOneToOneContactInvitationProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitialMessageForOneToOneContactInvitationProtocol(
            ownedIdentity: ownedIdentity,
            contactIdentity: contactIdentity)
    }
    
    public func getInitialMessageForDowngradingOneToOneContact(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitialMessageForDowngradingOneToOneContact(
            ownedIdentity: ownedIdentity,
            contactIdentity: contactIdentity)
    }
    
    public func getInitialMessageForOneStatusSyncRequest(ownedIdentity: ObvCryptoIdentity, contactsToSync: Set<ObvCryptoIdentity>) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitialMessageForOneStatusSyncRequest(ownedIdentity: ownedIdentity, contactsToSync: contactsToSync)
    }
    
    public func getInitiateGroupCreationMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, ownRawPermissions: Set<String>, otherGroupMembers: Set<GroupV2.IdentityAndPermissions>, serializedGroupCoreDetails: Data, photoURL: URL?, serializedGroupType: Data) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateGroupCreationMessageForGroupV2Protocol(ownedIdentity: ownedIdentity, ownRawPermissions: ownRawPermissions, otherGroupMembers: otherGroupMembers, serializedGroupCoreDetails: serializedGroupCoreDetails, photoURL: photoURL, serializedGroupType: serializedGroupType)
    }
    
    public func getInitiateGroupUpdateMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, changeset: ObvGroupV2.Changeset) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateGroupUpdateMessageForGroupV2Protocol(ownedIdentity: ownedIdentity, groupIdentifier: groupIdentifier, changeset: changeset)
    }
    
    public func getInitialMessageForDownloadGroupV2PhotoProtocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, serverPhotoInfo: GroupV2.ServerPhotoInfo) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitialMessageForDownloadGroupV2PhotoProtocol(ownedIdentity: ownedIdentity, groupIdentifier: groupIdentifier, serverPhotoInfo: serverPhotoInfo)
    }
    
    public func getInitiateGroupLeaveMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateGroupLeaveMessageForGroupV2Protocol(ownedIdentity: ownedIdentity, groupIdentifier: groupIdentifier)
    }
    
    public func getInitiateGroupReDownloadMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateGroupReDownloadMessageForGroupV2Protocol(ownedIdentity: ownedIdentity, groupIdentifier: groupIdentifier)
    }
    
    public func getInitiateInitiateGroupDisbandMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateInitiateGroupDisbandMessageForGroupV2Protocol(ownedIdentity: ownedIdentity, groupIdentifier: groupIdentifier)
    }
    
    /// When a channel is (re)created with a contact device, the engine will call this method so as to make sure our contact knows about the group informations we have about groups v2 that we have in common.
    public func getInitiateBatchKeysResendMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, remoteIdentity: ObvCryptoIdentity, remoteDeviceUID: UID, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateBatchKeysResendMessageForGroupV2Protocol(ownedIdentity: ownedIdentity, remoteIdentity: remoteIdentity, remoteDeviceUID: remoteDeviceUID, flowId: flowId)
        
    }
    
    // MARK: - Keycloak pushed groups

    public func getInitiateUpdateKeycloakGroupsMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, signedGroupBlobs: Set<String>, signedGroupDeletions: Set<String>, signedGroupKicks: Set<String>, keycloakCurrentTimestamp: Date) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateUpdateKeycloakGroupsMessageForGroupV2Protocol(
            ownedIdentity: ownedIdentity,
            signedGroupBlobs: signedGroupBlobs,
            signedGroupDeletions: signedGroupDeletions,
            signedGroupKicks: signedGroupKicks,
            keycloakCurrentTimestamp: keycloakCurrentTimestamp)
    }
    
    
    public func getInitiateTargetedPingMessageForKeycloakGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, pendingMemberIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateTargetedPingMessageForKeycloakGroupV2Protocol(
            ownedIdentity: ownedIdentity,
            groupIdentifier: groupIdentifier,
            pendingMemberIdentity: pendingMemberIdentity,
            flowId: flowId)
    }
    
    
    // MARK: - Owned identities
        
    public func getInitiateOwnedIdentityDeletionMessage(ownedCryptoIdentityToDelete: ObvCryptoIdentity, globalOwnedIdentityDeletion: Bool) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateOwnedIdentityDeletionMessage(ownedCryptoIdentityToDelete: ownedCryptoIdentityToDelete, globalOwnedIdentityDeletion: globalOwnedIdentityDeletion)
    }
    
    public func getInitiateOwnedDeviceDiscoveryMessage(ownedCryptoIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateOwnedDeviceDiscoveryMessage(ownedCryptoIdentity: ownedCryptoIdentity)
    }

    
    public func getInitiateOwnedDeviceManagementMessage(ownedCryptoIdentity: ObvCryptoIdentity, request: ObvOwnedDeviceManagementRequest) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateOwnedDeviceManagementMessage(ownedCryptoIdentity: ownedCryptoIdentity, request: request)
    }
    
    // MARK: - Keycloak binding and unbinding
    
    public func getOwnedIdentityKeycloakBindingMessage(ownedCryptoIdentity: ObvCryptoIdentity, keycloakState: ObvKeycloakState, keycloakUserId: String) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getOwnedIdentityKeycloakBindingMessage(
            ownedCryptoIdentity: ownedCryptoIdentity,
            keycloakState: keycloakState,
            keycloakUserId: keycloakUserId)
    }
    
    public func getOwnedIdentityKeycloakUnbindingMessage(ownedCryptoIdentity: ObvCryptoIdentity, isUnbindRequestByUser: Bool) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getOwnedIdentityKeycloakUnbindingMessage(ownedCryptoIdentity: ownedCryptoIdentity, isUnbindRequestByUser: isUnbindRequestByUser)
    }
    
    
    // MARK: - SynchronizationProtocol
    
    public func getInitiateSyncAtomMessageForSynchronizationProtocol(ownedCryptoIdentity: ObvCryptoIdentity, syncAtom: ObvSyncAtom) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateSyncAtomMessageForSynchronizationProtocol(ownedCryptoIdentity: ownedCryptoIdentity, syncAtom: syncAtom)
    }
    
    
//    public func sendTriggerSyncSnapshotMessageToAllExistingSynchronizationProtocolInstances(within obvContext: ObvContext) throws {
//        guard let channelDelegate = delegateManager.channelDelegate else {
//            throw ObvError.channelDelegateIsNotSet
//        }
//        let currentSynchronizationProtocolInstances = try ProtocolInstance.getAll(cryptoProtocolId: .synchronization, delegateManager: delegateManager, within: obvContext)
//        for protocolInstance in currentSynchronizationProtocolInstances {
//            let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: protocolInstance.ownedCryptoIdentity),
//                                                  cryptoProtocolId: .synchronization,
//                                                  protocolInstanceUid: protocolInstance.uid)
//            let message = SynchronizationProtocol.TriggerSyncSnapshotMessage(coreProtocolMessage: coreMessage, forceSendSnapshot: false)
//            guard let messageToSend = message.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); continue }
//            _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
//        }
//    }
    
    
//    public func getTriggerSyncSnapshotMessageForSynchronizationProtocol(ownedCryptoIdentity: ObvCryptoIdentity, currentDeviceUid: UID, otherOwnedDeviceUid: UID, forceSendSnapshot: Bool) throws -> ObvChannelProtocolMessageToSend {
//        return try delegateManager.protocolStarterDelegate.getTriggerSyncSnapshotMessageForSynchronizationProtocol(ownedCryptoIdentity: ownedCryptoIdentity, currentDeviceUid: currentDeviceUid, otherOwnedDeviceUid: otherOwnedDeviceUid, forceSendSnapshot: forceSendSnapshot)
//    }
    
    
//    public func getInitiateSyncSnapshotMessageForSynchronizationProtocol(ownedCryptoIdentity: ObvCryptoIdentity, currentDeviceUid: UID, otherOwnedDeviceUid: UID) throws -> ObvChannelProtocolMessageToSend {
//        return try delegateManager.protocolStarterDelegate.getInitiateSyncSnapshotMessageForSynchronizationProtocol(ownedCryptoIdentity: ownedCryptoIdentity, currentDeviceUid: currentDeviceUid, otherOwnedDeviceUid: otherOwnedDeviceUid)
//    }

    
    // MARK: - Owned identity transfer protocol

    public func initiateOwnedIdentityTransferProtocolOnSourceDevice(ownedCryptoIdentity: ObvCryptoIdentity, onAvailableSessionNumber: @MainActor @escaping (ObvOwnedIdentityTransferSessionNumber) -> Void, onAvailableSASExpectedOnInput: @MainActor @escaping (ObvOwnedIdentityTransferSas, String, UID) -> Void, flowId: FlowIdentifier) async throws {
        try await delegateManager.protocolStarterDelegate.initiateOwnedIdentityTransferProtocolOnSourceDevice(
            ownedCryptoIdentity: ownedCryptoIdentity,
            onAvailableSessionNumber: onAvailableSessionNumber,
            onAvailableSASExpectedOnInput: onAvailableSASExpectedOnInput,
            flowId: flowId)
    }

    public func initiateOwnedIdentityTransferProtocolOnTargetDevice(currentDeviceName: String, transferSessionNumber: ObvOwnedIdentityTransferSessionNumber, onIncorrectTransferSessionNumber: @escaping () -> Void, onAvailableSas: @escaping (UID, ObvOwnedIdentityTransferSas) -> Void, flowId: FlowIdentifier) async throws {
        try await delegateManager.protocolStarterDelegate.initiateOwnedIdentityTransferProtocolOnTargetDevice(
            currentDeviceName: currentDeviceName,
            transferSessionNumber: transferSessionNumber,
            onIncorrectTransferSessionNumber: onIncorrectTransferSessionNumber,
            onAvailableSas: onAvailableSas,
            flowId: flowId)
    }
    
    public func appIsShowingSasAndExpectingEndOfProtocol(protocolInstanceUID: ObvCrypto.UID, onSyncSnapshotReception: @escaping () -> Void, onSuccessfulTransfer: @escaping (ObvTypes.ObvCryptoId, (any Error)?) -> Void, onKeycloakAuthenticationNeeded: @escaping (ObvTypes.ObvCryptoId, ObvTypes.ObvKeycloakConfiguration, ObvTypes.ObvKeycloakTransferProofElements) -> Void) async {
        await delegateManager.protocolStarterDelegate.appIsShowingSasAndExpectingEndOfProtocol(
            protocolInstanceUID: protocolInstanceUID,
            onSyncSnapshotReception: onSyncSnapshotReception,
            onSuccessfulTransfer: onSuccessfulTransfer,
            onKeycloakAuthenticationNeeded: onKeycloakAuthenticationNeeded)
    }
    
    
    public func continueOwnedIdentityTransferProtocolOnUserEnteredSASOnSourceDevice(enteredSAS: ObvOwnedIdentityTransferSas, isTransferRestricted: Bool, deviceToKeepActive: UID?, ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID, snapshotSentToTargetDevice: @escaping () -> Void) async throws {
        try await delegateManager.protocolStarterDelegate.continueOwnedIdentityTransferProtocolOnUserEnteredSASOnSourceDevice(
            enteredSAS: enteredSAS,
            isTransferRestricted: isTransferRestricted,
            deviceToKeepActive: deviceToKeepActive,
            ownedCryptoId: ownedCryptoId,
            protocolInstanceUID: protocolInstanceUID,
            snapshotSentToTargetDevice: snapshotSentToTargetDevice)
    }
 
    
    public func cancelAllOwnedIdentityTransferProtocols(flowId: FlowIdentifier) async throws {
        try await delegateManager.protocolStarterDelegate.cancelAllOwnedIdentityTransferProtocols(flowId: flowId)
    }
    
    
    public func continueOwnedIdentityTransferProtocolOnUserProvidesProofOfAuthenticationOnKeycloakServer(ownedCryptoId: ObvTypes.ObvCryptoId, protocolInstanceUID: ObvCrypto.UID, proof: ObvTypes.ObvKeycloakTransferProofAndAuthState) async throws {
        try await delegateManager.protocolStarterDelegate.continueOwnedIdentityTransferProtocolOnUserProvidesProofOfAuthenticationOnKeycloakServer(
            ownedCryptoId: ownedCryptoId,
            protocolInstanceUID: protocolInstanceUID,
            proof: proof)
    }
    
}


// MARK: - Allow to execute external operations on the queue executing protocol steps

extension ObvProtocolManager {
    
    public func executeOnQueueForProtocolOperations<ReasonForCancelType: LocalizedErrorWithLogType>(operation: OperationWithSpecificReasonForCancel<ReasonForCancelType>) async throws {
        try await delegateManager.receivedMessageDelegate.executeOnQueueForProtocolOperations(operation: operation)
    }
    
}
