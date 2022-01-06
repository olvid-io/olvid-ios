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

    public func applicationDidStartRunning(flowId: FlowIdentifier) {}
    public func applicationDidEnterBackground() {}
    
    private let prng: PRNGService
    
    /// Strong reference to the delegate manager, which keeps strong references to all external and internal delegate requirements.
    let delegateManager: ObvProtocolDelegateManager
    
    private static let errorDomain = "ObvProtocolManager"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    // MARK: Initialiser
    public init(prng: PRNGService, downloadedUserData: URL) {
        self.prng = prng
        
        let protocolInstanceInputsCoordinator = ReceivedMessageCoordinator(prng: prng)
        let protocolStarterCoordinator = ProtocolStarterCoordinator(prng: prng)
        let contactTrustLevelWatcher = ContactTrustLevelWatcher(prng: prng)
        
        delegateManager = ObvProtocolDelegateManager(downloadedUserData: downloadedUserData,
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
            throw NSError()
        }
    }
    
    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {
        
        delegateManager.contactTrustLevelWatcher.finalizeInitialization()
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            return
        }
        
        let log = self.log
        
        contextCreator.performBackgroundTask(flowId: flowId) { [weak self] (obvContext) in

            guard let _self = self else { return }
            
            let receivedMessages: [ReceivedMessage]
            do {
                receivedMessages = try ReceivedMessage.getAll(delegateManager: _self.delegateManager, within: obvContext)
            } catch {
                os_log("Could not get all received messages in finalizeInitialization", log: _self.log, type: .fault)
                return
            }

            // Delete all received messages that are older than 15 days and that have no associated protocol instance. All other messages should be processed
            
            let fifteenDays = TimeInterval(1_296_000)
            let oldDate = Date(timeIntervalSinceNow: -fifteenDays)
            assert(oldDate < Date())

            let messagesToDelete = receivedMessages.filter { (message) in
                guard message.timestamp < oldDate else { return false }
                do {
                    return try !ProtocolInstance.exists(cryptoProtocolId: message.cryptoProtocolId, uid: message.protocolInstanceUid, ownedIdentity: message.messageId.ownedCryptoIdentity, within: obvContext)
                } catch {
                    assertionFailure()
                    return false
                }
            }

            os_log("We have %d old protocol messages to delete", log: log, type: .info, messagesToDelete.count)
            
            var contextNeedsToBeSaved = false
            
            for message in receivedMessages {
                if messagesToDelete.contains(message) {
                    obvContext.delete(message)
                    contextNeedsToBeSaved = true
                } else {
                    _self.delegateManager.receivedMessageDelegate.processReceivedMessage(withId: message.messageId, flowId: flowId)
                }
            }
            
            if contextNeedsToBeSaved {
                try? obvContext.save(logOnFailure: log)
            }
            
        }
        
        
    }
}


// MARK: - Implementing ObvFullRatchetProtocolStarterDelegate

extension ObvProtocolManager {
    
    
    public func deleteProtocolMetadataRelatingToContact(contactIdentity: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        try ChannelCreationPingSignatureReceived.deleteAllAssociatedWithContactIdentity(contactIdentity, ownedIdentity: ownedIdentity, within: obvContext)
    }
    
    
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

            _ = try channelDelegate.post(initialMessageToSend, randomizedWith: prng, within: obvContext)
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not save context allowing to post a message that would start a full ratchet protocol: %{public}@", log: log, type: .fault, error.localizedDescription)
                throw error
            }
                        
        }
        
    }

}


// MARK: - Implementing ObvProtocolDelegate

extension ObvProtocolManager {
    
    public func process(_ obvProtocolReceivedMessage: ObvProtocolReceivedMessage, within obvContext: ObvContext) throws {
        
        guard let genericReceivedMessage = GenericReceivedProtocolMessage(with: obvProtocolReceivedMessage) else {
            os_log("Could not parse the protocol received message", log: log, type: .error)
            throw NSError()
        }
        
        save(genericReceivedMessage, within: obvContext)
        
    }
    
    
    public func process(_ obvProtocolReceivedDialogResponse: ObvProtocolReceivedDialogResponse, within obvContext: ObvContext) throws {
        
        guard let genericReceivedMessage = GenericReceivedProtocolMessage(with: obvProtocolReceivedDialogResponse) else {
            os_log("Could not parse the protocol received dialog response ", log: log, type: .error)
            throw NSError()
        }

        save(genericReceivedMessage, within: obvContext)

    }
    
    
    public func process(_ obvProtocolReceivedServerResponse: ObvProtocolReceivedServerResponse, within obvContext: ObvContext) throws {
        
        guard let genericReceivedMessage = GenericReceivedProtocolMessage(with: obvProtocolReceivedServerResponse) else {
            os_log("Could not parse the protocol received dialog response ", log: log, type: .error)
            throw NSError()
        }
        
        save(genericReceivedMessage, within: obvContext)

    }
    
    private func save(_ genericReceivedMessage: GenericReceivedProtocolMessage, within obvContext: ObvContext) {
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }
        
        let receivedMessage = ReceivedMessage(with: genericReceivedMessage, using: prng, delegateManager: delegateManager, within: obvContext)
        
        // We notify that a new received message (due to a protocol received message) needs to be processed
        
        do {
            try obvContext.addContextDidSaveCompletionHandler { (error) in
                guard error == nil else { return }
                let NotificationType = ObvProtocolNotification.ProtocolMessageToProcess.self
                let userInfo = [NotificationType.Key.protocolMessageId: receivedMessage.messageId,
                                NotificationType.Key.flowId: obvContext.flowId] as [String: Any]
                notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
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
 
    
    public func getInitiateContactDeletionMessageForObliviousChannelManagementProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentityToDelete contactIdentity: ObvCryptoIdentity) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateContactDeletionMessageForObliviousChannelManagementProtocol(ownedIdentity: ownedIdentity, contactIdentityToDelete: contactIdentity)
    }

    public func getInitiateAddKeycloakContactMessageForObliviousChannelManagementProtocol(ownedIdentity: ObvCryptoIdentity, contactIdentityToAdd contactIdentity: ObvCryptoIdentity, signedContactDetails: String) throws -> ObvChannelProtocolMessageToSend {
        return try delegateManager.protocolStarterDelegate.getInitiateAddKeycloakContactMessageForObliviousChannelManagementProtocol(ownedIdentity: ownedIdentity, contactIdentityToAdd: contactIdentity, signedContactDetails: signedContactDetails)
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
}
