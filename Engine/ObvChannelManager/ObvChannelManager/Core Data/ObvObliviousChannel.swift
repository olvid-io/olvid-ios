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
import CoreData
import os.log
import ObvCrypto
import ObvTypes
import ObvEncoder
import ObvMetaManager
import OlvidUtils


@objc(ObvObliviousChannel)
final class ObvObliviousChannel: NSManagedObject, ObvManagedObject, ObvNetworkChannel {
    
    // MARK: Internal constants
    
    private static let entityName = "ObvObliviousChannel"
    static let currentDeviceUidKey = "currentDeviceUid"
    static let remoteCryptoIdentityKey = "remoteCryptoIdentity"
    static let remoteDeviceUidKey = "remoteDeviceUid"
    private static let isConfirmedKey = "isConfirmed"
    private static let provisionsKey = "provisions"
    
    private static let errorDomain = "ObvObliviousChannel"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    private static let log = OSLog(subsystem: ObvObliviousChannel.delegateManager.logSubsystem, category: ObvObliviousChannel.entityName)

    // MARK: General Attributes and Properties
    
    @NSManaged private(set) var currentDeviceUid: UID                   // Part of primary key
    @NSManaged private(set) var remoteCryptoIdentity: ObvCryptoIdentity // Part of primary key
    @NSManaged private(set) var remoteDeviceUid: UID                    // Part of primary key
    
    private(set) var isConfirmed: Bool {
        get {
            return kvoSafePrimitiveValue(forKey: ObvObliviousChannel.isConfirmedKey) as! Bool
        }
        set {
            if newValue != isConfirmed {
                kvoSafeSetPrimitiveValue(newValue, forKey: ObvObliviousChannel.isConfirmedKey)
                notificationRelatedChanges.insert(.isConfirmed)
            }
        }
    }
    
    // MARK: Properties related to sending keys and ratcheting
    
    // Used to determine which prng to use (to generate the next seed, the send encryption key, and the crypto key id) as well as which authenticated encryption algorithm to use
    @NSManaged private(set) var cryptoSuiteVersion: Int // Always 0, for now. Cannot be higher than the crypto suite version of the current device
    
    @NSManaged private var seedForNextSendKey: Seed
    @NSManaged private var numberOfEncryptedMessages: Int
    @NSManaged private var numberOfEncryptedMessagesAtTheTimeOfTheLastFullRatchet: Int
    @NSManaged private var numberOfDecryptedMessagesSinceLastFullRatchetSentMessage: Int
    @NSManaged private var numberOfEncryptedMessagesSinceLastFullRatchetSentMessage: Int
    @NSManaged private var timestampOfLastFullRatchet: Date
    @NSManaged private var timestampOfLastFullRatchetSentMessage: Date
    @NSManaged private var aFullRatchetOfTheSendSeedIsInProgress: Bool
    
    // MARK: Computed properties
    
    private var numberOfEncryptedMessagesSinceLastFullRatchet: Int {
        return numberOfEncryptedMessages - numberOfEncryptedMessagesAtTheTimeOfTheLastFullRatchet
    }
    
    /// Used by the manager to easily implement the full ratchet strategy. If this method returns True, the manager is expected to reset any ongoing full ratchet protocol.
    private var requiresFullRatchet: Bool {
        
        let log = OSLog(subsystem: ObvObliviousChannel.delegateManager.logSubsystem, category: "ObvObliviousChannel")
        
        os_log("Evaluating if a full ratchet of the send seed is required...", log: log, type: .info)
        
        if aFullRatchetOfTheSendSeedIsInProgress {

            os_log("A full ratchet of the send seed is in progress...", log: log, type: .info)
            
            // 1. If we received too many messages since the last full ratchet protocol message that we sent, it means that the other end of the channel will probably never send an answer to our last protocol message. In that case, we decide to start the full ratchet protocol all over again.
            guard numberOfDecryptedMessagesSinceLastFullRatchetSentMessage < ObvConstants.thresholdNumberOfDecryptedMessagesSinceLastFullRatchetSentMessage else {
                os_log("Full ratchet required because of the number of decrypted messages since the last full ratchet sent message: %d >= %d", log: log, type: .info, numberOfDecryptedMessagesSinceLastFullRatchetSentMessage, ObvConstants.thresholdNumberOfDecryptedMessagesSinceLastFullRatchetSentMessage)
                return true
            }
            os_log("[1/3] No need for a full ratchet because of the number of decrypted messages since the last full ratchet sent message: %d < %d", log: log, type: .info, numberOfDecryptedMessagesSinceLastFullRatchetSentMessage, ObvConstants.thresholdNumberOfDecryptedMessagesSinceLastFullRatchetSentMessage)

            // 2. If too much time passed since the time we sent a message related to the full ratcheting protocol in progress, we decide to start the protocol all over again.
            guard Date().timeIntervalSince(timestampOfLastFullRatchetSentMessage) < ObvConstants.thresholdTimeIntervalSinceLastFullRatchetSentMessage else {
                os_log("Full ratchet required because of too much time passed since the last last full ratchet sent message", log: log, type: .info)
                return true
            }
            os_log("[2/3] No full ratchet required because of the time passed since the last last full ratchet sent message", log: log, type: .info)

            // 3. If the number of messages sent since the last sent message related to the full ratcheting protocol is larger than the reprovisioning threshold, we must restart the protocol since the recipient could end up not being able to decrypt an old message arriving after the end of the full ratcheting.
            guard numberOfEncryptedMessagesSinceLastFullRatchetSentMessage < ObvConstants.reprovisioningThreshold else {
                os_log("Full ratchet required because of the number of encrypted messages since the last full ratchet sent message: %d >= %d", log: log, type: .info, numberOfEncryptedMessagesSinceLastFullRatchetSentMessage, ObvConstants.reprovisioningThreshold)
                return true
            }
            os_log("[3/3] No full ratchet required because of the number of encrypted messages since the last full ratchet sent message: %d < %d", log: log, type: .info, numberOfEncryptedMessagesSinceLastFullRatchetSentMessage, ObvConstants.reprovisioningThreshold)

        } else {
            
            os_log("No full ratchet of the send seed in progress...", log: log, type: .info)

            // 1. If the number of encrypted messages since the last successfull full ratchet is too high, we must start a new full ratchet
            guard numberOfEncryptedMessagesSinceLastFullRatchet < ObvConstants.thresholdNumberOfEncryptedMessagesPerFullRatchet else {
                os_log("Full ratchet required for the send seed: %d >= %d", log: log, type: .info, numberOfEncryptedMessagesSinceLastFullRatchet, ObvConstants.thresholdNumberOfEncryptedMessagesPerFullRatchet)
                return true
            }
            os_log("[1/2] No need to perform a full ratchet of the send seed: %d < %d", log: log, type: .info, numberOfEncryptedMessagesSinceLastFullRatchet, ObvConstants.thresholdNumberOfEncryptedMessagesPerFullRatchet)
            
            // 2. If the elapsed time since the last successfull full ratchet is too high, we must start a new full ratchet
            guard Date().timeIntervalSince(timestampOfLastFullRatchet) < ObvConstants.fullRatchetTimeIntervalValidity else {
                os_log("Full ratchet required because of too much time passed since the last full ratchet", log: log, type: .info)
                return true
            }
            os_log("[2/2] No need to perform a full ratchet because of the time passed since the last full ratchet", log: log, type: .info)
            
        }
        
        os_log("No need for full ratchet of the send seed.", log: log, type: .info)

        return false
    }
    
    
    
    // The following method *must* be called whenever a full ratchet protocol message is sent
    func aMessageConcerningTheFullRatchetOfTheSendSeedWasSent() {
        aFullRatchetOfTheSendSeedIsInProgress = true
        numberOfDecryptedMessagesSinceLastFullRatchetSentMessage = 0
        numberOfEncryptedMessagesSinceLastFullRatchetSentMessage = 0
        timestampOfLastFullRatchetSentMessage = Date()
    }

    
    // MARK: Relationships
    
    // MARK: Properties related to receiving and provisioning
    
    private(set) var provisions: Set<Provision> {
        get {
            let items = kvoSafePrimitiveValue(forKey: ObvObliviousChannel.provisionsKey) as! Set<Provision>
            return Set(items.map { $0.obvContext = self.obvContext; return $0 })
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: ObvObliviousChannel.provisionsKey)
        }
    }
    
    @NSManaged private var fullRatchetingCountOfLastProvision: Int
    
    // MARK: Other variables
    
    var obvContext: ObvContext?
    weak static var delegateManager: ObvChannelDelegateManager!
    
    // MARK: - Initializer
    
    /// We do *not* check whether the `currentDeviceUid`, `remoteCryptoIdentity`, nor the `remoteDeviceUid` exist within the identity delegate. This is done at the manager implementation level, i.e., within the `createObliviousChannelBetween` method of `ObvChannelManagerImplementation`
    convenience init?(currentDeviceUid: UID, remoteCryptoIdentity: ObvCryptoIdentity, remoteDeviceUid: UID, seed: Seed, cryptoSuiteVersion: Int, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: ObvObliviousChannel.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.currentDeviceUid = currentDeviceUid
        self.remoteCryptoIdentity = remoteCryptoIdentity
        self.remoteDeviceUid = remoteDeviceUid
        self.cryptoSuiteVersion = cryptoSuiteVersion
        let now = Date()
        self.timestampOfLastFullRatchet = now
        self.timestampOfLastFullRatchetSentMessage = now
        
        // Using the seed, we derive the seedForNextSendKey and compute the first provision (which contains the seedForNextProvisionedReceiveKey).
        guard let sendSeed = seed.diversify(with: currentDeviceUid, withCryptoSuite: cryptoSuiteVersion) else { return nil }
        self.seedForNextSendKey = sendSeed
        guard let recvSeed = seed.diversify(with: remoteDeviceUid, withCryptoSuite: cryptoSuiteVersion) else { return nil }
        
        self.provisions = Set<Provision>()
        guard let provision = Provision(fullRatchetingCount: 0,
                                        obliviousChannel: self,
                                        seedForNextProvisionedReceiveKey: recvSeed) else { return nil }
        self.provisions.insert(provision)
    }
    
    
    // MARK: - Updating the send seed and creating a new provision
    
    func updateSendSeed(with seed: Seed) throws {
        guard let sendSeed = seed.diversify(with: currentDeviceUid, withCryptoSuite: cryptoSuiteVersion) else {
            throw Self.makeError(message: "Could not diversify seed (1)")
        }
        seedForNextSendKey = sendSeed
        numberOfEncryptedMessagesAtTheTimeOfTheLastFullRatchet = numberOfEncryptedMessages
        timestampOfLastFullRatchet = Date()
        aFullRatchetOfTheSendSeedIsInProgress = false
    }
    

    func createNewProvision(with seed: Seed) throws {
        guard let recvSeed = seed.diversify(with: remoteDeviceUid, withCryptoSuite: cryptoSuiteVersion) else {
            throw Self.makeError(message: "Could not diversify seed (2)")
        }
        fullRatchetingCountOfLastProvision += 1
        guard let provision = Provision(fullRatchetingCount: fullRatchetingCountOfLastProvision,
                                        obliviousChannel: self,
                                        seedForNextProvisionedReceiveKey: recvSeed) else {
            throw Self.makeError(message: "Could create Provision")
        }
        self.provisions.insert(provision)
    }
    
    // MARK: Cleaning old provisions
    
    /// This method delete all the expired key material (regardless of the channel) before deleting all empty provisions.
    class func clean(within obvContext: ObvContext) throws {
        let now = Date()
        try KeyMaterial.deleteAllExpired(before: now, within: obvContext)
        try Provision.deleteAllEmpty(within: obvContext)
    }
    
    // MARK: Encryption/Wrapping method and helpers
    
    func wrapMessageKey(_ messageKey: AuthenticatedEncryptionKey, randomizedWith prng: PRNGService) -> ObvNetworkMessageToSend.Header {
        let (keyId, channelKey) = selfRatchet()!
        os_log("🔑 Wrapping message key with key id (%{public}@)", log: Self.log, type: .info, keyId.raw.hexString())
        let wrappedMessageKey = ObvObliviousChannel.wrap(messageKey, and: keyId, with: channelKey, randomizedWith: prng)
        let header = ObvNetworkMessageToSend.Header(toIdentity: remoteCryptoIdentity, deviceUid: remoteDeviceUid, wrappedMessageKey: wrappedMessageKey)
        numberOfEncryptedMessages += 1
        numberOfEncryptedMessagesSinceLastFullRatchetSentMessage += 1        
        return header
    }
    
    private static func wrap(_ messageKey: AuthenticatedEncryptionKey, and keyId: CryptoKeyId, with channelKey: AuthenticatedEncryptionKey, randomizedWith prng: PRNGService) -> EncryptedData {
        let authEnc = channelKey.algorithmImplementationByteId.algorithmImplementation
        let encryptedMessageKey = try! authEnc.encrypt(messageKey.obvEncode().rawData, with: channelKey, and: prng)
        let wrappedMessageKey = concat(keyId, with: encryptedMessageKey)
        return wrappedMessageKey
    }

    private static func concat(_ keyId: CryptoKeyId, with encryptedMessageKey: EncryptedData) -> EncryptedData {
        let rawWrappedMessageKey = keyId.raw + encryptedMessageKey
        let wrappedMessageKey = EncryptedData(data: rawWrappedMessageKey)
        return wrappedMessageKey
    }

    // MARK: Decryption/Unwrapping method and helpers

    static func unwrapMessageKey(wrappedKey: EncryptedData, toOwnedIdentity: ObvCryptoIdentity, delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) throws -> (AuthenticatedEncryptionKey, ObvProtocolReceptionChannelInfo)? {

        let log = OSLog(subsystem: ObvObliviousChannel.delegateManager.logSubsystem, category: ObvObliviousChannel.entityName)

        guard let identityDelegate = ObvObliviousChannel.delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return nil
        }

        guard let deviceUid = try? identityDelegate.getCurrentDeviceUidOfOwnedIdentity(toOwnedIdentity, within: obvContext) else {
            os_log("Could not get current device uid of an identity", log: log, type: .error)
            return nil
        }
        
        guard let (encryptedMessageKey, keyId) = ObvObliviousChannel.parse(wrappedKey) else { return nil }
        let provisionedKeys = try KeyMaterial.getAll(cryptoKeyId: keyId, currentDeviceUid: deviceUid, within: obvContext)
        // Given the keyId of the received message, we might have several candidate for the decryption key (i.e., several provisioned received keys). We try them one by one until one successfully decrypts the message
        
        os_log("🔑 Number of potential provisioned keys for this key id (%{public}@): %d", log: log, type: .info, keyId.raw.hexString(), provisionedKeys.count)
        
        for provisionedKey in provisionedKeys {
            
            let provision = provisionedKey.provision
            let obliviousChannel = provision.obliviousChannel
            let authEnc = provisionedKey.key.algorithmImplementationByteId.algorithmImplementation
            
            if let rawEncodedMessageKey = try? authEnc.decrypt(encryptedMessageKey, with: provisionedKey.key) {
                
                guard let encodedMessageKey = ObvEncoded(withRawData: rawEncodedMessageKey) else { return nil }
                guard let messageKey = try? AuthenticatedEncryptionKeyDecoder.decode(encodedMessageKey) else { return nil }
                
                os_log("🤖 Received a message on ratchet generation %d - %d", log: log, type: .info, provision.fullRatchetingCount, provisionedKey.selfRatchetingCount)
                
                // We set the expiration timestamp of older keys
                try provisionedKey.setExpirationTimestampOfOlderButNotYetExpiringProvisionedReceiveKeys()
                
                // If a full ratcheting is currently in place for refreshing the send key and send key id, we increment the number of decrypted messages since the last full ratchet sent message counter
                if obliviousChannel.aFullRatchetOfTheSendSeedIsInProgress {
                    obliviousChannel.numberOfDecryptedMessagesSinceLastFullRatchetSentMessage += 1
                }

                // We self-ratchet the provision which is about to "lose" a key
                try provisionedKey.provision.selfRatchetIfRequired()

                // The provisioned key we just used to decrypt the message will never be used again, so we delete it
                os_log("Since we used it to decrypt, we delete the provisioned key with selft ratcheting count %d", log: log, type: .debug, provisionedKey.selfRatchetingCount)
                obvContext.delete(provisionedKey)
                
                // If successfully decrypted, so we can mark the channel as 'confirmed'
                obliviousChannel.confirm()
                
                return (messageKey, obliviousChannel.type)
                
            }
        }
        
        os_log("Could not unwrap using an Oblivious Channel", log: log, type: .debug)
        return nil
    }
    
    
    static private func parse(_ wrappedMessageKey: EncryptedData) -> (EncryptedData, CryptoKeyId)? {
        // Construct the key id
        guard wrappedMessageKey.count >= CryptoKeyId.length else { return nil }
        let keyIdRange = wrappedMessageKey.startIndex..<wrappedMessageKey.startIndex+CryptoKeyId.length
        let rawKeyId = wrappedMessageKey[keyIdRange].raw
        let keyId = CryptoKeyId(rawKeyId)!
        // Construct the encryptedMessageToSendKey
        let encryptedMessageToSendKeyRange = wrappedMessageKey.startIndex+CryptoKeyId.length..<wrappedMessageKey.endIndex
        let encryptedMessageKey = wrappedMessageKey[encryptedMessageToSendKeyRange]
        return (encryptedMessageKey, keyId)
    }

    // MARK: Ratcheting
    
    /// This method self ratchets the send seed and returns a send crypto key id and authenticated encryption key.
    ///
    /// - Parameter cryptoSuiteVersion: The version of the ObvCrypto suite to use for the prng and for the authenticated encryption.
    private func selfRatchet() -> (CryptoKeyId, AuthenticatedEncryptionKey)? {
        guard let obvContext = self.obvContext else { return nil }
        guard let mergePolicy = obvContext.mergePolicy as? NSMergePolicy else { return nil }
        guard mergePolicy.isEqual(NSErrorMergePolicy) else { return nil }
        guard let (ratchetedSeed, keyId, key) = KeyMaterial.selfRatchet(seed: seedForNextSendKey,
                                                                        usingCryptoSuiteVersion: cryptoSuiteVersion) else { return nil }
        seedForNextSendKey = ratchetedSeed
        return (keyId, key)
    }

    // MARK: Other methods
    
    func confirm() {
        if isConfirmed { return }
        isConfirmed = true
    }
    
    // MARK: Tracking changes relevant for the notifications
    
    private var notificationRelatedChanges: NotificationRelatedChanges = []

}

// MARK: - Convenience DB getters
extension ObvObliviousChannel {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ObvObliviousChannel> {
        return NSFetchRequest<ObvObliviousChannel>(entityName: ObvObliviousChannel.entityName)
    }

    /// This method returns an ObvObliviousChannel if one is found.
    /// It leverages the obliviousChannelLockerDelegate to make sure that the returned channel can be safely used.
    static func get(currentDeviceUid: UID, remoteCryptoIdentity: ObvCryptoIdentity, remoteDeviceUid: UID, necessarilyConfirmed: Bool, within obvContext: ObvContext) throws -> ObvObliviousChannel? {
        let request: NSFetchRequest<ObvObliviousChannel> = ObvObliviousChannel.fetchRequest()
        if necessarilyConfirmed {
            request.predicate = NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %@ AND %K == %@",
                                            currentDeviceUidKey, currentDeviceUid,
                                            remoteCryptoIdentityKey, remoteCryptoIdentity,
                                            remoteDeviceUidKey, remoteDeviceUid,
                                            isConfirmedKey, NSNumber(value: true))
        } else {
            request.predicate = NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %@",
                                            currentDeviceUidKey, currentDeviceUid,
                                            remoteCryptoIdentityKey, remoteCryptoIdentity,
                                            remoteDeviceUidKey, remoteDeviceUid)
        }
        request.fetchLimit = 1
        let item = (try obvContext.fetch(request)).first
        item?.obvContext = obvContext
        return item
    }
    
    static func get(objectID: NSManagedObjectID, within obvContext: ObvContext) throws -> ObvObliviousChannel? {
        let request: NSFetchRequest<ObvObliviousChannel> = ObvObliviousChannel.fetchRequest()
        request.predicate = NSPredicate(format: "self == %@", objectID)
        request.fetchLimit = 1
        let item = (try obvContext.fetch(request)).first
        item?.obvContext = obvContext
        return item
    }

    /// This method returns an array of ObvObliviousChannels.
    /// It leverages the obliviousChannelLockerDelegate to make sure that the returned channels can be safely used.
    static func get(currentDeviceUid: UID, remoteCryptoIdentity: ObvCryptoIdentity, remoteDeviceUids: [UID], necessarilyConfirmed: Bool, within obvContext: ObvContext) throws -> [ObvObliviousChannel] {
        let request: NSFetchRequest<ObvObliviousChannel> = ObvObliviousChannel.fetchRequest()
        if necessarilyConfirmed {
            request.predicate = NSPredicate(format: "%K == %@ AND %K == %@ AND %K IN %@ AND %K == %@",
                                            currentDeviceUidKey, currentDeviceUid,
                                            remoteCryptoIdentityKey, remoteCryptoIdentity,
                                            remoteDeviceUidKey, remoteDeviceUids,
                                            isConfirmedKey, NSNumber(value: true))
        } else {
            request.predicate = NSPredicate(format: "%K == %@ AND %K == %@ AND %K IN %@",
                                            currentDeviceUidKey, currentDeviceUid,
                                            remoteCryptoIdentityKey, remoteCryptoIdentity,
                                            remoteDeviceUidKey, remoteDeviceUids)
        }
        let items = try obvContext.fetch(request)
        return items.map { $0.obvContext = obvContext; return $0 }
    }
    
    
    /// This method returns an array of ObvObliviousChannels.
    /// It leverages the obliviousChannelLockerDelegate to make sure that the returned channels can be safely used.
    static func getAllConfirmedChannels(currentDeviceUid: UID, remoteCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> [ObvObliviousChannel] {
        let request: NSFetchRequest<ObvObliviousChannel> = ObvObliviousChannel.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %@",
                                        currentDeviceUidKey, currentDeviceUid,
                                        remoteCryptoIdentityKey, remoteCryptoIdentity,
                                        isConfirmedKey, NSNumber(value: true))
        let items = try obvContext.fetch(request)
        return items.map { $0.obvContext = obvContext; return $0 }
    }
    
    
    static func getAll(within obvContext: ObvContext) throws -> Set<ObvObliviousChannel> {
        let request: NSFetchRequest<ObvObliviousChannel> = ObvObliviousChannel.fetchRequest()
        request.fetchBatchSize = 1_000
        return Set(try obvContext.fetch(request))
    }

    
    static func delete(currentDeviceUid: UID, remoteCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        let request: NSFetchRequest<ObvObliviousChannel> = ObvObliviousChannel.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                             currentDeviceUidKey, currentDeviceUid,
                                             remoteCryptoIdentityKey, remoteCryptoIdentity)
        let channels = try obvContext.fetch(request)
        for channel in channels {
            channel.obvContext = obvContext
            obvContext.delete(channel)
        }
    }
    
    
    static func delete(currentDeviceUid: UID, remoteDeviceUid: UID, remoteIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        let request: NSFetchRequest<ObvObliviousChannel> = ObvObliviousChannel.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %@",
                                        currentDeviceUidKey, currentDeviceUid,
                                        remoteDeviceUidKey, remoteDeviceUid,
                                        remoteCryptoIdentityKey, remoteIdentity)
        guard let channel = try obvContext.fetch(request).first else {
            return
        }
        channel.obvContext = obvContext
        obvContext.delete(channel)
    }

    
    static func getContactCryptoIdentitiesOfEstablishedChannels(withTheCurrentDeviceUid currentDeviceUid: UID, ofTheOwnedIdentity ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) -> Set<ObvCryptoIdentity>? {
        let request: NSFetchRequest<ObvObliviousChannel> = ObvObliviousChannel.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K != %@ AND %K == %@",
                                        currentDeviceUidKey, currentDeviceUid,
                                        remoteCryptoIdentityKey, ownedIdentity,
                                        isConfirmedKey, NSNumber(value: true))
        guard let items = try? obvContext.fetch(request) else { return nil }
        _ = items.map { $0.obvContext = obvContext }
        let identities = items.map { $0.remoteCryptoIdentity }
        return Set(identities)
    }

    
    static func getAllKnownRemoteDeviceUids(within obvContext: ObvContext) throws -> Set<ObliviousChannelIdentifier> {
        let request: NSFetchRequest<ObvObliviousChannel> = ObvObliviousChannel.fetchRequest()
        let items = try obvContext.fetch(request)
        _ = items.map { $0.obvContext = obvContext }
        let values = Set(items.map { ObliviousChannelIdentifier(currentDeviceUid: $0.currentDeviceUid, remoteCryptoIdentity: $0.remoteCryptoIdentity, remoteDeviceUid: $0.remoteDeviceUid) })
        return values

    }

}

// MARK: - Implementing ObvNetworkChannel
extension ObvObliviousChannel {
    
    var type: ObvProtocolReceptionChannelInfo {
        return .ObliviousChannel(remoteCryptoIdentity: remoteCryptoIdentity, remoteDeviceUid: remoteDeviceUid)
    }
    
    static func acceptableChannelsForPosting(_ message: ObvChannelMessageToSend, delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) throws -> [ObvChannel] {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObvObliviousChannel.entityName)
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw ObvObliviousChannel.makeError(message: "The identity delegate is not set")
        }
        
        let acceptableChannels: [ObvChannel]
        
        switch message.channelType {
            
        case .ObliviousChannel(to: let toIdentity, remoteDeviceUids: let remoteDeviceUids, fromOwnedIdentity: let fromOwnedIdentity, necessarilyConfirmed: let necessarilyConfirmed):
            
            // Only protocol messages may be sent through unconfirmed channels
            guard necessarilyConfirmed || message.messageType == .ProtocolMessage else { return [] }
            
            // Check that the fromIdentity is an OwnedIdentity
            guard try identityDelegate.isOwned(fromOwnedIdentity, within: obvContext) else {
                os_log("The source identity of an Oblivious channel must be owned", log: log, type: .fault)
                throw ObvObliviousChannel.makeError(message: "The source identity of an Oblivious channel must be owned")
            }
            
            // Check that the `remoteDeviceUids` match the `toIdentity`
            let allRemoteDeviceUids: Set<UID>
            if try identityDelegate.isOwned(toIdentity, within: obvContext) {
                allRemoteDeviceUids = try identityDelegate.getDeviceUidsOfOwnedIdentity(toIdentity, within: obvContext)
            } else {
                allRemoteDeviceUids = try identityDelegate.getDeviceUidsOfContactIdentity(toIdentity, ofOwnedIdentity: fromOwnedIdentity, within: obvContext)
            }
            let appropriateRemoteDeviceUids = remoteDeviceUids.filter { allRemoteDeviceUids.contains($0) }
            
            let channels = try ObvObliviousChannel.getAcceptableObliviousChannels(from: fromOwnedIdentity,
                                                                                  to: toIdentity,
                                                                                  remoteDeviceUids: appropriateRemoteDeviceUids,
                                                                                  necessarilyConfirmed: necessarilyConfirmed,
                                                                                  within: obvContext)
            
            // In the special case we are sending a protocol message that is part of a full ratchet protocol of the send seed, we must notify the channel
            if message.messageType == .ProtocolMessage {
                let protocolMessage = message as! ObvChannelProtocolMessageToSend
                if protocolMessage.partOfFullRatchetProtocolOfTheSendSeed {
                    for channel in channels {
                        channel.aMessageConcerningTheFullRatchetOfTheSendSeedWasSent()
                    }
                }
            }
            acceptableChannels = channels
            
            
        case .AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: let contactIdentities, fromOwnedIdentity: let ownedIdentity):
            let channels: [[ObvObliviousChannel]] = try contactIdentities.compactMap { (contactIdentity) in
                guard let remoteDeviceUids = try? identityDelegate.getDeviceUidsOfContactIdentity(contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext) else {
                    os_log("Could not determine the device uids of one of the recipient (4)", log: log, type: .error)
                    return nil
                }
                let channels = try ObvObliviousChannel.getAcceptableObliviousChannels(from: ownedIdentity,
                                                                                      to: contactIdentity,
                                                                                      remoteDeviceUids: Array(remoteDeviceUids),
                                                                                      necessarilyConfirmed: true,
                                                                                      within: obvContext)
                return channels
            }
            acceptableChannels = channels.reduce([ObvObliviousChannel]()) { (array, channels) in
                return array + channels
            }
            
            
        case .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: let ownedIdentity):
            guard try identityDelegate.isOwned(ownedIdentity, within: obvContext) else {
                throw ObvObliviousChannel.makeError(message: "Identity is not owned")
            }
            let remoteDeviceUids = try identityDelegate.getDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
            let channels = try ObvObliviousChannel.getAcceptableObliviousChannels(from: ownedIdentity,
                                                                                  to: ownedIdentity,
                                                                                  remoteDeviceUids: Array(remoteDeviceUids),
                                                                                  necessarilyConfirmed: true,
                                                                                  within: obvContext)
            acceptableChannels = channels

            
        case .AsymmetricChannel,
             .AsymmetricChannelBroadcast,
             .Local,
             .UserInterface,
             .ServerQuery:
            os_log("Wrong message channel type", log: log, type: .fault)
            assertionFailure()
            acceptableChannels = []
        }
        
        return acceptableChannels
    }

    
    private static func getAcceptableObliviousChannels(from ownedIdentity: ObvCryptoIdentity, to remoteCryptoIdentity: ObvCryptoIdentity, remoteDeviceUids: [UID], necessarilyConfirmed: Bool, within obvContext: ObvContext) throws -> [ObvObliviousChannel] {
        
        let log = OSLog(subsystem: ObvObliviousChannel.delegateManager.logSubsystem, category: ObvObliviousChannel.entityName)

        guard let identityDelegate = ObvObliviousChannel.delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw ObvObliviousChannel.makeError(message: "The identity delegate is not set")
        }
        
        let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
        let channels = try ObvObliviousChannel.get(currentDeviceUid: currentDeviceUid,
                                                   remoteCryptoIdentity: remoteCryptoIdentity,
                                                   remoteDeviceUids: remoteDeviceUids,
                                                   necessarilyConfirmed: necessarilyConfirmed,
                                                   within: obvContext)
        
        let acceptableChannels = channels.filter { $0.cryptoSuiteVersion >= ObvCryptoSuite.sharedInstance.minAcceptableVersion }
        return acceptableChannels.map { $0.obvContext = obvContext; return $0 }
    }
    
}

// MARK: - Managing notifications and calls to delegates
extension ObvObliviousChannel {
    
    private struct NotificationRelatedChanges: OptionSet {
        let rawValue: UInt8
        static let isConfirmed = NotificationRelatedChanges(rawValue: 1 << 0)
    }

    
    
    override func didSave() {
        super.didSave()
        
        defer {
            notificationRelatedChanges = [] // Ensure the notifications are set only once
        }
        
        let log = OSLog(subsystem: ObvObliviousChannel.delegateManager.logSubsystem, category: ObvObliviousChannel.entityName)
        
        guard let notificationDelegate = ObvObliviousChannel.delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }
        
        if self.requiresFullRatchet {
            if let fullRatchetProtocolStarterDelegate = ObvObliviousChannel.delegateManager.fullRatchetProtocolStarterDelegate {
                let currentDeviceUid = self.currentDeviceUid
                let remoteDeviceUid = self.remoteDeviceUid
                let remoteCryptoIdentity = self.remoteCryptoIdentity
                DispatchQueue(label: "Queue for starting a full ratchet of the current (send) Oblivious channel").async {
                    do {
                        try fullRatchetProtocolStarterDelegate.startFullRatchetProtocolForObliviousChannelBetween(currentDeviceUid: currentDeviceUid,
                                                                                                                  andRemoteDeviceUid: remoteDeviceUid,
                                                                                                                  ofRemoteIdentity: remoteCryptoIdentity)
                    } catch {
                        os_log("Could not start full ratchet protocol", log: log, type: .fault)
                        assertionFailure()
                    }
                }
            } else {
                os_log("The Oblivious Channel Full Ratchet Protocol Starter Delegate is not set", log: log, type: .fault)
                assertionFailure()
            }
        }
        
        if self.isConfirmed && notificationRelatedChanges.contains(.isConfirmed) {
            
            os_log("Posting a NewConfirmedObliviousChannel notification", log: log, type: .debug)
            ObvChannelNotification.newConfirmedObliviousChannel(currentDeviceUid: currentDeviceUid,
                                                                remoteCryptoIdentity: remoteCryptoIdentity,
                                                                remoteDeviceUid: remoteDeviceUid)
            .postOnBackgroundQueue(within: notificationDelegate)

        } else if isDeleted && self.isConfirmed {
            
            os_log("Posting a DeletedConfirmedObliviousChannel notification", log: log, type: .debug)
            ObvChannelNotification.deletedConfirmedObliviousChannel(currentDeviceUid: currentDeviceUid,
                                                                    remoteCryptoIdentity: remoteCryptoIdentity,
                                                                    remoteDeviceUid: remoteDeviceUid)
            .postOnBackgroundQueue(within: notificationDelegate)

        }
        
    }
    
}
