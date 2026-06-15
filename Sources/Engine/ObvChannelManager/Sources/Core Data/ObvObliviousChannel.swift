/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import OSLog
import ObvCrypto
import ObvTypes
import ObvEncoder
import ObvMetaManager
import OlvidUtils


@objc(ObvObliviousChannel)
final class ObvObliviousChannel: NSManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "ObvObliviousChannel"
    private static let logger = Logger(subsystem: "io.olvid.channel", category: "ObvObliviousChannel")
    weak static var delegateManager: ObvChannelDelegateManager?

    // MARK: General Properties
    
    @NSManaged private var rawCurrentDeviceUID: Data?                   // Part of primary key, non-nil in the model
    @NSManaged private var rawRemoteCryptoId: Data? // Part of primary key (may be an owned identity), non-nil in the model
    @NSManaged private var rawRemoteDeviceUID: Data?                    // Part of primary key, non-nil in the model
    @NSManaged private(set) var isConfirmed: Bool
    
    // MARK: Properties related to sending keys and ratcheting
    
    // Used to determine which prng to use (to generate the next seed, the send encryption key, and the crypto key id) as well as which authenticated encryption algorithm to use
    @NSManaged private(set) var cryptoSuiteVersion: Int // Always 0, for now. Cannot be higher than the crypto suite version of the current device
    
    @NSManaged private var rawSeedForNextSendKey: Data? // Non-nil in the model
    @NSManaged private var numberOfEncryptedMessages: Int
    @NSManaged private var numberOfEncryptedMessagesAtTheTimeOfTheLastFullRatchet: Int
    @NSManaged private var timestampOfLastFullRatchet: Date
    @NSManaged private var timestampOfLastFullRatchetRequest: Date // Date when `aFullRatchetOfTheSendSeedWasRequestedAndMayBeInProgress` was last set to true.
    @NSManaged private var aFullRatchetOfTheSendSeedWasRequestedAndMayBeInProgress: Bool // If true, a notification was sent to the protocol manager to start a full ratchet. Was aFullRatchetOfTheSendSeedIsInProgress.
    
    // MARK: Properties relating to receiving and provisioning
    
    @NSManaged private var fullRatchetingCountOfLastProvision: Int

    // MARK: Relationships relating to receiving and provisioning
    
    @NSManaged private(set) var provisions: Set<Provision>
    
    // MARK: Computed properties
    
    private var seedForNextSendKey: Seed {
        get throws(ObvError) {
            guard let rawSeedForNextSendKey else { assertionFailure(); throw .unexpectedNilValue }
            guard let seed = Seed(with: rawSeedForNextSendKey) else { assertionFailure(); throw .unexpectedNilValue }
            return seed
        }
    }
    
    
    var currentDeviceUID: UID {
        get throws(ObvError) {
            guard let rawCurrentDeviceUID else { assertionFailure(); throw .unexpectedNilValue }
            guard let uid = UID(uid: rawCurrentDeviceUID) else { assertionFailure(); throw .unexpectedNilValue }
            return uid
        }
    }
    
    
    var remoteDeviceUID: UID {
        get throws(ObvError) {
            guard let rawRemoteDeviceUID else { assertionFailure(); throw .unexpectedNilValue }
            guard let uid = UID(uid: rawRemoteDeviceUID) else { assertionFailure(); throw .unexpectedNilValue }
            return uid
        }
    }
    
    
    private var remoteCryptoId: ObvCryptoId {
        get throws {
            guard let rawRemoteCryptoId else { assertionFailure(); throw ObvError.unexpectedNilValue }
            return try ObvCryptoId(identity: rawRemoteCryptoId)
        }
    }
    
    
    private var numberOfEncryptedMessagesSinceLastFullRatchet: Int {
        return numberOfEncryptedMessages - numberOfEncryptedMessagesAtTheTimeOfTheLastFullRatchet
    }
    
    
    /// Used by the manager to easily implement the full ratchet strategy. If this method returns True, the manager is expected to reset any ongoing full ratchet protocol.
    private var requiresFullRatchet: Bool {
                
        Self.logger.info("Evaluating if a full ratchet of the send seed is required...")
                
        if aFullRatchetOfTheSendSeedWasRequestedAndMayBeInProgress {

            Self.logger.info("A full ratchet of the send seed was requested...")
                        
            // If too much time passed since the time we requested a full ratchet of the send seed, we decide to start the protocol all over again.
            let timeIntervalSinceTimestampOfLastFullRatchetRequest: TimeInterval = Date.now.timeIntervalSince(timestampOfLastFullRatchetRequest)
            guard timeIntervalSinceTimestampOfLastFullRatchetRequest < ObvConstants.thresholdTimeIntervalSinceLastFullRatchetRequest else {
                Self.logger.info("Full ratchet required because of too much time elapsed since the last last full ratchet sent message")
                return true
            }
            Self.logger.info("No full ratchet required because of the time elapsed since the last last full ratchet sent message. Remaining time: \(ObvConstants.thresholdTimeIntervalSinceLastFullRatchetRequest - timeIntervalSinceTimestampOfLastFullRatchetRequest) seconds.")

        } else {
            
            Self.logger.info("No full ratchet of the send seed was requested...")

            // 1. If the number of encrypted messages since the last successfull full ratchet is too high, we must start a new full ratchet
            guard numberOfEncryptedMessagesSinceLastFullRatchet < ObvConstants.thresholdNumberOfEncryptedMessagesPerFullRatchet else {
                let nbr = self.numberOfEncryptedMessagesSinceLastFullRatchet
                Self.logger.info("Full ratchet required for the send seed: \(nbr) >= \(ObvConstants.thresholdNumberOfEncryptedMessagesPerFullRatchet)")
                return true
            }
            let numberOfEncryptedMessagesSinceLastFullRatchetForLog = self.numberOfEncryptedMessagesSinceLastFullRatchet
            Self.logger.info("[1/2] No need to perform a full ratchet of the send seed: \(numberOfEncryptedMessagesSinceLastFullRatchetForLog) < \(ObvConstants.thresholdNumberOfEncryptedMessagesPerFullRatchet)")
            
            // 2. If the elapsed time since the last successfull full ratchet is too high, we must start a new full ratchet
            let timeIntervalSinceLastFullRatchet: TimeInterval = Date.now.timeIntervalSince(timestampOfLastFullRatchet)
            guard timeIntervalSinceLastFullRatchet < ObvConstants.fullRatchetTimeIntervalValidity else {
                Self.logger.info("Full ratchet required because of too much time passed since the last full ratchet")
                return true
            }
            Self.logger.info("[2/2] No need to perform a full ratchet because of the time passed since the last full ratchet. Next full ratchet in \(ObvConstants.fullRatchetTimeIntervalValidity - timeIntervalSinceLastFullRatchet) seconds maximum.")
            
        }
        
        Self.logger.info("No need for full ratchet of the send seed.")

        return false
    }
    

    /// Shall only be set to `true` from `func doRequestFullRatchetOfTheSendSeedOnSave()`
    private var requestFullRatchetOfTheSendSeedOnSave = false

    private func doRequestFullRatchetOfTheSendSeedOnSave() {
        requestFullRatchetOfTheSendSeedOnSave = true
        aFullRatchetOfTheSendSeedWasRequestedAndMayBeInProgress = true
        timestampOfLastFullRatchetRequest = Date.now
    }
            
    // MARK: - Initializer
    
    /// We do *not* check whether the `currentDeviceUid`, `remoteCryptoIdentity`, nor the `remoteDeviceUid` exist within the identity delegate. This is done at the manager implementation level, i.e., within the `createObliviousChannelBetween` method of `ObvChannelManagerImplementation`
    convenience init(currentDeviceUID: UID, remoteCryptoId: ObvCryptoId, remoteDeviceUID: UID, seed: Seed, cryptoSuiteVersion: Int, within context: NSManagedObjectContext) throws {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: ObvObliviousChannel.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.rawCurrentDeviceUID = currentDeviceUID.raw
        self.rawRemoteCryptoId = remoteCryptoId.getIdentity()
        self.rawRemoteDeviceUID = remoteDeviceUID.raw
        self.cryptoSuiteVersion = cryptoSuiteVersion
        let now = Date.now
        self.timestampOfLastFullRatchet = now
        self.timestampOfLastFullRatchetRequest = now
        self.aFullRatchetOfTheSendSeedWasRequestedAndMayBeInProgress = false
        
        // Using the seed, we derive the seedForNextSendKey and compute the first provision (which contains the seedForNextProvisionedReceiveKey).
        guard let sendSeed = seed.diversify(with: currentDeviceUID, withCryptoSuite: cryptoSuiteVersion) else { assertionFailure(); throw ObvError.couldNotDiversifySeed }
        self.rawSeedForNextSendKey = sendSeed.raw
        
        guard let recvSeed = seed.diversify(with: remoteDeviceUID, withCryptoSuite: cryptoSuiteVersion) else { assertionFailure(); throw ObvError.couldNotDiversifySeed }
        self.provisions = Set<Provision>()
        let provision = try Provision(fullRatchetingCount: 0,
                                      obliviousChannel: self,
                                      seedForNextProvisionedReceiveKey: recvSeed)
        self.provisions.insert(provision)
        
    }
    

    // MARK: - Updating the send seed and creating a new provision
    
    func updateSendSeed(with seed: Seed) throws {
        guard let sendSeed = try seed.diversify(with: currentDeviceUID, withCryptoSuite: cryptoSuiteVersion) else {
            throw ObvError.couldNotDiversifySeed
        }
        self.rawSeedForNextSendKey = sendSeed.raw
        numberOfEncryptedMessagesAtTheTimeOfTheLastFullRatchet = numberOfEncryptedMessages
        timestampOfLastFullRatchet = Date.now
        aFullRatchetOfTheSendSeedWasRequestedAndMayBeInProgress = false
    }
    

    func createNewProvision(with seed: Seed) throws {
        guard let recvSeed = try seed.diversify(with: remoteDeviceUID, withCryptoSuite: cryptoSuiteVersion) else {
            throw ObvError.couldNotDiversifySeed
        }
        fullRatchetingCountOfLastProvision += 1
        let provision = try Provision(fullRatchetingCount: fullRatchetingCountOfLastProvision,
                                      obliviousChannel: self,
                                      seedForNextProvisionedReceiveKey: recvSeed)
        self.provisions.insert(provision)
    }
    
    // MARK: Deleting old provisions
    
    /// This method delete all the expired key material (regardless of the channel) before deleting all empty provisions.
    static func deleteExpiredKeyMaterialAndEmptyProvisions(within context: NSManagedObjectContext) throws {
        try KeyMaterial.deleteAllExpired(before: Date.now, within: context)
        try Provision.deleteAllEmpty(within: context)
    }
    
    
    private func deleteObvObliviousChannel() throws {
        guard let context = self.managedObjectContext else {
            assertionFailure()
            throw ObvError.noContext
        }
        context.delete(self)
    }
    
    // MARK: Encryption/Wrapping method and helpers
    
    func wrapMessageKey(_ messageKey: any AuthenticatedEncryptionKey, isAppMessage: Bool, randomizedWith prng: any PRNGService) -> ObvNetworkMessageToSend.Header? {
        do {
            // Wrap the message key
            let header = try self.wrapMessageKeyIntern(messageKey, randomizedWith: prng)
            // In case we are wrapping the key of an application message, evaluate if a full ratchet of the send seed is required.
            // If this is the case, a notification will be sent to the protocol manager after saving this oblivious channel.
            if isAppMessage && self.requiresFullRatchet {
                doRequestFullRatchetOfTheSendSeedOnSave()
            }
            // Return the header
            return header
        } catch {
            assertionFailure()
            return nil
        }
    }


    private func wrapMessageKeyIntern(_ messageKey: AuthenticatedEncryptionKey, randomizedWith prng: PRNGService) throws -> ObvNetworkMessageToSend.Header {
        let (keyId, channelKey) = try selfRatchet()
        Self.logger.info("🔑 Wrapping message key with key id (\(keyId.raw.hexString(), privacy: .public)")
        let wrappedMessageKey = try ObvObliviousChannel.wrap(messageKey, and: keyId, with: channelKey, randomizedWith: prng)
        let header = try ObvNetworkMessageToSend.Header(
            toIdentity: remoteCryptoId.cryptoIdentity,
            deviceUid: remoteDeviceUID,
            wrappedMessageKey: wrappedMessageKey)
        numberOfEncryptedMessages += 1
        return header
    }
    
    
    private static func wrap(_ messageKey: AuthenticatedEncryptionKey, and keyId: CryptoKeyId, with channelKey: AuthenticatedEncryptionKey, randomizedWith prng: PRNGService) throws -> EncryptedData {
        let authEnc = channelKey.algorithmImplementationByteId.algorithmImplementation
        let encryptedMessageKey = try authEnc.encrypt(messageKey.obvEncode().rawData, with: channelKey, and: prng)
        let wrappedMessageKey = keyId.concat(with: encryptedMessageKey)
        return wrappedMessageKey
    }

    
    // MARK: Decryption/Unwrapping method and helpers
    
    static func unwrapMessageKey(wrappedKey: ObvCrypto.EncryptedData, toOwnedIdentity: ObvCrypto.ObvCryptoIdentity, delegateManager: ObvChannelDelegateManager, within obvContext: OlvidUtils.ObvContext) throws -> UnwrapMessageKeyResult {

        let context = obvContext.context
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            Self.logger.fault("The identity delegate is not set")
            assertionFailure()
            throw ObvError.identityDelegateIsNil
        }

        let deviceUID = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(toOwnedIdentity, within: obvContext)
        
        guard let (encryptedMessageKey, keyId) = CryptoKeyId.parse(wrappedKey) else { return .couldNotUnwrap }
        let provisionedKeys = try KeyMaterial.getAll(cryptoKeyId: keyId, currentDeviceUID: deviceUID, within: context)

        // Given the keyId of the received message, we might have several candidate for the decryption key (i.e., several provisioned received keys). We try them one by one until one successfully decrypts the message
        
        Self.logger.info("🔑 Number of potential provisioned keys for this key id (\(keyId.raw.hexString(), privacy: .public): \(provisionedKeys.count)")
        
        for provisionedKey in provisionedKeys {
            
            guard let provision = provisionedKey.provision else {
                assertionFailure()
                throw ObvError.unexpectedNilValue
            }
            guard let obliviousChannel = provision.obliviousChannel else {
                throw ObvError.unexpectedNilValue
            }
            let authEnc = try provisionedKey.key.algorithmImplementationByteId.algorithmImplementation
            
            if let rawEncodedMessageKey = try? authEnc.decrypt(encryptedMessageKey, with: provisionedKey.key) {
                
                guard let encodedMessageKey = ObvEncoded(withRawData: rawEncodedMessageKey) else { return .couldNotUnwrap }
                guard let messageKey = try? AuthenticatedEncryptionKeyDecoder.decode(encodedMessageKey) else { return .couldNotUnwrap }
                
                let fullRatchetingCount = provision.fullRatchetingCount
                let selfRatchetingCount = provisionedKey.selfRatchetingCount
                Self.logger.info("🤖 Received a message on ratchet generation \(fullRatchetingCount) - \(selfRatchetingCount)")
                
                // We set the expiration timestamp of older keys
                try provisionedKey.setExpirationTimestampOfOlderButNotYetExpiringProvisionedReceiveKeys()
                
                // We self-ratchet the provision which is about to "lose" a key
                guard let provisionedKeyProvision = provisionedKey.provision else {
                    assertionFailure()
                    throw ObvError.unexpectedNilValue
                }
                try provisionedKeyProvision.selfRatchetIfRequired()

                // The provisioned key we just used to decrypt the message will never be used again, so we delete it
                Self.logger.debug("Since we used it to decrypt, we delete the provisioned key with selft ratcheting count \(provisionedKey.selfRatchetingCount)")
                try provisionedKey.deleteKeyMaterial()
                
                // If successfully decrypted, so we can mark the channel as 'confirmed'
                obliviousChannel.confirm()
                
                return .unwrapSucceeded(
                    messageKey: messageKey,
                    receptionChannelInfo: try obliviousChannel.type)
                
            }
            
        }
        
        Self.logger.debug("Could not unwrap using an Oblivious Channel")
        return .couldNotUnwrap
        
    }
        
    
    // MARK: Ratcheting
    
    /// This method self ratchets the send seed and returns a send crypto key id and authenticated encryption key.
    ///
    /// - Parameter cryptoSuiteVersion: The version of the ObvCrypto suite to use for the prng and for the authenticated encryption.
    private func selfRatchet() throws -> (CryptoKeyId, AuthenticatedEncryptionKey) {
        let (ratchetedSeed, keyId, key) = try KeyMaterial.selfRatchet(
            seed: seedForNextSendKey,
            usingCryptoSuiteVersion: cryptoSuiteVersion)
        self.rawSeedForNextSendKey = ratchetedSeed.raw
        return (keyId, key)
    }

    // MARK: Other methods
    
    func confirm() {
        if isConfirmed { return }
        isConfirmed = true
    }
    
    // MARK: Tracking changes relevant for the notifications
    
    private var changedKeys = Set<String>()

}

// MARK: - Errors
extension ObvObliviousChannel {
    
    enum ObvError: Error {
        case keyWrapperForIdentityDelegateIsNotSet
        case cryptoIdentityIsNotOwned
        case identityDelegateIsNil
        case unexpectedNilValue
        case couldNotDiversifySeed
        case couldNotCreateProvision
        case noContext
        case couldNotCastFetchedResult
    }
    
}

// MARK: - Convenience DB getters
extension ObvObliviousChannel {
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case aFullRatchetOfTheSendSeedWasRequestedAndMayBeInProgress = "aFullRatchetOfTheSendSeedWasRequestedAndMayBeInProgress" // Bool
            case cryptoSuiteVersion = "cryptoSuiteVersion"
            case fullRatchetingCountOfLastProvision = "fullRatchetingCountOfLastProvision"
            case isConfirmed = "isConfirmed"
            case numberOfEncryptedMessages = "numberOfEncryptedMessages"
            case numberOfEncryptedMessagesAtTheTimeOfTheLastFullRatchet = "numberOfEncryptedMessagesAtTheTimeOfTheLastFullRatchet"
            case rawCurrentDeviceUID = "rawCurrentDeviceUID"
            case rawRemoteCryptoId = "rawRemoteCryptoId"
            case rawRemoteDeviceUID = "rawRemoteDeviceUID"
            case rawSeedForNextSendKey = "rawSeedForNextSendKey"
            case timestampOfLastFullRatchet = "timestampOfLastFullRatchet"
            case timestampOfLastFullRatchetSentMessage = "timestampOfLastFullRatchetSentMessage"
            // Relationships
            case provisions = "provisions"
        }
        static func withCurrentDeviceUID(_ currentDeviceUID: UID) -> NSPredicate {
            NSPredicate(Key.rawCurrentDeviceUID, EqualToData: currentDeviceUID.raw)
        }
        static func withRemoteCryptoId(_ remoteCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawRemoteCryptoId, EqualToData: remoteCryptoId.getIdentity())
        }
        static func withRemoteDeviceUID(_ remoteDeviceUID: UID) -> NSPredicate {
            NSPredicate(Key.rawRemoteDeviceUID, EqualToData: remoteDeviceUID.raw)
        }
        static func withRemoteDeviceUID(in remoteDeviceUIDs: [UID]) -> NSPredicate {
            NSPredicate(format: "%K IN %@", Key.rawRemoteDeviceUID.rawValue, remoteDeviceUIDs.map(\.raw))
        }
        static func whereIsConfirmed(is isConfirmed: Bool) -> NSPredicate {
            NSPredicate(Key.isConfirmed, is: isConfirmed)
        }
        static func withObjectID(_ objectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(withObjectID: objectID)
        }
    }
    
    
    @nonobjc private static func fetchRequest() -> NSFetchRequest<ObvObliviousChannel> {
        return NSFetchRequest<ObvObliviousChannel>(entityName: Self.entityName)
    }

    
    @nonobjc private static func dictionaryFetchRequest() -> NSFetchRequest<NSDictionary> {
        return NSFetchRequest<NSDictionary>(entityName: Self.entityName)
    }

    
    /// This method returns an `ObvObliviousChannel` if one is found.
    static func get(currentDeviceUID: UID, remoteCryptoId: ObvCryptoId, remoteDeviceUID: UID, necessarilyConfirmed: Bool, within context: NSManagedObjectContext) throws -> ObvObliviousChannel? {
        let request: NSFetchRequest<ObvObliviousChannel> = ObvObliviousChannel.fetchRequest()
        var allPredicates: [NSPredicate] = [
            Predicate.withCurrentDeviceUID(currentDeviceUID),
            Predicate.withRemoteCryptoId(remoteCryptoId),
            Predicate.withRemoteDeviceUID(remoteDeviceUID),
        ]
        if necessarilyConfirmed {
            allPredicates.append(Predicate.whereIsConfirmed(is: true))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: allPredicates)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    static func get(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> ObvObliviousChannel? {
        let request: NSFetchRequest<ObvObliviousChannel> = ObvObliviousChannel.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    /// This method returns an array of `ObvObliviousChannels`.
    static func get(currentDeviceUID: UID, remoteCryptoId: ObvCryptoId, remoteDeviceUIDs: [UID], necessarilyConfirmed: Bool, within context: NSManagedObjectContext) throws -> [ObvObliviousChannel] {
        let request: NSFetchRequest<ObvObliviousChannel> = ObvObliviousChannel.fetchRequest()
        var allPredicates: [NSPredicate] = [
            Predicate.withCurrentDeviceUID(currentDeviceUID),
            Predicate.withRemoteCryptoId(remoteCryptoId),
            Predicate.withRemoteDeviceUID(in: remoteDeviceUIDs),
        ]
        if necessarilyConfirmed {
            allPredicates.append(Predicate.whereIsConfirmed(is: true))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: allPredicates)
        request.fetchLimit = remoteDeviceUIDs.count
        return try context.fetch(request)
    }
    
    
    /// This method returns an array of `ObvObliviousChannels`.
    static func getAllConfirmedChannels(currentDeviceUID: UID, remoteCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> [ObvObliviousChannel] {
        let request: NSFetchRequest<ObvObliviousChannel> = ObvObliviousChannel.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withCurrentDeviceUID(currentDeviceUID),
            Predicate.withRemoteCryptoId(remoteCryptoId),
            Predicate.whereIsConfirmed(is: true),
        ])
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }
    
    
    static func getAll(within context: NSManagedObjectContext) throws -> Set<ObvObliviousChannel> {
        let request: NSFetchRequest<ObvObliviousChannel> = ObvObliviousChannel.fetchRequest()
        request.fetchBatchSize = 1_000
        return Set(try context.fetch(request))
    }

    
    static func delete(currentDeviceUID: UID, remoteCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<ObvObliviousChannel> = ObvObliviousChannel.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withCurrentDeviceUID(currentDeviceUID),
            Predicate.withRemoteCryptoId(remoteCryptoId),
        ])
        request.propertiesToFetch = []
        let channels = try context.fetch(request)
        for channel in channels {
            try channel.deleteObvObliviousChannel()
        }
    }
    
    
    static func delete(currentDeviceUID: UID, remoteDeviceUID: UID, remoteCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<ObvObliviousChannel> = ObvObliviousChannel.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withCurrentDeviceUID(currentDeviceUID),
            Predicate.withRemoteDeviceUID(remoteDeviceUID),
            Predicate.withRemoteCryptoId(remoteCryptoId),
        ])
        let channels = try context.fetch(request)
        for channel in channels {
            try channel.deleteObvObliviousChannel()
        }
    }

    
    static func getAllObliviousChannelIdentifiers(within context: NSManagedObjectContext) throws -> Set<ObliviousChannelIdentifier> {
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = [
            Self.Predicate.Key.rawCurrentDeviceUID.rawValue,
            Self.Predicate.Key.rawRemoteCryptoId.rawValue,
            Self.Predicate.Key.rawRemoteDeviceUID.rawValue,
        ]
        request.includesPendingChanges = true
        guard let results = try context.fetch(request) as? [[String: Data]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }
        let valuesToReturn: [ObliviousChannelIdentifier] = try results.map { dict in
            // Extract values from dict
            guard let rawCurrentDeviceUID = dict[Self.Predicate.Key.rawCurrentDeviceUID.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawRemoteCryptoId = dict[Self.Predicate.Key.rawRemoteCryptoId.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawRemoteDeviceUID = dict[Self.Predicate.Key.rawRemoteDeviceUID.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            // Cast extracted values
            guard let currentDeviceUID = UID(uid: rawCurrentDeviceUID) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            let remoteCryptoId = try ObvCryptoId(identity: rawRemoteCryptoId)
            guard let remoteDeviceUID = UID(uid: rawRemoteDeviceUID) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            // Return the expected type
            return ObliviousChannelIdentifier(
                currentDeviceUid: currentDeviceUID,
                remoteCryptoIdentity: remoteCryptoId.cryptoIdentity,
                remoteDeviceUid: remoteDeviceUID)
        }
        return Set(valuesToReturn)
    }

    
    static func deleteAllObliviousChannelsForCurrentDeviceUID(_ currentDeviceUID: UID, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<ObvObliviousChannel> = ObvObliviousChannel.fetchRequest()
        request.fetchBatchSize = 500
        request.predicate = Predicate.withCurrentDeviceUID(currentDeviceUID)
        request.propertiesToFetch = []
        let channels = try context.fetch(request)
        for channel in channels {
            try channel.deleteObvObliviousChannel()
        }
    }

}



// MARK: - Implementing ObvNetworkChannel

extension ObvObliviousChannel: ObvNetworkChannel {
    
    var type: ObvProtocolReceptionChannelInfo {
        get throws {
            return try .obliviousChannel(
                remoteCryptoIdentity: remoteCryptoId.cryptoIdentity,
                remoteDeviceUid: remoteDeviceUID)
        }
    }
    
    
    static func acceptableChannelsForPosting(_ message: ObvChannelMessageToSend, delegateManager: ObvChannelDelegateManager, within obvContext: ObvContext) throws -> [ObvChannel] {
                
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ObvObliviousChannel.entityName)

        guard let identityDelegate = delegateManager.identityDelegate else {
            Self.logger.fault("The identity delegate is not set")
            throw ObvError.identityDelegateIsNil
        }
        
        guard let keyWrapper = delegateManager.keyWrapperForIdentityDelegate else {
            Self.logger.fault("The keyWrapperForIdentityDelegate is not set")
            throw ObvError.keyWrapperForIdentityDelegateIsNotSet
        }
        
        // Check that the fromIdentity is an OwnedIdentity

        do {
            let ownedCryptoId = message.channelType.fromOwnedIdentity
            guard try identityDelegate.isOwned(ownedCryptoId, within: obvContext) else {
                Self.logger.fault("The source identity of an Oblivious channel must be owned")
                throw ObvError.cryptoIdentityIsNotOwned
            }
        }
        
        let acceptableChannels: [ObvChannel]
        
        switch message.channelType {
            
        case .obliviousChannel(to: let remoteCryptoId, remoteDeviceUids: let remoteDeviceUids, fromOwnedIdentity: let ownedCryptoId, necessarilyConfirmed: let necessarilyConfirmed, usePreKeyIfRequired: let usePreKeyIfRequired):
                        
            // Only protocol messages may be sent through unconfirmed channels
            
            guard necessarilyConfirmed || message.messageType == .ProtocolMessage else { return [] }
            
            // Check that the `remoteDeviceUids` match the `toIdentity`
            
            let appropriateRemoteDeviceUids: Set<UID>
            if ownedCryptoId == remoteCryptoId {
                let allRemoteDeviceUids = try identityDelegate.getDeviceUidsOfOwnedIdentity(remoteCryptoId, within: obvContext)
                appropriateRemoteDeviceUids = Set(remoteDeviceUids).intersection(allRemoteDeviceUids)
            } else {
                let allRemoteDeviceUids = try identityDelegate.getDeviceUidsOfContactIdentity(remoteCryptoId, ofOwnedIdentity: ownedCryptoId, within: obvContext)
                appropriateRemoteDeviceUids = Set(remoteDeviceUids).intersection(allRemoteDeviceUids)
            }
            
            // Determine the appropriate channels
            
            acceptableChannels = try getAllAcceptableChannels(
                ownedCryptoId: ObvCryptoId(cryptoIdentity: ownedCryptoId),
                remoteCryptoId: ObvCryptoId(cryptoIdentity: remoteCryptoId),
                remoteDeviceUIDs: appropriateRemoteDeviceUids,
                necessarilyConfirmed: necessarilyConfirmed,
                usePreKeyIfRequired: usePreKeyIfRequired,
                identityDelegate: identityDelegate,
                keyWrapper: keyWrapper,
                within: obvContext)

        case .allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(contactIdentities: let contactCryptoIds, fromOwnedIdentity: let ownedCryptoId, withUserContent: _, contactDeviceIdentifiersToExclude: let contactDeviceIdentifiersToExclude):
            
            let acceptableChannelsWithContacts = try getAcceptableConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(
                ownedCryptoId: ownedCryptoId,
                contactCryptoIds: contactCryptoIds,
                contactDeviceIdentifiersToExclude: contactDeviceIdentifiersToExclude,
                identityDelegate: identityDelegate,
                keyWrapper: keyWrapper,
                log: log,
                within: obvContext)

            acceptableChannels = acceptableChannelsWithContacts
            
        case .allConfirmedObliviousChannelsOrPreKeyChannelsWithOtherOwnedDevices(ownedIdentity: let ownedCryptoId):
            
            let acceptableChannelsWithOtherOwnedDevices = try getAcceptableConfirmedObliviousChannelsOrPreKeyChannelsWithOtherOwnedDevices(
                ownedCryptoId: ownedCryptoId,
                identityDelegate: identityDelegate,
                keyWrapper: keyWrapper,
                within: obvContext)

            acceptableChannels = acceptableChannelsWithOtherOwnedDevices

        case .allConfirmedObliviousChannelsOrPreKeyChannelsWithContactsAndWithOtherOwnedDevices(contactIdentities: let contactCryptoIds, fromOwnedIdentity: let ownedCryptoId, withUserContent: _, contactDeviceIdentifiersToExclude: let contactDeviceIdentifiersToExclude):
            
            let acceptableChannelsWithContacts = try getAcceptableConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(
                ownedCryptoId: ownedCryptoId,
                contactCryptoIds: contactCryptoIds,
                contactDeviceIdentifiersToExclude: contactDeviceIdentifiersToExclude,
                identityDelegate: identityDelegate,
                keyWrapper: keyWrapper,
                log: log,
                within: obvContext)
            
            let acceptableChannelsWithOtherOwnedDevices = try getAcceptableConfirmedObliviousChannelsOrPreKeyChannelsWithOtherOwnedDevices(
                ownedCryptoId: ownedCryptoId,
                identityDelegate: identityDelegate,
                keyWrapper: keyWrapper,
                within: obvContext)
            
            acceptableChannels = acceptableChannelsWithContacts + acceptableChannelsWithOtherOwnedDevices

        case .confirmedObliviousChannelOrPreKeyChannelWithContactDevice(contactDevice: let contactDevice):

            let acceptableChannelWithContact = try getAllAcceptableChannels(
                ownedCryptoId: contactDevice.ownedCryptoId,
                remoteCryptoId: contactDevice.contactCryptoId,
                remoteDeviceUIDs: Set([contactDevice.deviceUID]),
                necessarilyConfirmed: true,
                usePreKeyIfRequired: true,
                identityDelegate: identityDelegate,
                keyWrapper: keyWrapper,
                within: obvContext)
            
            assert(acceptableChannelWithContact.count == 1)
            
            return acceptableChannelWithContact
            
        case .confirmedObliviousChannelOrPreKeyChannelWithOtherOwnedDevice(otherOwnedDevice: let otherOwnedDevice, withUserContent: _):
            
            let acceptableChannelWithOtherOwnedDevice = try getAllAcceptableChannels(
                ownedCryptoId: otherOwnedDevice.ownedCryptoId,
                remoteCryptoId: otherOwnedDevice.ownedCryptoId,
                remoteDeviceUIDs: Set([otherOwnedDevice.deviceUID]),
                necessarilyConfirmed: true,
                usePreKeyIfRequired: true,
                identityDelegate: identityDelegate,
                keyWrapper: keyWrapper,
                within: obvContext)

            assert(acceptableChannelWithOtherOwnedDevice.count == 1)

            return acceptableChannelWithOtherOwnedDevice
            
        case .asymmetricChannel,
             .asymmetricChannelBroadcast,
             .local,
             .userInterface,
             .serverQuery:
            Self.logger.fault("Wrong message channel type")
            assertionFailure()
            acceptableChannels = []
        }
        
        return acceptableChannels
    }
    

    /// Helper methods for ``static ObvObliviousChannel.acceptableChannelsForPosting(_:delegateManager:within:)``
    private static func getAcceptableConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(ownedCryptoId: ObvCryptoIdentity, contactCryptoIds: Set<ObvCryptoIdentity>, contactDeviceIdentifiersToExclude: Set<ObvContactDeviceIdentifier>, identityDelegate: ObvIdentityDelegate, keyWrapper: any ObvKeyWrapperForIdentityDelegate, log: OSLog, within obvContext: ObvContext) throws -> [ObvChannel] {
        
        return contactCryptoIds.flatMap { contactCryptoId in
            
            let contactDeviceUIDsToExclude: Set<UID> = Set(contactDeviceIdentifiersToExclude
                .filter({ $0.ownedCryptoId.cryptoIdentity == ownedCryptoId })
                .filter({ $0.contactCryptoId.cryptoIdentity == contactCryptoId })
                .map(\.deviceUID))
            
            do {
                return try getAcceptableConfirmedObliviousChannelsOrPreKeyChannelsWithContact(
                    ownedCryptoId: ownedCryptoId,
                    contactCryptoId: contactCryptoId,
                    contactDeviceUIDsToExclude: contactDeviceUIDsToExclude,
                    identityDelegate: identityDelegate,
                    keyWrapper: keyWrapper,
                    log: log,
                    within: obvContext)
            } catch {
                assertionFailure()
                return []
            }
            
        }
        
    }


    /// Helper method for ``static getAcceptableConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(ownedCryptoId:contactCryptoIds:identityDelegate:keyWrapper:log:within:)``
    private static func getAcceptableConfirmedObliviousChannelsOrPreKeyChannelsWithContact(ownedCryptoId: ObvCryptoIdentity, contactCryptoId: ObvCryptoIdentity, contactDeviceUIDsToExclude: Set<UID>, identityDelegate: ObvIdentityDelegate, keyWrapper: any ObvKeyWrapperForIdentityDelegate, log: OSLog, within obvContext: ObvContext) throws -> [ObvChannel] {

        let contactDeviceUids = try identityDelegate.getDeviceUidsOfContactIdentity(contactCryptoId, ofOwnedIdentity: ownedCryptoId, within: obvContext)
            .filter({ !contactDeviceUIDsToExclude.contains($0) })
        
        guard !contactDeviceUids.isEmpty else { return [] }
        
        return try getAllAcceptableChannels(ownedCryptoId: ObvCryptoId(cryptoIdentity: ownedCryptoId),
                                            remoteCryptoId: ObvCryptoId(cryptoIdentity: contactCryptoId),
                                            remoteDeviceUIDs: contactDeviceUids,
                                            necessarilyConfirmed: true,
                                            usePreKeyIfRequired: true,
                                            identityDelegate: identityDelegate,
                                            keyWrapper: keyWrapper,
                                            within: obvContext)

    }

    
    /// Helper methods for ``static ObvObliviousChannel.acceptableChannelsForPosting(_:delegateManager:within:)``
    private static func getAcceptableConfirmedObliviousChannelsOrPreKeyChannelsWithOtherOwnedDevices(ownedCryptoId: ObvCryptoIdentity, identityDelegate: ObvIdentityDelegate, keyWrapper: any ObvKeyWrapperForIdentityDelegate, within obvContext: ObvContext) throws -> [ObvChannel] {
                
        let otherOwnedDeviceUIDs = try identityDelegate.getDeviceUidsOfOwnedIdentity(ownedCryptoId, within: obvContext)
        
        return try getAllAcceptableChannels(ownedCryptoId: ObvCryptoId(cryptoIdentity: ownedCryptoId),
                                            remoteCryptoId: ObvCryptoId(cryptoIdentity: ownedCryptoId),
                                            remoteDeviceUIDs: otherOwnedDeviceUIDs,
                                            necessarilyConfirmed: true,
                                            usePreKeyIfRequired: true,
                                            identityDelegate: identityDelegate,
                                            keyWrapper: keyWrapper,
                                            within: obvContext)
        
    }

    
    /// Helper method useds by all other methods in order to determine acceptable channels (pure ``ObvObliviousChannel`` as well as ``PreKeyChannel`` if possible).
    private static func getAllAcceptableChannels(ownedCryptoId: ObvCryptoId, remoteCryptoId: ObvCryptoId, remoteDeviceUIDs: Set<UID>, necessarilyConfirmed: Bool, usePreKeyIfRequired: Bool, identityDelegate: ObvIdentityDelegate, keyWrapper: any ObvKeyWrapperForIdentityDelegate, within obvContext: ObvContext) throws -> [ObvChannel] {
        
        guard try identityDelegate.isOwned(ownedCryptoId.cryptoIdentity, within: obvContext) else {
            throw ObvError.cryptoIdentityIsNotOwned
        }

        let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedCryptoId.cryptoIdentity, within: obvContext)
        
        // Determine all the appropriate available Oblivious channels
        
        let obliviousChannels: [ObvObliviousChannel]
        
        do {
            let channels = try ObvObliviousChannel.get(
                currentDeviceUID: currentDeviceUid,
                remoteCryptoId: remoteCryptoId,
                remoteDeviceUIDs: Array(remoteDeviceUIDs),
                necessarilyConfirmed: necessarilyConfirmed,
                within: obvContext.context)
            
            let acceptableChannels = channels.filter {
                $0.cryptoSuiteVersion >= ObvCryptoSuite.sharedInstance.minAcceptableVersion
            }
            obliviousChannels = acceptableChannels
        }
        
        // If we are not allowed to use pre-keys, we return the oblivious channels
        
        guard usePreKeyIfRequired else {
            return obliviousChannels
        }
        
        // If we have an oblivious channel with each device, we are done
        
        let devicesWithoutChannel = Set(remoteDeviceUIDs).subtracting(Set( try obliviousChannels.map({ try $0.remoteDeviceUID })))

        guard !devicesWithoutChannel.isEmpty else {
            return obliviousChannels
        }

        // If we reach this point, we have no oblivious channel with at least one remote device and we are allowed to use PreKey channels instead

        let preKeyChannels: [PreKeyChannel]
        
        do {

            let devicesWithPrekeys = try identityDelegate.getUIDsOfRemoteDevicesForWhichHavePreKeys(
                ownedCryptoId: ownedCryptoId.cryptoIdentity,
                remoteCryptoId: remoteCryptoId.cryptoIdentity,
                within: obvContext)
            let devicesForPreKeys = devicesWithoutChannel.intersection(devicesWithPrekeys)
            preKeyChannels = devicesForPreKeys.map { remoteDeviceUID in
                PreKeyChannel(keyWrapper: keyWrapper,
                              remoteDeviceUID: remoteDeviceUID,
                              remoteCryptoId: remoteCryptoId.cryptoIdentity,
                              ownedIdentity: ownedCryptoId.cryptoIdentity,
                              obvContext: obvContext)
            }

        } catch {
            assertionFailure()
            return obliviousChannels
        }
     
        // We return all the acceptable channels we found
        
        return obliviousChannels + preKeyChannels
        
    }
    
}


// MARK: - Managing notifications and calls to delegates

extension ObvObliviousChannel {
    

    public override func willSave() {
        super.willSave()
        changedKeys = Set<String>(self.changedValues().keys)
    }

    override func didSave() {
        super.didSave()
        
        defer {
            changedKeys.removeAll()
            requestFullRatchetOfTheSendSeedOnSave = false
        }
        
        if isDeleted {
            //assertionFailure("This assertion shall be deleted. We are just trying to understand when a channel can be deleted")
        }
        
        guard let delegateManager = Self.delegateManager else {
            Self.logger.fault("The delegate manager is nil")
            assertionFailure()
            return
        }
                
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            Self.logger.fault("The notification delegate is not set")
            assertionFailure()
            return
        }
        
        if requestFullRatchetOfTheSendSeedOnSave {
            if let fullRatchetProtocolStarterDelegate = delegateManager.fullRatchetProtocolStarterDelegate {
                do {
                    let currentDeviceUid = try self.currentDeviceUID
                    let remoteDeviceUid = try self.remoteDeviceUID
                    let remoteCryptoIdentity = try self.remoteCryptoId.cryptoIdentity
                    DispatchQueue(label: "Queue for starting a full ratchet of the current (send) Oblivious channel").async {
                        do {
                            Self.logger.info("Sending a request to start a full ratchet protocol")
                            try fullRatchetProtocolStarterDelegate.startFullRatchetProtocolForObliviousChannelBetween(
                                currentDeviceUid: currentDeviceUid,
                                andRemoteDeviceUid: remoteDeviceUid,
                                ofRemoteIdentity: remoteCryptoIdentity)
                        } catch {
                            Self.logger.fault("Could not start full ratchet protocol: \(error)")
                            assertionFailure()
                        }
                    }
                } catch {
                    Self.logger.fault("Could not start full ratchet protocol: \(error)")
                }
            } else {
                Self.logger.fault("The Oblivious Channel Full Ratchet Protocol Starter Delegate is not set")
                assertionFailure()
            }
        }
        
        if self.isConfirmed && changedKeys.contains(Predicate.Key.isConfirmed.rawValue) {
            
            Self.logger.debug("Posting a newConfirmedObliviousChannel notification")
            do {
                try ObvChannelNotification.newConfirmedObliviousChannel(
                    currentDeviceUid: currentDeviceUID,
                    remoteCryptoIdentity: remoteCryptoId.cryptoIdentity,
                    remoteDeviceUid: remoteDeviceUID)
                .postOnBackgroundQueue(within: notificationDelegate)
            } catch {
                Self.logger.error("Could not post a newConfirmedObliviousChannel notification: \(error)")
            }

        } else if isDeleted && self.isConfirmed {
            
            Self.logger.debug("Posting a deletedConfirmedObliviousChannel notification")
            do {
                try ObvChannelNotification.deletedConfirmedObliviousChannel(
                    currentDeviceUid: currentDeviceUID,
                    remoteCryptoIdentity: remoteCryptoId.cryptoIdentity,
                    remoteDeviceUid: remoteDeviceUID)
                .postOnBackgroundQueue(within: notificationDelegate)
            } catch {
                Self.logger.error("Could not post a deletedConfirmedObliviousChannel notification: \(error)")
            }

        }
        
    }
    
}
