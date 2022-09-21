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
import ObvCrypto
import ObvEncoder
import ObvTypes
import CoreData
import ObvMetaManager
import OlvidUtils

public final class ObvChannelManagerImplementation: ObvChannelDelegate, ObvProcessDownloadedMessageDelegate {
    
    // MARK: Instance variables
    
    public var logSubsystem: String { return delegateManager.logSubsystem }
    
    public func prependLogSubsystem(with prefix: String) {
        delegateManager.prependLogSubsystem(with: prefix)
    }
    
    lazy private var log = OSLog(subsystem: logSubsystem, category: "ObvChannelManagerImplementation")
    
    private static let logCategory = "ObvChannelManagerImplementation"
    
    private static let errorDomain = "ObvChannelManagerImplementation"
    
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    private weak var contextCreator: ObvCreateContextDelegate?
        
    /// Strong reference to the delegate manager, which keeps strong references to all external and internal delegate requirements.
    let delegateManager: ObvChannelDelegateManager
    let gateKeeper: GateKeeper
    
    // MARK: Initialiser
    public init(readOnly: Bool) {
        self.gateKeeper = GateKeeper(readOnly: readOnly)
        let networkReceivedMessageDecryptor = NetworkReceivedMessageDecryptor()
        let obliviousChannelLifeManager = ObliviousChannelLifeManager()
        delegateManager = ObvChannelDelegateManager(networkReceivedMessageDecryptorDelegate: networkReceivedMessageDecryptor,
                                                    obliviousChannelLifeDelegate: obliviousChannelLifeManager)
        networkReceivedMessageDecryptor.delegateManager = delegateManager // Weak reference
        obliviousChannelLifeManager.delegateManager = delegateManager // Weak reference
        KeyMaterial.delegateManager = delegateManager // Weak reference
        ObvObliviousChannel.delegateManager = delegateManager // Weak reference
        Provision.delegateManager = delegateManager // Weak reference
    }
 
    public func setObvUserInterfaceChannelDelegate(_ obvUserInterfaceChannelDelegate: ObvUserInterfaceChannelDelegate) {
        delegateManager.obvUserInterfaceChannelDelegate = obvUserInterfaceChannelDelegate
    }
    
}


// MARK: Implementing ObvManager
extension ObvChannelManagerImplementation {
    
    public var requiredDelegates: [ObvEngineDelegateType] {
        return [ObvEngineDelegateType.ObvCreateContextDelegate,
                ObvEngineDelegateType.ObvIdentityDelegate,
                ObvEngineDelegateType.ObvKeyWrapperForIdentityDelegate,
                ObvEngineDelegateType.ObvNetworkPostDelegate,
                ObvEngineDelegateType.ObvNetworkFetchDelegate,
                ObvEngineDelegateType.ObvProtocolDelegate,
                ObvEngineDelegateType.ObvFullRatchetProtocolStarterDelegate,
                ObvEngineDelegateType.ObvNotificationDelegate]
    }
    
    public func fulfill(requiredDelegate delegate: AnyObject, forDelegateType delegateType: ObvEngineDelegateType) throws {
        switch delegateType {
        case .ObvCreateContextDelegate:
            guard let delegate = delegate as? ObvCreateContextDelegate else {
                throw Self.makeError(message: "Failed to fulfill delegates (ObvCreateContextDelegate)")
            }
            self.contextCreator = delegate
        case .ObvIdentityDelegate:
            guard let delegate = delegate as? ObvIdentityDelegate else {
                throw Self.makeError(message: "Failed to fulfill delegates (ObvIdentityDelegate)")
            }
            delegateManager.identityDelegate = delegate
        case .ObvKeyWrapperForIdentityDelegate:
            guard let delegate = delegate as? ObvKeyWrapperForIdentityDelegate else {
                throw Self.makeError(message: "Failed to fulfill delegates (ObvKeyWrapperForIdentityDelegate)")
            }
            delegateManager.keyWrapperForIdentityDelegate = delegate
        case .ObvNetworkPostDelegate:
            guard let delegate = delegate as? ObvNetworkPostDelegate else {
                throw Self.makeError(message: "Failed to fulfill delegates (ObvNetworkPostDelegate)")
            }
            delegateManager.networkPostDelegate = delegate
        case .ObvNetworkFetchDelegate:
            guard let delegate = delegate as? ObvNetworkFetchDelegate else {
                throw Self.makeError(message: "Failed to fulfill delegates (ObvNetworkFetchDelegate)")
            }
            delegateManager.networkFetchDelegate = delegate
        case .ObvProtocolDelegate:
            guard let delegate = delegate as? ObvProtocolDelegate else {
                throw Self.makeError(message: "Failed to fulfill delegates (ObvProtocolDelegate)")
            }
            delegateManager.protocolDelegate = delegate
        case .ObvFullRatchetProtocolStarterDelegate:
            guard let delegate = delegate as? ObvFullRatchetProtocolStarterDelegate else {
                throw Self.makeError(message: "Failed to fulfill delegates (ObvFullRatchetProtocolStarterDelegate)")
            }
            delegateManager.fullRatchetProtocolStarterDelegate = delegate
        case .ObvNotificationDelegate:
            guard let delegate = delegate as? ObvNotificationDelegate else {
                throw Self.makeError(message: "Failed to fulfill delegates (ObvNotificationDelegate)")
            }
            delegateManager.notificationDelegate = delegate
        default:
            throw Self.makeError(message: "Failed to fulfill delegates (default)")
        }
    }
    
    
    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {}

    
    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {

        guard forTheFirstTime else { return }
        
        do {
            
            guard let contextCreator = self.contextCreator else {
                os_log("The context creator is not set", log: log, type: .fault)
                assertionFailure()
                throw ObvChannelManagerImplementation.makeError(message: "The context creator is not set")
            }
            
            try contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
                try delegateManager.obliviousChannelLifeDelegate.deleteExpiredKeyMaterialsAndProvisions(within: obvContext)
                do {
                    try obvContext.save(logOnFailure: log)
                } catch  let error {
                    os_log("Could not save context: %{public}@", log: log, type: .fault, error.localizedDescription)
                    throw error
                }
            }
            
        } catch {
            os_log("Failed to delete expired key material: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
            
    }

}


// MARK: - ProcessDownloadedMessageDelegate

extension ObvChannelManagerImplementation {
    
    public func processNetworkReceivedEncryptedMessages(_ networkReceivedMessages: Set<ObvNetworkReceivedMessageEncrypted>, within obvContext: ObvContext) {

        os_log("🌊 Processing %d network received encrypted messages within flow %{public}@", log: log, type: .info, networkReceivedMessages.count, obvContext.flowId.debugDescription)
        do {
            try gateKeeper.waitUntilSlotIsAvailableForObvContext(obvContext)
        } catch let error {
            os_log("Gate Keeper failed: %{public}@. We return now.", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            assertionFailure()
            return
        }

        let messages = networkReceivedMessages.sorted { return $0.messageUploadTimestampFromServer < $1.messageUploadTimestampFromServer }
        
        for encryptedMessage in messages {
            
            do {
                try delegateManager.networkReceivedMessageDecryptorDelegate.decryptAndProcess(encryptedMessage, within: obvContext)
            } catch {
                os_log("Failed to decrypt and process an encrypted message", log: log, type: .fault)
                assertionFailure()
                continue
            }
            
            do {
                try obvContext.addContextDidSaveCompletionHandler { (_) in
                    ObvChannelNotification.networkReceivedMessageWasProcessed(messageId: encryptedMessage.messageId, flowId: obvContext.flowId)
                        .postOnBackgroundQueue(within: notificationDelegate)
                }
            } catch {
                os_log("Could not add completion handler into obvContext", log: log, type: .fault)
                assertionFailure()
            }

        }
        
    }

}


// MARK: - ObvChannelDelegate

extension ObvChannelManagerImplementation {

    
    // MARK: Posting a message
    
    public func post(_ message: ObvChannelMessageToSend, randomizedWith prng: PRNGService, within obvContext: ObvContext) throws -> [MessageIdentifier: Set<ObvCryptoIdentity>] {
        assert(!Thread.isMainThread)
        os_log("Posting a message within obvContext: %{public}@", log: log, type: .info, obvContext.name)
        debugPrint("🚨 Posting a message within obvContext: \(obvContext.name)")
        try gateKeeper.waitUntilSlotIsAvailableForObvContext(obvContext)
        debugPrint("🚨 A slot was made avaible for posting message within obvContext \(obvContext.name)")
        os_log(" A slot was made avaible for posting message within obvContext: %{public}@", log: log, type: .info, obvContext.name)
        let channelType = message.channelType.obvChannelType
        let messageIdentifiersForCryptoIdentities = try channelType.post(message, randomizedWith: prng, delegateManager: delegateManager, within: obvContext)
        return messageIdentifiersForCryptoIdentities
    }
    
    
    // MARK: Decrypting a message

    // This method only succeeds if the ObvNetworkReceivedMessageEncrypted actually is an Application message. It is typically used when decrypting Application's User Notifications sent through APNS.
    public func decrypt(_ receivedMessage: ObvNetworkReceivedMessageEncrypted, within flowId: FlowIdentifier) throws -> ObvNetworkReceivedMessageDecrypted {
        guard let contextCreator = self.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            assertionFailure()
            throw ObvChannelManagerImplementation.makeError(message: "The context creator is not set")
        }
        var applicationMessage: ReceivedApplicationMessage?
        try contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            // Since we do not save the context, we do not need to wait until a slot is available
            applicationMessage = try delegateManager.networkReceivedMessageDecryptorDelegate.decrypt(receivedMessage, within: obvContext)
            // We do *not* save the context so as to *not* delete the decryption key, making it possible to decrypt the (full) message reveived by the network manager.
        }
        guard let message = applicationMessage else {
            os_log("Application message is nil, which is unexpected at this point", log: log, type: .fault)
            assertionFailure()
            throw ObvChannelManagerImplementation.makeError(message: "Application message is nil, which is unexpected at this point")
        }
        return ObvNetworkReceivedMessageDecrypted(with: message,
                                                  messageUploadTimestampFromServer: receivedMessage.messageUploadTimestampFromServer,
                                                  downloadTimestampFromServer: receivedMessage.downloadTimestampFromServer,
                                                  localDownloadTimestamp: receivedMessage.localDownloadTimestamp)
    }

    
    // MARK: Oblivious Channels management
    
    public func deleteObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andTheRemoteDeviceWithUid remoteDeviceUid: UID, ofRemoteIdentity remoteIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        try gateKeeper.waitUntilSlotIsAvailableForObvContext(obvContext)
        try delegateManager.obliviousChannelLifeDelegate.deleteObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andTheRemoteDeviceWithUid: remoteDeviceUid, ofRemoteIdentity: remoteIdentity, within: obvContext)
    }

    
    public func deleteObliviousChannelBetweenCurentDeviceWithUid(currentDeviceUid: UID, andTheRemoteDeviceWithUid remoteDeviceUid: UID, ofRemoteIdentity remoteIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        try gateKeeper.waitUntilSlotIsAvailableForObvContext(obvContext)
        try delegateManager.obliviousChannelLifeDelegate.deleteObliviousChannelBetweenCurentDeviceWithUid(currentDeviceUid: currentDeviceUid, andTheRemoteDeviceWithUid: remoteDeviceUid, ofRemoteIdentity: remoteIdentity, within: obvContext)
    }
    
    
    public func deleteAllObliviousChannelsBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andTheDevicesOfContactIdentity contactIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        try gateKeeper.waitUntilSlotIsAvailableForObvContext(obvContext)
        try delegateManager.obliviousChannelLifeDelegate.deleteAllObliviousChannelsBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andTheDevicesOfContactIdentity: contactIdentity, within: obvContext)
    }

    
    public func createObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity remoteCryptoIdentity: ObvCryptoIdentity, withRemoteDeviceUid remoteDeviceUid: UID, with seed: Seed, cryptoSuiteVersion: Int, within obvContext: ObvContext) throws {
        try gateKeeper.waitUntilSlotIsAvailableForObvContext(obvContext)
        try delegateManager.obliviousChannelLifeDelegate.createObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andRemoteIdentity: remoteCryptoIdentity, withRemoteDeviceUid: remoteDeviceUid, with: seed, cryptoSuiteVersion: cryptoSuiteVersion, within: obvContext)
    }
    
    
    public func confirmObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity remoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid remoteDeviceUid: UID, within obvContext: ObvContext) throws {
        try gateKeeper.waitUntilSlotIsAvailableForObvContext(obvContext)
        try delegateManager.obliviousChannelLifeDelegate.confirmObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andRemoteIdentity: remoteIdentity, withRemoteDeviceUid: remoteDeviceUid, within: obvContext)
    }
    
    
    public func updateSendSeedOfObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity remoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid remoteDeviceUid: UID, with seed: Seed, within obvContext: ObvContext) throws {
        try gateKeeper.waitUntilSlotIsAvailableForObvContext(obvContext)
        try delegateManager.obliviousChannelLifeDelegate.updateSendSeedOfObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andRemoteIdentity: remoteIdentity, withRemoteDeviceUid: remoteDeviceUid, with: seed, within: obvContext)
    }
    
    
    public func updateReceiveSeedOfObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity remoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid remoteDeviceUid: UID, with seed: Seed, within obvContext: ObvContext) throws {
        try gateKeeper.waitUntilSlotIsAvailableForObvContext(obvContext)
        try delegateManager.obliviousChannelLifeDelegate.updateReceiveSeedOfObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andRemoteIdentity: remoteIdentity, withRemoteDeviceUid: remoteDeviceUid, with: seed, within: obvContext)
    }
    
    
    public func aConfirmedObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity remoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid remoteDeviceUid: UID, within obvContext: ObvContext) throws -> Bool {
        try gateKeeper.waitUntilSlotIsAvailableForObvContext(obvContext)
        return try delegateManager.obliviousChannelLifeDelegate.aConfirmedObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andRemoteIdentity: remoteIdentity, withRemoteDeviceUid: remoteDeviceUid, within: obvContext)
    }

    
    public func anObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity remoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid remoteDeviceUid: UID, within obvContext: ObvContext) throws -> Bool {
        try gateKeeper.waitUntilSlotIsAvailableForObvContext(obvContext)
        return try delegateManager.obliviousChannelLifeDelegate.anObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andRemoteIdentity: remoteIdentity, withRemoteDeviceUid: remoteDeviceUid, within: obvContext)
    }
    
    
    public func aConfirmedObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity remoteIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        try gateKeeper.waitUntilSlotIsAvailableForObvContext(obvContext)
        return try delegateManager.obliviousChannelLifeDelegate.aConfirmedObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andRemoteIdentity: remoteIdentity, within: obvContext)
    }

    
    public func getRemoteDeviceUidsOfRemoteIdentity(_ remoteIdentity: ObvCryptoIdentity, forWhichAConfirmedObliviousChannelExistsWithTheCurrentDeviceOfOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> [UID] {
        try gateKeeper.waitUntilSlotIsAvailableForObvContext(obvContext)
        return try delegateManager.obliviousChannelLifeDelegate.getAllConfirmedObliviousChannelsBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andTheDevicesOfTheRemoteIdentity: remoteIdentity, within: obvContext)
    }
    
    
    public func getAllRemoteDeviceUidsAssociatedToAnObliviousChannel(within obvContext: ObvContext) throws -> Set<ObliviousChannelIdentifier> {
        try gateKeeper.waitUntilSlotIsAvailableForObvContext(obvContext)
        return try ObvObliviousChannel.getAllKnownRemoteDeviceUids(within: obvContext)
    }
    
}


public protocol ObvUserInterfaceChannelDelegate: AnyObject {
    func newUserDialogToPresent(obvChannelDialogMessageToSend: ObvChannelDialogMessageToSend, within obvContext: ObvContext) throws
}
