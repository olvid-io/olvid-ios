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
import CoreData
import ObvMetaManager
import ObvCrypto
import ObvEncoder


// MARK: - AbstractPreKey

@objc(PreKeyAbstract)
class PreKeyAbstract: NSManagedObject {
    
    // MARK: Attributes

    @NSManaged private var rawPreKeyId: Data? // Expected to be non-nil
    @NSManaged private var rawPreKeyEncryptionKey: Data?  // Expected to be non-nil
    @NSManaged private var rawPreKeyExpirationTimestamp: Date?  // Expected to be non-nil
    
    var cryptoKeyId: CryptoKeyId? {
        guard let rawPreKeyId else { assertionFailure(); return nil }
        return CryptoKeyId(rawPreKeyId)
    }
    
    var expirationTimestamp: Date? {
        rawPreKeyExpirationTimestamp
    }
    
    fileprivate var encryptionKey: PublicKeyForPublicKeyEncryption? {
        guard let rawPreKeyEncryptionKey else { assertionFailure(); return nil }
        guard let encoded = ObvEncoded(withRawData: rawPreKeyEncryptionKey) else { assertionFailure(); return nil }
        guard let key = PublicKeyForPublicKeyEncryptionDecoder.obvDecode(encoded) else { assertionFailure(); return nil }
        return key
    }

    // MARK: Initializers

    fileprivate convenience init(devicePreKey: DevicePreKey, entityName: String, within context: NSManagedObjectContext) {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.rawPreKeyId = devicePreKey.keyId.raw
        self.rawPreKeyEncryptionKey = devicePreKey.encryptionKey.obvEncode().rawData
        self.rawPreKeyExpirationTimestamp = devicePreKey.expirationTimestamp

    }
    
    // Using this pre-key
    
    fileprivate func wrap(_ messageKey: any AuthenticatedEncryptionKey, with ownedPrivateKeyForAuthentication: any PrivateKeyForAuthentication, and ownedPublicKeyForAuthentication: any PublicKeyForAuthentication, prng: any PRNGService, toDeviceUID: UID, toIdentity: ObvCryptoIdentity, currentDeviceUID: UID, ownedCryptoId: ObvCryptoIdentity) throws -> EncryptedData? {
        
        guard let encryptionKey else { assertionFailure(); return nil }
        guard let cryptoKeyId else { assertionFailure(); return nil }
        
        
        let encodedToSend = [
            messageKey,
            currentDeviceUID,
            ownedCryptoId
        ].obvEncode()

        guard let response = ObvSolveChallengeStruct.solveChallenge(
            .encryptionWithPreKey(encodedToSend: encodedToSend,
                                  toIdentity: toIdentity,
                                  toDeviceUID: toDeviceUID,
                                  preKeyId: cryptoKeyId),
            with: ownedPrivateKeyForAuthentication,
            and: ownedPublicKeyForAuthentication,
            using: prng) else {
            assertionFailure()
            throw ObvError.couldNotSolveChallenge
        }
        
        let plaintext = [
            encodedToSend,
            response.obvEncode(),
        ].obvEncode().rawData
        
        guard let encryptedMessageKey = PublicKeyEncryption.encrypt(plaintext, using: encryptionKey, and: prng) else {
            assertionFailure()
            return nil
        }

        let wrappedMessageKey = cryptoKeyId.concat(with: encryptedMessageKey)

        return wrappedMessageKey
        
    }
        
    // Errors
    
    enum ObvError: Error {
        case couldNotSolveChallenge
    }
    
    
    struct Predicate {
        enum Key: String {
            case rawPreKeyExpirationTimestamp = "rawPreKeyExpirationTimestamp"
        }
    }

}


// MARK: - PreKeyForContactDevice: AbstractPreKey

@objc(PreKeyForContactDevice)
final class PreKeyForContactDevice: PreKeyAbstract {
    
    private static let entityName = "PreKeyForContactDevice"

    // MARK: Relationship
    
    @NSManaged private var contactDevice: ContactDevice? // Expected to be non-nil

    
    // MARK: Initializers

    convenience init(deviceBlobOnServer: DeviceBlobOnServer, forContactDevice contactDevice: ContactDevice) throws {
        
        guard let context = contactDevice.managedObjectContext else {
            assertionFailure()
            throw ObvError.noContext
        }

        // Check the signature of the PreKey on server
        
        guard let cryptoIdentity = contactDevice.contactIdentity?.cryptoIdentity else {
            assertionFailure()
            throw ObvError.noOwnedCryptoId
        }

        try deviceBlobOnServer.checkChallengeResponse(for: cryptoIdentity)

        // Check the match between the UIDs
        
        let devicePreKey = deviceBlobOnServer.deviceBlob.devicePreKey
        
        guard contactDevice.uid == devicePreKey.deviceUID else {
            assertionFailure()
            throw ObvError.uidMismatch
        }

        // All checks passed
        
        self.init(devicePreKey: devicePreKey, entityName: Self.entityName, within: context)
        
        self.contactDevice = contactDevice

    }
    
    
    func deletePreKeyForContactDevice() throws {
        guard let context = self.managedObjectContext else { assertionFailure(); throw ObvError.noContext }
        context.delete(self)
    }

    
    // MARK: Errors
    
    enum ObvError: Error {
        case noContext
        case uidMismatch
        case noOwnedCryptoId
        case noContactCryptoId
        case encryptionFailed
        case noContactDevice
        case noContactIdentity
        case noOwnedIdentity
    }
    
    
    // Using this pre-key
    
    func wrap(_ messageKey: any AuthenticatedEncryptionKey, with ownedPrivateKeyForAuthentication: any PrivateKeyForAuthentication, and ownedPublicKeyForAuthentication: any PublicKeyForAuthentication, prng: any PRNGService) throws -> EncryptedData? {
                
        guard let contactDevice else {
            assertionFailure()
            throw ObvError.noContactDevice
        }
        
        let toDeviceUID = contactDevice.uid
        
        guard let contactIdentity = contactDevice.contactIdentity else {
            assertionFailure()
            throw ObvError.noContactIdentity
        }
        
        guard let toIdentity = contactIdentity.cryptoIdentity else {
            assertionFailure()
            throw ObvError.noContactCryptoId
        }
        
        guard let ownedIdentity = contactIdentity.ownedIdentity else {
            assertionFailure()
            throw ObvError.noOwnedIdentity
        }
        
        let currentDeviceUID = ownedIdentity.currentDeviceUid
        
        let ownedCryptoId = ownedIdentity.cryptoIdentity

        let wrappedMessageKey = try self.wrap(messageKey,
                                              with: ownedPrivateKeyForAuthentication,
                                              and: ownedPublicKeyForAuthentication,
                                              prng: prng,
                                              toDeviceUID: toDeviceUID,
                                              toIdentity: toIdentity,
                                              currentDeviceUID: currentDeviceUID,
                                              ownedCryptoId: ownedCryptoId)

        return wrappedMessageKey
        
    }

}


// MARK: - PreKeyForRemoteOwnedDevice: AbstractPreKey

@objc(PreKeyForRemoteOwnedDevice)
final class PreKeyForRemoteOwnedDevice: PreKeyAbstract {
    
    private static let entityName = "PreKeyForRemoteOwnedDevice"

    // MARK: Relationship
    
    @NSManaged private var remoteOwnedDevice: OwnedDevice? // Expected to be non-nil

    
    // MARK: Initializers

    convenience init(deviceBlobOnServer: DeviceBlobOnServer, forRemoteOwnedDevice ownedDevice: OwnedDevice) throws {
        
        guard let context = ownedDevice.managedObjectContext else {
            assertionFailure()
            throw ObvError.noContext
        }
        
        // Check the signature of the PreKey on server
        
        guard let cryptoIdentity = ownedDevice.identity?.cryptoIdentity else {
            assertionFailure()
            throw ObvError.noOwnedCryptoId
        }
        
        try deviceBlobOnServer.checkChallengeResponse(for: cryptoIdentity)
        
        // Check the match between the UIDs
        
        let devicePreKey = deviceBlobOnServer.deviceBlob.devicePreKey
        
        guard ownedDevice.uid == devicePreKey.deviceUID else {
            assertionFailure()
            throw ObvError.uidMismatch
        }
        
        // All checks passed
        
        self.init(devicePreKey: devicePreKey, entityName: Self.entityName, within: context)
        
        self.remoteOwnedDevice = ownedDevice
        
    }
    
    
    func deletePreKeyForRemoteOwnedDevice() throws {
        guard let context = self.managedObjectContext else { assertionFailure(); throw ObvError.noContext }
        context.delete(self)
    }
    
    
    // Using this pre-key

    func wrap(_ messageKey: any AuthenticatedEncryptionKey, with ownedPrivateKeyForAuthentication: any PrivateKeyForAuthentication, and ownedPublicKeyForAuthentication: any PublicKeyForAuthentication, prng: any PRNGService) throws -> EncryptedData? {
        
        guard let remoteOwnedDevice else {
            assertionFailure()
            throw ObvError.noRemoteOwnedDevice
        }
        
        let toDeviceUID = remoteOwnedDevice.uid
        
        guard let ownedIdentity = remoteOwnedDevice.identity else {
            assertionFailure()
            throw ObvError.noOwnedIdentity
        }
        
        let ownedCryptoId = ownedIdentity.ownedCryptoIdentity.getObvCryptoIdentity()
        
        let currentDeviceUID = ownedIdentity.currentDeviceUid
        
        let wrappedMessageKey = try self.wrap(messageKey,
                                              with: ownedPrivateKeyForAuthentication,
                                              and: ownedPublicKeyForAuthentication,
                                              prng: prng,
                                              toDeviceUID: toDeviceUID,
                                              toIdentity: ownedCryptoId,
                                              currentDeviceUID: currentDeviceUID,
                                              ownedCryptoId: ownedCryptoId)

        return wrappedMessageKey

        
    }
    
    // MARK: Errors
    
    enum ObvError: Error {
        case noContext
        case uidMismatch
        case noOwnedCryptoId
        case noRemoteOwnedDevice
        case noOwnedIdentity
    }
    
}


// MARK: - PreKeyForCurrentOwnedDevice: AbstractPreKey

@objc(PreKeyForCurrentOwnedDevice)
final class PreKeyForCurrentOwnedDevice: PreKeyAbstract {
    
    private static let entityName = "PreKeyForCurrentOwnedDevice"

    // MARK: Attributes

    @NSManaged private var rawPreKeyDecryptionKey: Data?  // Expected to be non-nil
    @NSManaged private var rawServerTimestampOnCreation: Date? // Expected to be non-nil

    // MARK: Relationship
    
    @NSManaged private var currentOwnedDevice: OwnedDevice? // Expected to be non-nil
    
    
    // MARK: Accessors
    
    var serverTimestampOnCreation: Date {
        assert(rawServerTimestampOnCreation != nil)
        return rawServerTimestampOnCreation ?? .distantPast
    }

    
    private var privateKeyForPublicKeyEncryption: PrivateKeyForPublicKeyEncryption? {
        guard let rawPreKeyDecryptionKey else { assertionFailure(); return nil }
        guard let encodedPreKeyDecryptionKey = ObvEncoded(withRawData: rawPreKeyDecryptionKey) else { assertionFailure(); return nil }
        guard let privateKey = PrivateKeyForPublicKeyEncryptionDecoder.obvDecode(encodedPreKeyDecryptionKey) else { assertionFailure(); return nil }
        return privateKey
    }
    
    // MARK: Initializers

    private convenience init(currentOwnedDevice: OwnedDevice, devicePreKeyDecryptionKey: PrivateKeyForPublicKeyEncryption, devicePreKey: DevicePreKey, serverCurrentTimestamp: Date) throws {
        
        guard let context = currentOwnedDevice.managedObjectContext else {
            assertionFailure()
            throw ObvError.noContext
        }

        self.init(devicePreKey: devicePreKey, entityName: Self.entityName, within: context)
        
        self.rawPreKeyDecryptionKey = devicePreKeyDecryptionKey.obvEncode().rawData
        self.currentOwnedDevice = currentOwnedDevice
        self.rawServerTimestampOnCreation = serverCurrentTimestamp
        
    }
    
    
    static func createPreKeyForCurrentOwnedDevice(forCurrentOwnedDevice currentOwnedDevice: OwnedDevice, serverCurrentTimestamp: Date, prng: PRNGService) throws -> DevicePreKey {
        
        let expirationTimestamp = serverCurrentTimestamp.addingTimeInterval(ObvConstants.preKeyValidityTimeInterval)
        let (devicePreKey, sk) = DevicePreKey.generate(prng: prng, forDeviceUID: currentOwnedDevice.uid, withExpirationTimestamp: expirationTimestamp)
        
        _ = try self.init(currentOwnedDevice: currentOwnedDevice, devicePreKeyDecryptionKey: sk, devicePreKey: devicePreKey, serverCurrentTimestamp: serverCurrentTimestamp)
        
        return devicePreKey
        
    }
    
    
    func deletePreKeyForCurrentOwnedDevice() throws {
        guard let context = self.managedObjectContext else { assertionFailure(); throw ObvError.noContext }
        context.delete(self)
    }
    
    
    // Using this pre-key
    
    static func unwrapMessageKey(_ wrappedMessageKey: EncryptedData, forCurrentOwnedDevice currentOwnedDevice: OwnedDevice) throws -> (messageKey: any AuthenticatedEncryptionKey, remoteCryptoId: ObvCryptoIdentity, remoteDeviceUID: UID)? {
        
        guard let (encryptedMessageKey, cryptoKeyId) = CryptoKeyId.parse(wrappedMessageKey) else { return nil }
        
        let preKeyCandidates = try Self.fetchPreKeysForCurrentOwnedDevice(currentOwnedDevice, withCryptoKeyId: cryptoKeyId)
        
        for preKeyCandidate in preKeyCandidates {
            if let (messageKey, remoteCryptoId, remoteDeviceUID) = try? preKeyCandidate.unwrapMessageKey(encryptedMessageKey) {
                return (messageKey, remoteCryptoId, remoteDeviceUID)
            }
        }
        
        return nil
        
    }
    
    
    private func unwrapMessageKey(_ encryptedMessageKey: EncryptedData) throws -> (messageKey: any AuthenticatedEncryptionKey, remoteCryptoId: ObvCryptoIdentity, remoteDeviceUID: UID)? {
        
        guard let privateKeyForPublicKeyEncryption else { assertionFailure(); return nil }
        
        guard let plaintext = PublicKeyEncryption.decrypt(encryptedMessageKey, using: privateKeyForPublicKeyEncryption) else { return nil }
        
        guard let plaintextAsEncoded = ObvEncoded(withRawData: plaintext) else { assertionFailure(); return nil }
        
        guard let listOfEncoded = [ObvEncoded](plaintextAsEncoded) else { assertionFailure(); return nil }
        
        guard listOfEncoded.count == 2 else { assertionFailure(); return nil }
        
        let encodedToSend = listOfEncoded[0]
        let response: Data = try listOfEncoded[1].obvDecode()
        
        // Parse the "encodedToSend"
        
        guard let innerListOfEncoded = [ObvEncoded](encodedToSend) else { assertionFailure(); return nil }
        guard innerListOfEncoded.count == 3 else { assertionFailure(); return nil }
        
        let messageKey = try AuthenticatedEncryptionKeyDecoder.decode(innerListOfEncoded[0])
        let remoteDeviceUID: UID = try innerListOfEncoded[1].obvDecode()
        let remoteCryptoId: ObvCryptoIdentity = try innerListOfEncoded[2].obvDecode()
        
        // Collect necessary data
        
        guard let currentOwnedDevice else {
            assertionFailure()
            throw ObvError.noCurrentOwnedDevice
        }
        
        let toDeviceUID = currentOwnedDevice.uid
        
        guard let ownedIdentity = currentOwnedDevice.identity else {
            assertionFailure()
            throw ObvError.noOwnedIdentity
        }
        
        let toIdentity = ownedIdentity.ownedCryptoIdentity.getObvCryptoIdentity()
        
        guard let cryptoKeyId else {
            assertionFailure()
            throw ObvError.noCryptoKeyId
        }

        // Check the signature
        
        guard ObvSolveChallengeStruct.checkResponse(response, to: .encryptionWithPreKey(encodedToSend: encodedToSend, toIdentity: toIdentity, toDeviceUID: toDeviceUID, preKeyId: cryptoKeyId), from: remoteCryptoId) else {
            assertionFailure()
            throw ObvError.invalidChallengeResponse
        }
        
        // Return found values
        
        return (messageKey, remoteCryptoId, remoteDeviceUID)
        
    }


    /// Expected to be non-nil
    var preKey: DevicePreKey? {
        guard let cryptoKeyId,
              let encryptionKey,
              let deviceUID = currentOwnedDevice?.uid,
              let expirationTimestamp else {
            assertionFailure()
            return nil
        }
        return .init(keyId: cryptoKeyId,
                     encryptionKey: encryptionKey,
                     deviceUID: deviceUID,
                     expirationTimestamp: expirationTimestamp)
    }

    // MARK: Errors
    
    enum ObvError: Error {
        case noContext
        case uidMismatch
        case noOwnedCryptoId
        case noCurrentOwnedDevice
        case noOwnedIdentity
        case noCryptoKeyId
        case invalidChallengeResponse
    }
    
    
    // MARK: - Convenience DB getters

    @nonobjc class func fetchRequest() -> NSFetchRequest<PreKeyForCurrentOwnedDevice> {
        return NSFetchRequest<PreKeyForCurrentOwnedDevice>(entityName: PreKeyForCurrentOwnedDevice.entityName)
    }

    struct Predicate {
        enum Key: String {
            case rawPreKeyId = "rawPreKeyId"
            case currentOwnedDevice = "currentOwnedDevice"
        }
        fileprivate static func withCryptoKeyId(_ cryptoKeyId: CryptoKeyId) -> NSPredicate {
            NSPredicate(Key.rawPreKeyId, EqualToData: cryptoKeyId.raw)
        }
        fileprivate static func withCurrentOwnedDevice(_ currentOwnedDevice: OwnedDevice) -> NSPredicate {
            NSPredicate(Key.currentOwnedDevice, equalTo: currentOwnedDevice)
        }
        fileprivate static var withoutExpirationTimestamp: NSPredicate {
            NSPredicate(withNilValueForKey: PreKeyAbstract.Predicate.Key.rawPreKeyExpirationTimestamp)
        }
        fileprivate static func withExpirationTimestamp(earlierThan date: Date) -> NSPredicate {
            NSPredicate(PreKeyAbstract.Predicate.Key.rawPreKeyExpirationTimestamp, earlierThan: date)
        }
    }

    
    private static func fetchPreKeysForCurrentOwnedDevice(_ currentOwnedDevice: OwnedDevice, withCryptoKeyId cryptoKeyId: CryptoKeyId) throws -> Set<PreKeyForCurrentOwnedDevice> {
        guard let context = currentOwnedDevice.managedObjectContext else {
            assertionFailure()
            throw ObvError.noContext
        }
        let request: NSFetchRequest<PreKeyForCurrentOwnedDevice> = PreKeyForCurrentOwnedDevice.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withCurrentOwnedDevice(currentOwnedDevice),
            Predicate.withCryptoKeyId(cryptoKeyId),
        ])
        request.fetchBatchSize = 500
        let items = try context.fetch(request)
        return Set(items)
    }
    
    
    static func deleteExpiredPreKeysForCurrentOwnedDevice(_ currentOwnedDevice: OwnedDevice, downloadTimestampFromServer: Date) throws {
        guard let context = currentOwnedDevice.managedObjectContext else {
            assertionFailure()
            throw ObvError.noContext
        }
        // We delete keys s.t. now > rawPreKeyExpirationTimestamp + preKeyForCurrentDeviceConservationGracePeriod
        let request: NSFetchRequest<PreKeyForCurrentOwnedDevice> = PreKeyForCurrentOwnedDevice.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withCurrentOwnedDevice(currentOwnedDevice),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                Predicate.withoutExpirationTimestamp,
                Predicate.withExpirationTimestamp(earlierThan: downloadTimestampFromServer.addingTimeInterval(-ObvConstants.preKeyForCurrentDeviceConservationGracePeriod))
            ])
        ])
        request.fetchBatchSize = 500
        request.propertiesToFetch = []
        let items = try context.fetch(request)
        try items.forEach { item in
            try item.deletePreKeyForCurrentOwnedDevice()
        }
    }
    
}
