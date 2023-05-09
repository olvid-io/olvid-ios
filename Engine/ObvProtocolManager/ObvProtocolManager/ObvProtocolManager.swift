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
    
}

// MARK: - Implementing ObvManager

extension ObvProtocolManager {
    
    public var requiredDelegates: [ObvEngineDelegateType] {
        return [ObvEngineDelegateType.ObvCreateContextDelegate,
                ObvEngineDelegateType.ObvChannelDelegate,
                ObvEngineDelegateType.ObvIdentityDelegate,
                ObvEngineDelegateType.ObvSolveChallengeDelegate,
                ObvEngineDelegateType.ObvNotificationDelegate]
    }
    
    public func fulfill(requiredDelegate delegate: AnyObject, forDelegateType delegateType: ObvEngineDelegateType) throws {
        switch delegateType {
        case .ObvCreateContextDelegate:
            guard let delegate = delegate as? ObvCreateContextDelegate else { throw NSError() }
            delegateManager.contextCreator = delegate
        case .ObvChannelDelegate:
            guard let delegate = delegate as? ObvChannelDelegate else { throw NSError() }
            delegateManager.channelDelegate = delegate
        case .ObvIdentityDelegate:
            guard let delegate = delegate as? ObvIdentityDelegate else { throw NSError() }
            delegateManager.identityDelegate = delegate
        case .ObvNotificationDelegate:
            guard let delegate = delegate as? ObvNotificationDelegate else { throw NSError() }
            delegateManager.notificationDelegate = delegate
        case .ObvSolveChallengeDelegate:
            guard let delegate = delegate as? ObvSolveChallengeDelegate else { throw NSError() }
            delegateManager.solveChallengeDelegate = delegate
        default:
            throw Self.makeError(message: "Unexpected delegate type")
        }
    }
    

    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {
        delegateManager.contactTrustLevelWatcher.finalizeInitialization()
    }
    

    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {

        await delegateManager.contactTrustLevelWatcher.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime, flowId: flowId)

        if forTheFirstTime {
            Task(priority: .low) {
                await deleteOldUploadingUserData()
            }
            delegateManager.receivedMessageDelegate.deleteProtocolInstancesInAFinalState(flowId: flowId)
            delegateManager.receivedMessageDelegate.deleteObsoleteReceivedMessages(flowId: flowId)
            // Now that we cleaned the databases, we can try to re-process all protocol's `ReceivedMessage`s
            delegateManager.receivedMessageDelegate.processAllReceivedMessages(flowId: flowId)
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

            let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                                  cryptoProtocolId: .FullRatchet,
                                                  protocolInstanceUid: protocolInstanceUid)

            let initialMessage = FullRatchetProtocol.InitialMessage(coreProtocolMessage: coreMessage,
                                                                    contactIdentity: remoteIdentity,
                                                                    contactDeviceUid: remoteDeviceUid)
            
            guard let initialMessageToSend = initialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                os_log("Could create generic protocol message to send", log: log, type: .fault)
                throw ObvProtocolManager.makeError(message: "Could create generic protocol message to send")
            }

            debugPrint("🚨 Will post message for full ratchet \(obvContext.name)")
            _ = try channelDelegate.post(initialMessageToSend, randomizedWith: prng, within: obvContext)
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
            let messageId = MessageIdentifier(ownedCryptoIdentity: genericReceivedMessage.toOwnedIdentity, uid: receivedMessageUID)
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
    
    
    public func getInitialMessageForTrustEstablishmentProtocol(of contactIdentity: ObvCryptoIdentity, withFullDisplayName contactFullDisplayName: String, forOwnedIdentity ownedIdentity: ObvCryptoIdentity, withOwnedIdentityCoreDetails ownedIdentityDetails: ObvIdentityCoreDetails, usingProtocolInstanceUid protocolInstanceUid: UID) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitialMessageForTrustEstablishmentProtocol(of: contactIdentity,
                                                                                                          withFullDisplayName: contactFullDisplayName,
                                                                                                          forOwnedIdentity: ownedIdentity,
                                                                                                          withOwnedIdentityCoreDetails: ownedIdentityDetails,
                                                                                                          usingProtocolInstanceUid: protocolInstanceUid)
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
    
    
    public func getInitialMessageForChannelCreationWithContactDeviceProtocol(betweenTheCurrentDeviceOfOwnedIdentity ownedIdentity: ObvCryptoIdentity, andTheDeviceUid contactDeviceUid: UID, ofTheContactIdentity contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitialMessageForChannelCreationWithContactDeviceProtocol(betweenTheCurrentDeviceOfOwnedIdentity: ownedIdentity, andTheDeviceUid: contactDeviceUid, ofTheContactIdentity: contactIdentity)
    }
    
    
    public func getInitialMessageForContactMutualIntroductionProtocol(of contact1: ObvCryptoIdentity, withContactIdentityCoreDetails contactCoreDetails1: ObvIdentityCoreDetails, with contact2: ObvCryptoIdentity, withOtherContactIdentityCoreDetails contactCoreDetails2: ObvIdentityCoreDetails, byOwnedIdentity ownedIdentity: ObvCryptoIdentity, usingProtocolInstanceUid protocolInstanceUid: UID) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitialMessageForContactMutualIntroductionProtocol(of: contact1,
                                                                                                                 withIdentityCoreDetails: contactCoreDetails1,
                                                                                                                 with: contact2,
                                                                                                                 withOtherIdentityCoreDetails: contactCoreDetails2,
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
    
    
    public func getInitialMessageForDeviceDiscoveryForContactIdentityProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitialMessageForDeviceDiscoveryForContactIdentityProtocol(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity)
    }
    
    
    public func getAllObliviousChannelIdentifiersHavingARunningChannelCreationWithContactDeviceProtocolInstances(within obvContext: ObvContext) throws -> Set<ObliviousChannelIdentifierAlt> {
        return try ChannelCreationWithContactDeviceProtocolInstance.getAll(within: obvContext)
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
    
    public func getInitiateGroupCreationMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, ownRawPermissions: Set<String>, otherGroupMembers: Set<GroupV2.IdentityAndPermissions>, serializedGroupCoreDetails: Data, photoURL: URL?, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateGroupCreationMessageForGroupV2Protocol(ownedIdentity: ownedIdentity, ownRawPermissions: ownRawPermissions, otherGroupMembers: otherGroupMembers, serializedGroupCoreDetails: serializedGroupCoreDetails, photoURL: photoURL, flowId: flowId)
    }
    
    public func getInitiateGroupUpdateMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, changeset: ObvGroupV2.Changeset, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateGroupUpdateMessageForGroupV2Protocol(ownedIdentity: ownedIdentity, groupIdentifier: groupIdentifier, changeset: changeset, flowId: flowId)
    }
    
    public func getInitiateGroupLeaveMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateGroupLeaveMessageForGroupV2Protocol(ownedIdentity: ownedIdentity, groupIdentifier: groupIdentifier, flowId: flowId)
    }
    
    public func getInitiateGroupReDownloadMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateGroupReDownloadMessageForGroupV2Protocol(ownedIdentity: ownedIdentity, groupIdentifier: groupIdentifier, flowId: flowId)
    }
    
    public func getInitiateInitiateGroupDisbandMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateInitiateGroupDisbandMessageForGroupV2Protocol(ownedIdentity: ownedIdentity, groupIdentifier: groupIdentifier, flowId: flowId)
    }
    
    /// When a channel is (re)created with a contact device, the engine will call this method so as to make sure our contact knows about the group informations we have about groups v2 that we have in common.
    public func getInitiateBatchKeysResendMessageForGroupV2Protocol(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactDeviceUID: UID, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateBatchKeysResendMessageForGroupV2Protocol(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, contactDeviceUID: contactDeviceUID, flowId: flowId)
        
    }
    
    // MARK: - Owned identities
    
    /// Called when an owned identity is about to be deleted.
    public func prepareForOwnedIdentityDeletion(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        // Delete all received messages
        
        try ReceivedMessage.batchDeleteAllReceivedMessagesForOwnedCryptoIdentity(ownedCryptoIdentity, within: obvContext)
        
        // Delete signatures, commitments,... received relating to this owned identity
        
        try ChannelCreationPingSignatureReceived.batchDeleteAllChannelCreationPingSignatureReceivedForOwnedCryptoIdentity(ownedCryptoIdentity, within: obvContext)
        try TrustEstablishmentCommitmentReceived.batchDeleteAllTrustEstablishmentCommitmentReceivedForOwnedCryptoIdentity(ownedCryptoIdentity, within: obvContext)
        try MutualScanSignatureReceived.batchDeleteAllMutualScanSignatureReceivedForOwnedCryptoIdentity(ownedCryptoIdentity, within: obvContext)
        try GroupV2SignatureReceived.deleteAllAssociatedWithOwnedIdentity(ownedCryptoIdentity, within: obvContext)
        try ContactOwnedIdentityDeletionSignatureReceived.deleteAllAssociatedWithOwnedIdentity(ownedCryptoIdentity, within: obvContext)
        
    }
    
    public func getInitiateOwnedIdentityDeletionMessage(ownedCryptoIdentityToDelete: ObvCryptoIdentity, notifyContacts: Bool, flowId: FlowIdentifier) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateOwnedIdentityDeletionMessage(ownedCryptoIdentityToDelete: ownedCryptoIdentityToDelete, notifyContacts: notifyContacts, flowId: flowId)
    }
    
}
