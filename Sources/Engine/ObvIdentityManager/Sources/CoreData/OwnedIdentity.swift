/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvEncoder
@preconcurrency import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils
import ObvJWS

@objc(OwnedIdentity)
final class OwnedIdentity: NSManagedObject, ObvErrorMaker {
    
    // MARK: Internal constants
    
    static weak var delegateManager: ObvIdentityDelegateManager?
    
    private static let entityName = "OwnedIdentity"
    static let errorDomain = String(describing: OwnedIdentity.self)

    private static var logSubsystem: String { delegateManager?.logSubsystem ?? ObvIdentityDelegateManager.defaultLogSubsystem }
    private static var logger: Logger = { Logger(subsystem: OwnedIdentity.logSubsystem, category: "OwnedIdentity") }()

    // MARK: Attributes
    
    @NSManaged private(set) var isActive: Bool // true iff the current device is registered on the server
    @NSManaged private var isDeletionInProgress: Bool
    @NSManaged private var rawBackupSeed: Data? // Non nil in the model
    @NSManaged private var rawCryptoIdentity: Data? // Non-optional in the model Unique (not enforced). Must be coherent with rawOwnedCryptoIdentity
    @NSManaged private var rawOwnedCryptoIdentity: Data? // Non-optional in the model, raw value of the encoding of an `ObvOwnedCryptoIdentity`. Must be coherent with rawCryptoIdentity.

    // MARK: Relationships
    
    @NSManaged private(set) var keycloakServer: KeycloakServer?
    @NSManaged private(set) var contactGroups: Set<ContactGroup>
    @NSManaged private(set) var contactGroupsV2: Set<ContactGroupV2>
    @NSManaged private(set) var contactIdentities: Set<ContactIdentity>
    @NSManaged private(set) var currentDevice: OwnedDevice
    @NSManaged private(set) var otherDevices: Set<OwnedDevice>
    @NSManaged private(set) var publishedIdentityDetails: OwnedIdentityDetailsPublished

    // MARK: Other variables
    
    var cryptoIdentity: ObvCryptoIdentity {
        get throws(ObvError) {
            guard let rawCryptoIdentity else { assertionFailure(); throw .unexpectedNilValue }
            guard let cryptoIdentity = ObvCryptoIdentity(from: rawCryptoIdentity) else { assertionFailure(); throw .couldNotParseValue }
            return cryptoIdentity
        }
    }
    
    var ownedCryptoIdentity: ObvOwnedCryptoIdentity {
        get throws(ObvError) {
            guard let rawOwnedCryptoIdentity else { assertionFailure(); throw .unexpectedNilValue }
            guard let encodedList = ObvEncoded(withRawData: rawOwnedCryptoIdentity) else { assertionFailure(); throw .couldNotParseValue }
            guard let ownedCryptoIdentity = ObvOwnedCryptoIdentity(encodedList) else { assertionFailure(); throw .couldNotParseValue }
            return ownedCryptoIdentity
        }
    }
    
    var currentDeviceUid: UID {
        get throws {
            return try currentDevice.uid
        }
    }

    private var changedKeys = Set<String>()
    private var ownedIdentityOnDeletion: ObvCryptoIdentity?
    
    var backupSeed: BackupSeed {
        get throws {
            guard let rawBackupSeed else {
                throw ObvError.rawBackupSeedIsNil
            }
            guard let backupSeed = BackupSeed(with: rawBackupSeed) else {
                throw ObvError.backupSeedParsingFailed
            }
            return backupSeed
        }
    }
    
    // MARK: - Initializer
    
    /// This initializer purpose is to create a longterm owned identity
    convenience init?(serverURL: URL, identityDetails: ObvIdentityDetails, accordingTo pkEncryptionImplemByteId: PublicKeyEncryptionImplementationByteId, and authEmplemByteId: AuthenticationImplementationByteId, keycloakState: ObvKeycloakState?, nameForCurrentDevice: String, using prng: PRNGService, within context: NSManagedObjectContext) {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: OwnedIdentity.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        let ownedCryptoIdentity = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL,
                                                             forAuthenticationImplementationId: authEmplemByteId,
                                                             andPublicKeyEncryptionImplementationByteId: pkEncryptionImplemByteId,
                                                             using: prng)
        let cryptoIdentity = ownedCryptoIdentity.getObvCryptoIdentity()

        self.rawBackupSeed = prng.genBackupSeed().raw
        self.isActive = true // An owned identity is always active on creation. Several places within the engine assume this behaviour.
        self.isDeletionInProgress = false
        self.rawCryptoIdentity = cryptoIdentity.getIdentity()
        self.rawOwnedCryptoIdentity = ownedCryptoIdentity.obvEncode().rawData

        self.contactIdentities = Set<ContactIdentity>()
        guard let device = OwnedDevice.createCurrentOwnedDevice(ownedIdentity: self, name: nameForCurrentDevice, with: prng) else {
            Self.logger.fault("Could not create a current device for the new owned identity")
            assertionFailure()
            return nil
        }
        self.currentDevice = device
        self.otherDevices = Set<OwnedDevice>()
        self.contactGroups = Set<ContactGroup>()
        guard let publishedIdentityDetails = OwnedIdentityDetailsPublished(ownedIdentity: self, identityDetails: identityDetails, version: 0) else { return nil }
        self.publishedIdentityDetails = publishedIdentityDetails
        if let keycloakState = keycloakState {
            do {
                self.keycloakServer = try KeycloakServer(keycloakState: keycloakState, managedOwnedIdentity: self)
            } catch {
                Self.logger.fault("Could not create a KeycloakServer for the new owned identity")
                return nil
            }
        } else {
            self.keycloakServer = nil
        }
    }
    
    
    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    convenience init(backupItem: OwnedIdentityBackupItem, prng: PRNGService, within context: NSManagedObjectContext) throws {
        let entityDescription = NSEntityDescription.entity(forEntityName: OwnedIdentity.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.isActive = backupItem.isActive
        self.isDeletionInProgress = false
        self.rawCryptoIdentity = backupItem.cryptoIdentity.getIdentity()
        self.rawBackupSeed = backupItem.backupSeed.raw
        guard let ownedCryptoIdentity = backupItem.ownedCryptoIdentity else {
            throw OwnedIdentity.makeError(message: "Could not recover owned crypto identity")
        }
        self.rawOwnedCryptoIdentity = ownedCryptoIdentity.obvEncode().rawData
    }

    
    fileprivate func restoreRelationships(contactGroups: Set<ContactGroup>, contactGroupsV2: Set<ContactGroupV2>, contactIdentities: Set<ContactIdentity>, currentDevice: OwnedDevice, publishedIdentityDetails: OwnedIdentityDetailsPublished, keycloakServer: KeycloakServer?) {
        self.contactGroups = contactGroups
        self.contactGroupsV2 = contactGroupsV2
        self.contactIdentities = contactIdentities
        self.currentDevice = currentDevice
        /* maskingUid is nil */
        self.otherDevices = Set<OwnedDevice>()
        self.publishedIdentityDetails = publishedIdentityDetails
        self.keycloakServer = keycloakServer
    }
    
    
    private var isInsertedWhileRestoringSyncSnapshot = false
    
    /// Used *exclusively* during a snapshot restore for creating an instance. Relatioships are recreated in a second step.
    convenience init(cryptoIdentity: ObvCryptoIdentity, snapshotNode: OwnedIdentitySyncSnapshotNode, within context: NSManagedObjectContext) throws {

        let entityDescription = NSEntityDescription.entity(forEntityName: OwnedIdentity.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.isActive = true
        self.isDeletionInProgress = false
        self.rawCryptoIdentity = cryptoIdentity.getIdentity()
        self.rawBackupSeed = snapshotNode.backupSeed.raw
        guard let ownedCryptoIdentity = snapshotNode.privateIdentity?.getOwnedIdentity(cryptoIdentity: cryptoIdentity) else {
            throw OwnedIdentity.makeError(message: "Could not recover owned crypto identity")
        }
        self.rawOwnedCryptoIdentity = ownedCryptoIdentity.obvEncode().rawData
        
        // Prevents the sending of notifications
        isInsertedWhileRestoringSyncSnapshot = true
        
    }
    
    
    /// When the user requests the deletion of an owned identity, a cryptographic protocol starts. The first action is to mark the owned identity for deletion before evenutally deleting it.
    ///
    /// This makes is possible to have a very responsive UI.
    func markForDeletion() {
        guard !isDeletionInProgress else { return }
        isDeletionInProgress = true
    }

    
    func delete(within context: NSManagedObjectContext) throws {
        guard isDeletionInProgress else { assertionFailure(); throw Self.makeError(message: "Request the deletion of an owned identity that was not marked for deletion") }
        try publishedIdentityDetails.delete(within: context)
        context.delete(self)
    }
    
    
    // MARK: - Observers
    
    private static var observersHolder = ObserversHolder()
    
    static func addObvObserver(_ newObserver: OwnedIdentityObserver) async {
        await observersHolder.addObserver(newObserver)
    }

}


// MARK: - Details and owned identity management

extension OwnedIdentity {
    
    func updatePublishedDetailsWithNewDetails(_ newIdentityDetails: ObvIdentityDetails) throws {
        try self.publishedIdentityDetails.updateWithNewIdentityDetails(newIdentityDetails)
    }
    
    
    /// Returns `true` if we need to download a new profile picture
    func updatePublishedDetailsWithOtherDetailsIfNewer(otherDetails: IdentityDetailsElements) throws -> Bool {
        let photoDownloadNeeded = try self.publishedIdentityDetails.updateWithOtherDetailsIfNewer(otherDetails: otherDetails)
        return photoDownloadNeeded
    }

    
    func saveRegisteredKeycloakAPIKey(apiKey: UUID) throws {
        guard self.isKeycloakManaged, let keycloakServer else {
            assertionFailure()
            throw ObvIdentityManagerError.ownedIdentityIsNotKeycloakManaged
        }
        keycloakServer.saveRegisteredKeycloakAPIKey(apiKey: apiKey)
    }
    

    func updatePhoto(withData photoData: Data, version: Int, within context: NSManagedObjectContext) throws {
        if self.publishedIdentityDetails.version == version {
            try self.publishedIdentityDetails.setOwnedIdentityPhoto(data: photoData)
        }
    }

    
    func deactivateAndDeleteAllContactDevices() {

        if isActive {
            isActive = false
        }
        
        /* After deactivating an owned identity, we must delete all devices */
        
        self.otherDevices.forEach { otherOwnedDevice in
            try? otherOwnedDevice.deleteThisDevice()
        }
        
        self.contactIdentities.forEach { contactIdentity in
            contactIdentity.devices.forEach { contactDevice in
                try? contactDevice.deleteContactDevice()
            }
        }
    }
    
    func reactivate() {
        if !isActive {
            isActive = true
        }
    }

}


// MARK: - Sync between owned devices

extension OwnedIdentity {
    
    func processSyncAtom(_ syncAtom: ObvSyncAtom) throws {
        
        guard syncAtom.recipient == .identityManager else {
            assertionFailure()
            throw ObvIdentityManagerError.wrongSyncAtomRecipient
        }
        
        switch syncAtom {
        case .contactNickname,
                .groupV1Nickname,
                .groupV2Nickname,
                .contactPersonalNote,
                .groupV1PersonalNote,
                .groupV2PersonalNote,
                .ownProfileNickname,
                .contactCustomHue,
                .contactSendReadReceipt,
                .groupV1ReadReceipt,
                .groupV2ReadReceipt,
                .settingDefaultSendReadReceipts,
                .settingAutoJoinGroups,
                .pinnedDiscussions,
                .bookmarkedMessage,
                .archivedDiscussions,
                .discussionsMute,
                .settingUnarchiveOnNotification:
            throw ObvIdentityManagerError.wrongSyncAtomRecipient
        case .trustContactDetails(contactCryptoId: let contactCryptoId, serializedIdentityDetailsElements: let serializedIdentityDetailsElements):
            guard let contact = try ContactIdentity.get(contactIdentity: contactCryptoId.cryptoIdentity, ownedIdentity: self) else {
                throw ObvIdentityManagerError.cryptoIdentityIsNotContact
            }
            try contact.processTrustContactDetailsSyncAtom(serializedIdentityDetailsElements: serializedIdentityDetailsElements)
        case .trustGroupV1Details(groupOwner: let groupOwner, groupUid: let groupUid, serializedGroupDetailsElements: let serializedGroupDetailsElements):
            guard let groupV1 = try ContactGroupJoined.get(groupUid: groupUid, groupOwnerCryptoIdentity: groupOwner.cryptoIdentity, ownedIdentity: self) else {
                throw ObvIdentityManagerError.groupIsNotJoined
            }
            try groupV1.processTrustGroupV1DetailsSyncAtom(serializedGroupDetailsElements: serializedGroupDetailsElements)
        case .trustGroupV2Details(groupIdentifier: let groupIdentifier, version: let version):
            guard let encodedGroupIdentifier = ObvEncoded(withRawData: groupIdentifier),
                  let groupIdentifier = ObvGroupV2.Identifier(encodedGroupIdentifier)
            else {
                assertionFailure()
                throw ObvIdentityManagerError.couldNotDecodeGroupIdentifier
            }
            
            guard let groupV2 = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: GroupV2.Identifier(obvGroupV2Identifier: groupIdentifier), of: self) else {
                throw ObvIdentityManagerError.groupDoesNotExist
            }
            try groupV2.processTrustGroupV2DetailsSyncAtom(version: version)
        }
        
    }
    
}



// MARK: - Keycloak management

extension OwnedIdentity {

    var isKeycloakManaged: Bool {
        self.keycloakServer != nil
    }
    
    
    func unbindFromKeycloak(isUnbindRequestByUser: Bool) throws {
        // If the unbind is requested by the user, we must check they are allowed to do so
        if isUnbindRequestByUser, let keycloakServer {
            guard !keycloakServer.isTransferRestricted else {
                // In case the keycloak server enforces restricted transfer, the user is not allowed to unregister
                throw ObvIdentityManagerError.unbindIsRestricted
            }
        }
        // We can perform the unbind
        try keycloakServer?.delete()
        if keycloakServer != nil {
            keycloakServer = nil
        }
        refreshCertifiedByOwnKeycloakAndTrustedDetailsForAllContacts()
        try deleteAllKeycloakGroups()
    }
    

    func bindToKeycloak(keycloakState: ObvKeycloakState) throws {
        // If there is a previous keycloak server, we unbind from this old server before setting the new one
        if self.keycloakServer != nil {
            try unbindFromKeycloak(isUnbindRequestByUser: true)
        }
        self.keycloakServer = try KeycloakServer(keycloakState: keycloakState, managedOwnedIdentity: self)
        refreshCertifiedByOwnKeycloakAndTrustedDetailsForAllContacts()
    }
    
    
    fileprivate func refreshCertifiedByOwnKeycloakAndTrustedDetailsForAllContacts() {
        for contact in contactIdentities {
            do {
                try contact.refreshCertifiedByOwnKeycloakAndTrustedDetails()
            } catch {
                // In production, we continue anyway
                assertionFailure()
            }
        }
    }
    
    
    /// When unbinding from a keycloak server, we delete all keycloak groups
    private func deleteAllKeycloakGroups() throws {
        guard !isKeycloakManaged else { assertionFailure("We expect this method to be called when leaving a keycloak server in which case isKeycloakManaged should be false"); return }
        try contactGroupsV2
            .filter({ $0.groupIdentifier?.category == .keycloak })
            .forEach { keycloakGroup in
                do {
                    try keycloakGroup.delete()
                } catch {
                    assertionFailure(error.localizedDescription)
                    throw error
                }
            }
    }
    
    
    func setOwnedIdentityKeycloakSignatureKey(_ keycloakServersignatureVerificationKey: ObvJWK?) throws {
        guard isKeycloakManaged else { throw Self.makeError(message: "Owned identity is not keycloak managed. Cannot set keycloak server signature key") }
        keycloakServer?.setServerSignatureVerificationKey(keycloakServersignatureVerificationKey)
        refreshCertifiedByOwnKeycloakAndTrustedDetailsForAllContacts()
    }

    
    func verifyAndAddRevocationList(signedRevocations: [String], revocationListTimetamp: Date) throws -> Set<ObvCryptoIdentity> {
        assert(keycloakServer != nil)
        return try keycloakServer?.verifyAndAddRevocationList(signedRevocations: signedRevocations, revocationListTimetamp: revocationListTimetamp) ?? Set<ObvCryptoIdentity>()
    }

    
    func pruneOldKeycloakRevokedContacts() {
        assert(keycloakServer != nil)
        do {
            try keycloakServer?.pruneOldKeycloakRevokedIdentities()
        } catch {
            Self.logger.fault("Could not prune old keycloak revoked identities: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    
    /// Each time we update the revocation lists of the keycloak server of a managed owned identity, we also update its
    /// `latestRevocationListTimetamp`. Consequently, we want to uncertify managed contacts whose details are
    /// older than this timestamp minus, e.g., two months.
    func uncertifyExpiredSignedContactDetails() {
        assert(keycloakServer != nil)
        let certifiedContacts = contactIdentities.filter({ $0.isCertifiedByOwnKeycloak })
        certifiedContacts.forEach { contact in
            do {
                try contact.refreshCertifiedByOwnKeycloakAndTrustedDetails()
            } catch {
                Self.logger.fault("Could not refresh the isCertifiedByOwnKeycloak of one of our contacts: \(error.localizedDescription, privacy: .public)")
                assertionFailure()
                // In production, we continue anyway
            }
        }
    }
    
    
    func updateKeycloakPushTopicsIfNeeded(pushTopics: Set<String>) -> Bool {
        assert(keycloakServer != nil)
        let storedPushTopicsUpdated = keycloakServer?.updateKeycloakPushTopicsIfNeeded(newPushTopics: pushTopics) ?? false
        return storedPushTopicsUpdated
    }
    
    
    
    func getPushTopicsForKeycloakServer() -> Set<String> {
        keycloakServer?.pushTopicsForKeycloakServer ?? Set()
    }
    
    
    func getPushTopicsForKeycloakManagedGroups() throws -> Set<String> {
        return try ContactGroupV2.getAllPushTopicsOfKeycloakManagedGroups(ownedIdentity: self)
    }
    
    
    func getPushTopicsForKeycloakServerAndForKeycloakManagedGroups() throws -> Set<String> {
        let pushTopicsForKeycloakServer = getPushTopicsForKeycloakServer()
        let pushTopicsForKeycloakManagedGroups = try getPushTopicsForKeycloakManagedGroups()
        return pushTopicsForKeycloakServer.union(pushTopicsForKeycloakManagedGroups)
    }
    
    func setIsTransferRestricted(to isTransferRestricted: Bool) throws {
        guard let keycloakServer else {
            assertionFailure()
            throw ObvError.ownedIdentityIsNotKeycloakManaged
        }
        keycloakServer.setIsTransferRestricted(to: isTransferRestricted)
    }
    
    
    /// This method is called during a keycloak managed profile transfer, if the keycloak enforces a restriction on the transfer. It is called on the source device, when it receives a proof from the target device that it was able to authenticate against the keycloak server.
    /// This method verifies the signature and checks that the payload contained in the signature contains the elements that we expect.
    func verifyKeycloakSignature(keycloakTransferProof: ObvKeycloakTransferProof, keycloakTransferProofElements: ObvKeycloakTransferProofElements) throws(ObvIdentityManagerError) {
        
        guard let keycloakServer else {
            throw .ownedIdentityIsNotKeycloakManaged
        }
        
        try keycloakServer.verifyKeycloakSignature(keycloakTransferProof: keycloakTransferProof, keycloakTransferProofElements: keycloakTransferProofElements)
        
    }
    
}


// MARK: - Keycloak pushed groups

extension OwnedIdentity {
    
    /// Updates the
    func updateKeycloakGroups(signedGroupBlobs: Set<String>, signedGroupDeletions: Set<String>, signedGroupKicks: Set<String>, keycloakCurrentTimestamp: Date, within context: NSManagedObjectContext) throws -> [KeycloakGroupV2UpdateOutput] {

        guard isKeycloakManaged else {
            throw Self.makeError(message: "The owned identity is not keycloak managed, cannot update keycloak groups")
        }

        guard let keycloakServer = self.keycloakServer else {
            throw Self.makeError(message: "Could not find keycloak server of the keycloak managed identity. Unexpected.")
        }

        let keycloakGroupV2UpdateOutputs = try keycloakServer.processSignedKeycloakGroups(signedGroupBlobs: signedGroupBlobs,
                                                                                          signedGroupDeletions: signedGroupDeletions,
                                                                                          signedGroupKicks: signedGroupKicks,
                                                                                          keycloakCurrentTimestamp: keycloakCurrentTimestamp,
                                                                                          within: context)

        return keycloakGroupV2UpdateOutputs
        
    }
    
}


// MARK: - OwnedDevice management

extension OwnedIdentity {
    
    func addIfNotExistRemoteDeviceWith(uid: UID, createdDuringChannelCreation: Bool) throws {
        guard try otherDevices.first(where: { try $0.uid == uid }) == nil else {
            // The device already exists
            return
        }
        guard try uid != currentDeviceUid else {
            // Trying to add the current device as a remote device
            return
        }
        guard OwnedDevice(remoteDeviceUid: uid, ownedIdentity: self, createdDuringChannelCreation: createdDuringChannelCreation) != nil else {
            assertionFailure()
            Self.logger.fault("Could not add a remote device")
            throw Self.makeError(message: "Could not add a remote device")
        }
    }
    
    
    func removeIfExistsOtherDeviceWith(uid: UID, flowId: FlowIdentifier) throws {
        for device in otherDevices {
            guard try device.uid == uid else { continue }
            try device.deleteThisDevice()
        }
    }


    /// Returns a Boolean indicating whether the current device is part of the owned device discovery results.
    func processEncryptedOwnedDeviceDiscoveryResult(_ encryptedOwnedDeviceDiscoveryResult: EncryptedData, prng: PRNGService, solveChallengeDelegate: ObvSolveChallengeDelegate, within context: NSManagedObjectContext) throws -> OwnedDeviceDiscoveryPostProcessingTask {
        
        let ownedDeviceDiscoveryResult = try OwnedDeviceDiscoveryResult.decrypt(encryptedOwnedDeviceDiscoveryResult: encryptedOwnedDeviceDiscoveryResult, for: self.ownedCryptoIdentity)

        // Update existing devices and add missing devices
        
        var currentDevicePreKeyToUpload: DevicePreKey?
        
        for device in ownedDeviceDiscoveryResult.devices {
            
            if let deviceBlobOnServer = device.deviceBlobOnServer {
                try deviceBlobOnServer.checkChallengeResponse(for: cryptoIdentity)
            }
            
            if let existingRemoteDevice = try self.otherDevices.first(where: { try $0.uid == device.uid }) {
                
                _ = try existingRemoteDevice.updateThisDevice(with: device,
                                                              serverCurrentTimestamp: ownedDeviceDiscoveryResult.serverCurrentTimestamp)
                
            } else if try self.currentDevice.uid == device.uid {
                
                currentDevicePreKeyToUpload = try self.currentDevice.updateThisDevice(with: device,
                                                                                      serverCurrentTimestamp: ownedDeviceDiscoveryResult.serverCurrentTimestamp)
                
            } else {
                
                _ = OwnedDevice(remoteDeviceUid: device.uid,
                                ownedIdentity: self,
                                createdDuringChannelCreation: false)
                                
            }
            
        }
        
        // We don't deactivate the current device if not part of the owned device discovery.
        // Instead, we notify the engine by returning a Boolean.
        
        let currentDeviceIsPartOfOwnedDeviceDiscoveryResult = try ownedDeviceDiscoveryResult.devices.map({ $0.uid }).contains(where: { try $0 == self.currentDevice.uid })
        
        // Remove deactivated remote devices
        
        let otherDevicesToDeactivate = try self.otherDevices.filter { otherDevice in
            try !ownedDeviceDiscoveryResult.devices.map({ $0.uid }).contains(where: { try $0 == otherDevice.uid })
        }
        
        for otherDeviceToDeactivate in otherDevicesToDeactivate {
            try otherDeviceToDeactivate.deleteThisDevice()
        }
        
        // We don't care about the ownedDeviceDiscoveryResult.isMultidevice Boolean
        
        if !currentDeviceIsPartOfOwnedDeviceDiscoveryResult {

            return .currentDeviceMustRegister

        } else {

            if let currentDevicePreKeyToUpload {
                
                assert(currentDevice.allCapabilities != nil)
                let deviceCapabilities = currentDevice.allCapabilities ?? Set<ObvCapability>()
                
                do {
                    let deviceBlobOnServerToUpload = try DeviceBlobOnServer.createDevicePreKeyToUploadOnServer(
                        devicePreKey: currentDevicePreKeyToUpload,
                        deviceCapabilities: deviceCapabilities,
                        ownedCryptoId: self.ownedCryptoIdentity.getObvCryptoIdentity(),
                        prng: prng,
                        solveChallengeDelegate: solveChallengeDelegate,
                        within: context)
                    return .currentDeviceMustUploadPreKey(deviceBlobOnServerToUpload: deviceBlobOnServerToUpload)
                } catch {
                    Self.logger.fault("Failed to create a device prekey for the current device: \(error.localizedDescription, privacy: .public)")
                    assertionFailure()
                    // We don't want to abort the complete process when we fail to generate a prekey
                    return .none
                }
                                
            } else {
            
                return .none
                
            }
            
        }
        
    }
    
    
    func decryptEncryptedOwnedDeviceDiscoveryResult(_ encryptedOwnedDeviceDiscoveryResult: EncryptedData) throws -> OwnedDeviceDiscoveryResult {
        let ownedDeviceDiscoveryResult = try OwnedDeviceDiscoveryResult.decrypt(encryptedOwnedDeviceDiscoveryResult: encryptedOwnedDeviceDiscoveryResult, for: self.ownedCryptoIdentity)
        return ownedDeviceDiscoveryResult
    }
    
    
    func decryptProtocolCiphertext(_ ciphertext: EncryptedData) throws -> Data {
        
        guard let cleartext = try PublicKeyEncryption.decrypt(ciphertext, for: ownedCryptoIdentity) else {
            assertionFailure()
            throw Self.makeError(message: "Could not decrypt encrypted payload")
        }
        
        return cleartext
    }
    
    
    func getInfosAboutOwnedDevice(withUid uid: UID) throws -> (name: String?, expirationDate: Date?, latestRegistrationDate: Date?) {
        if try currentDevice.uid == uid {
            return currentDevice.infos
        } else if let otherRemoteDevice = try otherDevices.first(where: { try $0.uid == uid }) {
            return otherRemoteDevice.infos
        } else {
            // This happens when the current owned device was deactivated
            throw Self.makeError(message: "Could not find other remote device")
        }
    }
    
    
    func setCurrentDeviceNameAfterBackupRestore(newName: String) {
        currentDevice.setCurrentDeviceNameAfterBackupRestore(newName: newName)
    }
    
    
}


// MARK: - Errors

extension OwnedIdentity {
    
    enum ObvError: Error {
        case unexpectedContext
        case couldNotFindRemoteOwnedDevice
        case ownedIdentityIsNotKeycloakManaged
        case rawBackupSeedIsNil
        case backupSeedParsingFailed
        case unexpectedNilValue
        case couldNotParseValue
    }
    
}


// MARK: - Contact management

extension OwnedIdentity {
    
    /// If the `cryptoIdentity` is already a contact of this own identity, this method only adds a trust origin to that contact. If not, this method creates the contact with the appropriate trust origin.
    /// Note that if the contact already exists, this method does *not* update her details.
    func addContactOrTrustOrigin(cryptoIdentity: ObvCryptoIdentity, identityCoreDetails: ObvIdentityCoreDetails, trustOrigin: TrustOrigin, isKnownToBeOneToOne: Bool) throws -> ContactIdentity {
        guard let context = self.managedObjectContext else { assertionFailure(); throw Self.makeError(message: "Could not find context") }
        if let contact = try ContactIdentity.get(contactIdentity: cryptoIdentity, ownedIdentity: self.cryptoIdentity, within: context) {
            try contact.addTrustOriginIfTrustWouldBeIncreased(trustOrigin)
            return contact
        } else {
            guard let contact = ContactIdentity(cryptoIdentity: cryptoIdentity, identityCoreDetails: identityCoreDetails, trustOrigin: trustOrigin, ownedIdentity: self, isKnownToBeOneToOne: isKnownToBeOneToOne) else {
                throw Self.makeError(message: "Could not create contact identity")
            }
            return contact
        }
    }
    
    
}

// MARK: - Keychain management

extension OwnedIdentity {
    
    private func iOSSecItemAdd(ownedCryptoIdentity: ObvOwnedCryptoIdentity, sharedContainerIdentifier: String) throws {
        let identity = ownedCryptoIdentity.getObvCryptoIdentity().getIdentity()
        let encodedOwnedCryptoIdentity = ownedCryptoIdentity.obvEncode()
        let accessGroup = sharedContainerIdentifier
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                     kSecAttrAccount as String: identity,
                                     kSecValueData as String: encodedOwnedCryptoIdentity.rawData,
                                     kSecAttrAccessGroup as String: accessGroup]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw Self.makeError(message: "Keychain error: \(status.description)")
        }
    }
    
    
    private func iOSSecItemCopyMatching(cryptoIdentity: ObvCryptoIdentity) throws -> ObvOwnedCryptoIdentity {
        let identity = cryptoIdentity.getIdentity()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecMatchLimit as String: kSecMatchLimitOne,
                                     kSecReturnAttributes as String: true,
                                     kSecReturnData as String: true,
                                     kSecAttrAccount as String: identity]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            assertionFailure()
            throw Self.makeError(message: "Keychain error")
        }
        
        guard let existingItem = item as? [String: Any],
            let encodedOwnedCryptoIdentityRawData = existingItem[kSecValueData as String] as? Data,
            let encodedOwnedCryptoIdentity = ObvEncoded(withRawData: encodedOwnedCryptoIdentityRawData),
            let ownedCryptoIdentity = ObvOwnedCryptoIdentity(encodedOwnedCryptoIdentity) else {
            assertionFailure()
            throw Self.makeError(message: "Could not extract owned identity from keychain item")
        }

        return ownedCryptoIdentity
    }
    
}


// MARK: - Capabilities

extension OwnedIdentity {
    
    func setRawCapabilitiesOfOtherDeviceWithUID(_ deviceUID: UID, newRawCapabilities: Set<String>) throws {
        guard let device = try self.otherDevices.first(where: { try $0.uid == deviceUID }) else {
            throw Self.makeError(message: "Could not find contact device")
        }
        device.setRawCapabilities(newRawCapabilities: newRawCapabilities)
    }

    
    func setCapabilitiesOfCurrentDevice(newCapabilities: Set<ObvCapability>) throws {
        self.currentDevice.setCapabilities(newCapabilities: newCapabilities)
    }
    
    
    /// Returns `nil` if the own capabilities are not known yet (i.e., when no device has capabilities)
    var allCapabilities: Set<ObvCapability>? {
        var capabilitiesOfDevicesWithKnownCapabilities = otherDevices.compactMap({ $0.allCapabilities })
        if let currentDeviceCapabilities = currentDevice.allCapabilities {
            capabilitiesOfDevicesWithKnownCapabilities.append(currentDeviceCapabilities)
        }
        guard !capabilitiesOfDevicesWithKnownCapabilities.isEmpty else { return nil }
        var capabilities = Set<ObvCapability>()
        ObvCapability.allCases.forEach { capability in
            if capabilitiesOfDevicesWithKnownCapabilities.allSatisfy({ $0.contains(capability) }) {
                capabilities.insert(capability)
            }
        }
        return capabilities
    }
    
}


// MARK: - Using Pre-keys

extension OwnedIdentity {
    
    func wrap(_ messageKey: any ObvCrypto.AuthenticatedEncryptionKey, forRemoteDeviceUID uid: UID, ofRemoteCryptoId remoteCryptoId: ObvCryptoIdentity, prng: any PRNGService) throws -> EncryptedData? {
        
        let wrappedMessageKey: EncryptedData?

        if try ownedCryptoIdentity.getObvCryptoIdentity() == remoteCryptoId {
            
            guard let remoteOwnedDevice = try self.otherDevices.first(where: { try $0.uid == uid }) else {
                assertionFailure()
                throw ObvError.couldNotFindRemoteOwnedDevice
            }
            
            wrappedMessageKey = try remoteOwnedDevice.wrapForRemoteOwnedDevice(messageKey,
                                                                               with: self.ownedCryptoIdentity.privateKeyForAuthentication,
                                                                               and: self.cryptoIdentity.publicKeyForAuthentication,
                                                                               prng: prng)
            
        } else {
            
            guard let contact = try ContactIdentity.get(contactIdentity: remoteCryptoId, ownedIdentity: self) else {
                assertionFailure()
                return nil
            }
            
            wrappedMessageKey = try contact.wrap(messageKey,
                                                 forContactDeviceUID: uid,
                                                 with: self.ownedCryptoIdentity.privateKeyForAuthentication,
                                                 and: self.cryptoIdentity.publicKeyForAuthentication,
                                                 prng: prng)
                        
        }
            
        return wrappedMessageKey

    }
    
    
    func unwrapForCurrentOwnedDevice(_ wrappedMessageKey: EncryptedData, within context: NSManagedObjectContext) throws -> ResultOfUnwrapWithPreKey {
        
        guard let (messageKey, remoteCryptoId, remoteDeviceUID) = try self.currentDevice.unwrapForCurrentOwnedDevice(wrappedMessageKey) else {
            return .couldNotUnwrap
        }
        
        let receptionChannelInfo = ObvProtocolReceptionChannelInfo.preKeyChannel(remoteCryptoIdentity: remoteCryptoId, remoteDeviceUid: remoteDeviceUID)

        // Make sure the remoteCryptoId either is the ownedCryptoId or corresponds to a contact
        
        if try remoteCryptoId == ownedCryptoIdentity.getObvCryptoIdentity() {
            
            // Add the remote device UID in case we don't know about it yet, note that this will trigger an owned device discovery
            
            if try self.otherDevices.first(where: { try $0.uid == remoteDeviceUID }) == nil {
                try self.addIfNotExistRemoteDeviceWith(uid: remoteDeviceUID, createdDuringChannelCreation: false)
            }
                        
            return .unwrapSucceeded(messageKey: messageKey, receptionChannelInfo: receptionChannelInfo)
            
        } else if let contact = try ContactIdentity.get(contactIdentity: remoteCryptoId, ownedIdentity: self) {
            
            guard contact.isNotRevokedAsCompromisedOrIsForcefullyTrustedByUser else {
                return .contactIsRevokedAsCompromised
            }
            
            // Add the remote device UID in case we don't know about it yet, note that this will trigger a contact device discovery

            if try contact.devices.first(where: { try $0.uid == remoteDeviceUID }) == nil {
                try contact.addIfNotExistDeviceWith(uid: remoteDeviceUID, createdDuringChannelCreation: false)
            }
            
            return .unwrapSucceeded(messageKey: messageKey, receptionChannelInfo: receptionChannelInfo)

        } else {
            
            return .unwrapSucceededButRemoteCryptoIdIsUnknown(remoteCryptoIdentity: remoteCryptoId)
            
        }

    }
    
    
    func deleteCurrentOwnedDeviceExpiredPreKeys(downloadTimestampFromServer: Date) throws {
        try currentDevice.deleteThisCurrentOwnedDeviceExpiredPreKeys(downloadTimestampFromServer: downloadTimestampFromServer)
    }
    
}


// MARK: - Latest Channel Creation Ping Timestamp for remote owned devices

extension OwnedIdentity {
    
    func getLatestChannelCreationPingTimestampOfRemoteOwnedDevice(withUID uid: UID) throws -> Date? {
        guard let device = try self.otherDevices.first(where: { try $0.uid == uid }) else {
            assertionFailure()
            throw ObvError.couldNotFindRemoteOwnedDevice
        }
        return device.latestChannelCreationPingTimestamp
    }
    
    
    func setLatestChannelCreationPingTimestampOfRemoteOwnedDevice(withUID uid: UID, to date: Date) throws {
        guard let device = try self.otherDevices.first(where: { try $0.uid == uid }) else { return }
        device.setLatestChannelCreationPingTimestamp(to: date)
    }
    
}



// MARK: - Convenience DB getters

extension OwnedIdentity {
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case isActive = "isActive"
            case isDeletionInProgress = "isDeletionInProgress"
            case rawBackupSeed = "rawBackupSeed"
            case rawCryptoIdentity = "rawCryptoIdentity"
            case rawOwnedCryptoIdentity = "rawOwnedCryptoIdentity"
            // Relationships
            case contactGroups = "contactGroups"
            case contactGroupsV2 = "contactGroupsV2"
            case contactIdentities = "contactIdentities"
            case currentDevice = "currentDevice"
            case keycloakServer = "keycloakServer"
            case maskingUID = "maskingUID"
            case otherDevices = "otherDevices"
            case publishedIdentityDetails = "publishedIdentityDetails"
        }
        static func withCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawCryptoIdentity, EqualToData: ownedCryptoIdentity.getIdentity())
        }
        static func isKeycloakManaged(_ isKeycloakManaged: Bool) -> NSPredicate {
            if isKeycloakManaged {
                return NSPredicate(withNonNilValueForKey: Key.keycloakServer)
            } else {
                return NSPredicate(withNilValueForKey: Key.keycloakServer)
            }
        }
        static var isActive: NSPredicate {
            NSPredicate(Key.isActive, is: true)
        }
        static func isDeletionInProgress(is bool: Bool) -> NSPredicate {
            NSPredicate(Key.isDeletionInProgress, is: bool)
        }
    }
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<OwnedIdentity> {
        return NSFetchRequest<OwnedIdentity>(entityName: entityName)
    }

    
    static func get(_ identity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws -> OwnedIdentity? {
        let request: NSFetchRequest<OwnedIdentity> = OwnedIdentity.fetchRequest()
        request.predicate = Predicate.withCryptoIdentity(identity)
        request.fetchLimit = 1
        let item = try context.fetch(request).first
        return item
    }
    
    
    static func isOwnedIdentityDeletedOrDeletionIsInProgress(_ identity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws -> Bool {
        let request: NSFetchRequest<OwnedIdentity> = OwnedIdentity.fetchRequest()
        request.predicate = Predicate.withCryptoIdentity(identity)
        request.fetchLimit = 1
        request.propertiesToFetch = [Predicate.Key.isDeletionInProgress.rawValue]
        guard let item = (try context.fetch(request)).first else {
            // The owned identity was deleted
            return true
        }
        return item.isDeletionInProgress
    }
    
    
    static func exists(_ identity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws -> Bool {
        let request: NSFetchRequest<OwnedIdentity> = OwnedIdentity.fetchRequest()
        request.predicate = Predicate.withCryptoIdentity(identity)
        request.fetchLimit = 1
        request.propertiesToFetch = []
        let item = try context.fetch(request).first
        return item != nil
    }
    

    static func getAll(restrictToActive: Bool, within context: NSManagedObjectContext) throws -> [OwnedIdentity] {
        
        let request: NSFetchRequest<OwnedIdentity> = OwnedIdentity.fetchRequest()
        
        request.propertiesToFetch = [
            Predicate.Key.rawCryptoIdentity.rawValue,
            Predicate.Key.rawOwnedCryptoIdentity.rawValue,
        ]
        
        var andPredicateWithSubpredicates: [NSPredicate] = [
            Predicate.isDeletionInProgress(is: false),
        ]
        if restrictToActive {
            andPredicateWithSubpredicates += [Predicate.isActive]
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: andPredicateWithSubpredicates)
        
        let items = try context.fetch(request)
        return items
        
    }

    
    static func getAllCryptoIds(restrictToActive: Bool, within context: NSManagedObjectContext) throws -> Set<ObvCryptoIdentity> {
        
        let request: NSFetchRequest<OwnedIdentity> = OwnedIdentity.fetchRequest()
        
        request.propertiesToFetch = [
            Predicate.Key.rawCryptoIdentity.rawValue,
        ]
        
        var andPredicateWithSubpredicates: [NSPredicate] = [
            Predicate.isDeletionInProgress(is: false),
        ]
        if restrictToActive {
            andPredicateWithSubpredicates += [Predicate.isActive]
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: andPredicateWithSubpredicates)

        let items = try context.fetch(request)
        return try Set(items.map { try $0.cryptoIdentity })
        
    }

    
    static func getAllKeycloakManaged(within context: NSManagedObjectContext) throws -> [OwnedIdentity] {
        let request: NSFetchRequest<OwnedIdentity> = OwnedIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isDeletionInProgress(is: false),
            Predicate.isKeycloakManaged(true),
        ])
        let items = try context.fetch(request)
        return items
    }
    
    
    static func getBackupSeedOfOwnedIdentity(ownedCryptoId: ObvCryptoId, restrictToActive: Bool, within context: NSManagedObjectContext) throws -> BackupSeed? {
        let request: NSFetchRequest<OwnedIdentity> = OwnedIdentity.fetchRequest()
        request.predicate = Predicate.withCryptoIdentity(ownedCryptoId.cryptoIdentity)
        request.fetchLimit = 1
        request.propertiesToFetch = [Predicate.Key.rawBackupSeed.rawValue]
        guard let item = try context.fetch(request).first else {
            return nil
        }
        if restrictToActive {
            guard item.isActive else {
                throw ObvIdentityManagerError.ownedIdentityIsInactive
            }
        }
        return try item.backupSeed
    }

}


// MARK: - Sending notifications

extension OwnedIdentity {
    
    override func willSave() {
        super.willSave()
        do {
            self.ownedIdentityOnDeletion = try cryptoIdentity
        } catch {
            assertionFailure()
        }
        if !isInserted {
            changedKeys = Set<String>(self.changedValues().keys)
        }
    }
    
    override func didSave() {
        super.didSave()
        
        defer {
            changedKeys.removeAll()
            isInsertedWhileRestoringSyncSnapshot = false
        }

        guard !isInsertedWhileRestoringSyncSnapshot else {
            assert(isInserted)
            Self.logger.info("Insertion of an OwnedIdentity during a snapshot restore --> we don't send any notification")
            return
        }

        guard let delegateManager = Self.delegateManager else {
            Self.logger.fault("The delegate manager is not set (7)")
            // This will certainly happen during a backup restore. Not sure this is a good thing...
            return
        }
        
        if isInserted {
            Self.logger.debug("A new owned identity was inserted")
            if self.isActive {
                if let ownedCryptoIdentity = try? self.ownedCryptoIdentity.getObvCryptoIdentity() {
                    
                    ObvIdentityNotificationNew.newActiveOwnedIdentity(ownedCryptoIdentity: ownedCryptoIdentity)
                        .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
                    
                    ObvIdentityNotificationNew.newOwnedIdentityWithinIdentityManager(cryptoIdentity: ownedCryptoIdentity)
                        .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)

                } else {
                    assertionFailure()
                }
            }
        } else if isDeleted {
            assert(ownedIdentityOnDeletion != nil)
            if let ownedIdentityOnDeletion {
                Self.logger.info("An owned identity was deleted from the engine database")
                Task { await Self.observersHolder.anOwnedIdentityWasDeleted(deletedOwnedCryptoId: ownedIdentityOnDeletion) }
            }
        }
        
        if changedKeys.contains(Predicate.Key.isActive.rawValue) && !isDeleted {
            if self.isActive {
                if let ownedCryptoIdentity = try? self.ownedCryptoIdentity.getObvCryptoIdentity() {
                    ObvIdentityNotificationNew.ownedIdentityWasReactivated(ownedCryptoIdentity: ownedCryptoIdentity)
                        .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
                } else {
                    assertionFailure()
                }
            } else {
                if let ownedCryptoIdentity = try? self.ownedCryptoIdentity.getObvCryptoIdentity() {
                    ObvIdentityNotificationNew.ownedIdentityWasDeactivated(ownedCryptoIdentity: ownedCryptoIdentity)
                        .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
                } else {
                    assertionFailure()
                }
            }
        }
        
        if changedKeys.contains(Predicate.Key.keycloakServer.rawValue) && !isDeleted {
            if let ownedCryptoIdentity = try? self.ownedCryptoIdentity.getObvCryptoIdentity() {
                ObvIdentityNotificationNew.ownedIdentityKeycloakServerChanged(ownedCryptoIdentity: ownedCryptoIdentity)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
            } else {
                assertionFailure()
            }
        }
        
        // Send a backupableManagerDatabaseContentChanged notification
        if isInserted || isDeleted || isUpdated || !changedKeys.isEmpty {
            ObvBackupNotification.backupableManagerDatabaseContentChanged
                .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)

        }
        
        // Potentially notify that the previous backed up device snapshot is obsolete
        // Other entities can also notify:
        // - KeycloakServer
        // - OwnedIdentityDetailsPublished
        
        do {
            let previousBackedUpDeviceSnapShotIsObsolete: Bool
            if isInserted || isDeleted {
                previousBackedUpDeviceSnapShotIsObsolete = true
            } else if changedKeys.contains(Predicate.Key.rawBackupSeed.rawValue) {
                previousBackedUpDeviceSnapShotIsObsolete = true
            } else {
                previousBackedUpDeviceSnapShotIsObsolete = false
            }
            if previousBackedUpDeviceSnapShotIsObsolete {
                Task { await Self.observersHolder.previousBackedUpDeviceSnapShotIsObsoleteAsOwnedIdentityChanged() }
            }
        }
        
        // Potentially notify that the previous backed up profile snapshot is obsolete
        // Other entities can also notify:
        // - ContactIdentity (implemented)
        // - OwnedIdentityDetailsPublished (implemented)
        // - KeycloakServer (implemented)
        // - ContactGroup (implemented)
        // - ContactGroupV2 (implemented)
        // - ContactIdentityDetails (implemented)
        // - ContactGroupV2Member (implemented)
        // - ContactGroupV2PendingMember (implemented)
        // - ContactGroupV2Details (implemented)
        
        if !isDeleted {
            let previousBackedUpProfileSnapShotIsObsolete: Bool
            if isInserted {
                previousBackedUpProfileSnapShotIsObsolete = true
            } else if changedKeys.contains(Predicate.Key.contactIdentities.rawValue) ||
                        changedKeys.contains(Predicate.Key.publishedIdentityDetails.rawValue) ||
                        changedKeys.contains(Predicate.Key.keycloakServer.rawValue) ||
                        changedKeys.contains(Predicate.Key.contactGroups.rawValue) ||
                        changedKeys.contains(Predicate.Key.contactGroupsV2.rawValue) ||
                        changedKeys.contains(Predicate.Key.rawBackupSeed.rawValue) {
                previousBackedUpProfileSnapShotIsObsolete = true
            } else {
                previousBackedUpProfileSnapShotIsObsolete = false
            }
            if previousBackedUpProfileSnapShotIsObsolete {
                if let ownedCryptoIdentity = try? self.ownedCryptoIdentity.getObvCryptoIdentity() {
                    let ownedCryptoId = ObvCryptoId(cryptoIdentity: ownedCryptoIdentity)
                    Task { await Self.observersHolder.previousBackedUpProfileSnapShotIsObsoleteAsOwnedIdentityChangedOrWasInserted(ownedCryptoId: ownedCryptoId) }
                } else {
                    assertionFailure()
                }
            }
        }
        
    }
}


// MARK: - For Backup purposes

extension OwnedIdentity {
    
    var backupItem: OwnedIdentityBackupItem {
        get throws {
            let contactGroupsOwned = contactGroups.filter { $0 is ContactGroupOwned } as! Set<ContactGroupOwned>
            return try OwnedIdentityBackupItem(ownedCryptoIdentity: ownedCryptoIdentity,
                                               contactIdentities: contactIdentities,
                                               currentDevice: currentDevice,
                                               otherDevices: otherDevices,
                                               publishedIdentityDetails: publishedIdentityDetails,
                                               contactGroupsOwned: contactGroupsOwned,
                                               contactGroupsV2: contactGroupsV2,
                                               keycloakServer: keycloakServer,
                                               isActive: isActive,
                                               backupSeed: try self.backupSeed)
        }
    }

}


/// For legacy backups
struct OwnedIdentityBackupItem: Codable, Hashable, ObvErrorMaker {
    
    fileprivate let privateIdentity: ObvOwnedCryptoIdentityPrivateBackupItem
    let cryptoIdentity: ObvCryptoIdentity
    fileprivate let contactIdentities: Set<ContactIdentityBackupItem>
    let publishedIdentityDetails: OwnedIdentityDetailsPublishedBackupItem
    fileprivate let ownedGroups: Set<ContactGroupOwnedBackupItem>?
    private let contactGroupsV2: Set<ContactGroupV2BackupItem>
    let keycloakServer: KeycloakServerBackupItem?
    let isActive: Bool
    fileprivate let backupSeed: BackupSeed

    static let errorDomain = "OwnedIdentityBackupItem"

    var ownedCryptoIdentity: ObvOwnedCryptoIdentity? {
        return privateIdentity.getOwnedIdentity(cryptoIdentity: cryptoIdentity)
    }
    
    fileprivate init(ownedCryptoIdentity: ObvOwnedCryptoIdentity, contactIdentities: Set<ContactIdentity>, currentDevice: OwnedDevice, otherDevices: Set<OwnedDevice>, publishedIdentityDetails: OwnedIdentityDetailsPublished, contactGroupsOwned: Set<ContactGroupOwned>, contactGroupsV2: Set<ContactGroupV2>, keycloakServer: KeycloakServer?, isActive: Bool, backupSeed: BackupSeed) throws {
        self.cryptoIdentity = ownedCryptoIdentity.getObvCryptoIdentity()
        self.privateIdentity = ownedCryptoIdentity.privateBackupItem
        self.contactIdentities = Set(contactIdentities.compactMap { $0.backupItem })
        self.publishedIdentityDetails = publishedIdentityDetails.backupItem
        self.ownedGroups = try contactGroupsOwned.isEmpty ? nil : Set(contactGroupsOwned.map { try $0.backupItem })
        self.contactGroupsV2 = Set(contactGroupsV2.compactMap({ $0.backupItem }))
        self.keycloakServer = keycloakServer?.backupItem
        self.isActive = isActive
        self.backupSeed = backupSeed
    }
    
    enum CodingKeys: String, CodingKey {
        case privateIdentity = "private_identity"
        case cryptoIdentity = "owned_identity"
        case contactIdentities = "contact_identities"
        case publishedIdentityDetails = "published_details"
        case ownedGroups = "owned_groups"
        case contactGroupsV2 = "groups_v2"
        case keycloak = "keycloak"
        case isActive = "active"
        case backupSeed = "backup_seed"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cryptoIdentity.getIdentity(), forKey: .cryptoIdentity)
        try container.encode(privateIdentity, forKey: .privateIdentity)
        try container.encode(contactIdentities, forKey: .contactIdentities)
        try container.encode(publishedIdentityDetails, forKey: .publishedIdentityDetails)
        try container.encodeIfPresent(ownedGroups, forKey: .ownedGroups)
        try container.encode(contactGroupsV2, forKey: .contactGroupsV2)
        try container.encode(isActive, forKey: .isActive)
        try container.encodeIfPresent(backupSeed, forKey: .backupSeed)
        do {
            try container.encodeIfPresent(keycloakServer, forKey: .keycloak)
        } catch {
            assertionFailure("Could not backup keycloak server: \(error.localizedDescription)")
            // In production, we continue anyway
        }
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.privateIdentity = try values.decode(ObvOwnedCryptoIdentityPrivateBackupItem.self, forKey: .privateIdentity)
        guard let secretMACKey = self.privateIdentity.secretMACKey else {
            assertionFailure()
            throw Self.makeError(message: "Failed to parse secret MAC Key")
        }
        let identity = try values.decode(Data.self, forKey: .cryptoIdentity)
        guard let cryptoIdentity = ObvCryptoIdentity(from: identity) else {
            throw OwnedIdentityBackupItem.makeError(message: "Could not get crypto identity")
        }
        self.cryptoIdentity = cryptoIdentity
        self.contactIdentities = try values.decode(Set<ContactIdentityBackupItem>.self, forKey: .contactIdentities)
        self.publishedIdentityDetails = try values.decode(OwnedIdentityDetailsPublishedBackupItem.self, forKey: .publishedIdentityDetails)
        self.ownedGroups = try values.decodeIfPresent(Set<ContactGroupOwnedBackupItem>.self, forKey: .ownedGroups)
        self.contactGroupsV2 = try values.decodeIfPresent(Set<ContactGroupV2BackupItem>.self, forKey: .contactGroupsV2) ?? Set<ContactGroupV2BackupItem>()
        self.backupSeed = try values.decodeIfPresent(BackupSeed.self, forKey: .backupSeed) ?? OwnedIdentity.getDeterministicBackupSeedForLegacyIdentity(secretMACKey: secretMACKey)
        do {
            self.keycloakServer = try values.decodeIfPresent(KeycloakServerBackupItem.self, forKey: .keycloak)
        } catch {
            self.keycloakServer = nil
            assertionFailure("Could not recover keycloak server during backup restore: \(error.localizedDescription)")
            // In production, we continue anyway
        }
        // If the isActive is not present, its an old backup, we assume the identity was active.
        self.isActive = try values.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    }
    
    func restoreInstance(prng: PRNGService, within context: NSManagedObjectContext, associations: inout BackupItemObjectAssociations) throws {
        let ownedIdentity = try OwnedIdentity(backupItem: self, prng: prng, within: context)
        try associations.associate(ownedIdentity, to: self)
        let ownedIdentityIdentity = try ownedIdentity.cryptoIdentity.getIdentity()
        _ = try contactIdentities.map { try $0.restoreInstance(within: context, ownedIdentityIdentity: ownedIdentityIdentity, associations: &associations) }
        try publishedIdentityDetails.restoreInstance(within: context, associations: &associations)
        _ = try ownedGroups?.map { try $0.restoreInstance(within: context, associations: &associations) }
        try contactGroupsV2.forEach({ try $0.restoreInstance(within: context, associations: &associations, ownedIdentity: ownedIdentity.cryptoIdentity.getIdentity()) })
        try keycloakServer?.restoreInstance(within: context, associations: &associations, rawOwnedIdentity: ownedIdentity.cryptoIdentity.getIdentity())
    }
    
    
    func restoreRelationships(associations: BackupItemObjectAssociations, prng: PRNGService, within context: NSManagedObjectContext) throws {
        let ownedIdentity: OwnedIdentity = try associations.getObject(associatedTo: self, within: context)
        
        // Restore the relationships of this instance
        
        let contactGroups: Set<ContactGroup>
        do {
            let ownedGroups: Set<ContactGroupOwned> = Set(try self.ownedGroups?.map({ try associations.getObject(associatedTo: $0, within: context) }) ?? [])
            var joinedGroups = Set<ContactGroupJoined>()
            for contact in self.contactIdentities {
                let contactGroupsOwnedByContact: Set<ContactGroupJoined> = Set(try contact.contactGroupsOwnedByContact.map({ try associations.getObject(associatedTo: $0, within: context) }))
                joinedGroups.formUnion(contactGroupsOwnedByContact)
            }
            contactGroups = (ownedGroups as Set<ContactGroup>).union(joinedGroups)
        }
        
        let contactGroupsV2: Set<ContactGroupV2> = Set(try self.contactGroupsV2.map({ try associations.getObject(associatedTo: $0, within: context) }) )
        
        let contactIdentities: Set<ContactIdentity> = Set(try self.contactIdentities.map({ try associations.getObject(associatedTo: $0, within: context) }))
        
        let currentDevice = OwnedDeviceBackupItem.generateNewCurrentDevice(prng: prng, within: context)
        
        let publishedIdentityDetails: OwnedIdentityDetailsPublished = try associations.getObject(associatedTo: self.publishedIdentityDetails, within: context)
        
        let keycloakServer: KeycloakServer? = try associations.getObjectIfPresent(associatedTo: self.keycloakServer, within: context)
        
        ownedIdentity.restoreRelationships(contactGroups: contactGroups,
                                           contactGroupsV2: contactGroupsV2,
                                           contactIdentities: contactIdentities,
                                           currentDevice: currentDevice,
                                           publishedIdentityDetails: publishedIdentityDetails,
                                           keycloakServer: keycloakServer)
        
        // Restore the relationships of this instance relationships
        
        try self.contactIdentities.forEach({ try $0.restoreRelationships(associations: associations,
                                                                         within: context) })
        
        try self.publishedIdentityDetails.restoreRelationships(associations: associations, within: context)
        
        try self.ownedGroups?.forEach({ try $0.restoreRelationships(associations: associations, within: context) })
        
        try self.contactGroupsV2.forEach({ try $0.restoreRelationships(associations: associations, within: context) })
        
        try self.keycloakServer?.restoreRelationships(associations: associations, within: context)
        
        // If there is a photoServerLabel within the published details, we create an instance of IdentityServerUserData
        
        if let photoServerLabel = publishedIdentityDetails.photoServerLabel {
            _ = IdentityServerUserData.createForOwnedIdentityDetails(ownedIdentity: try ownedIdentity.cryptoIdentity,
                                                                     label: photoServerLabel,
                                                                     within: context)
        }
        
        // We scan each owned group. For each, of there is a photoServerLabel within the published details, we create an instance of IdentityServerUserData
        
        for contactGroup in contactGroups {
            guard let ownedGroup = contactGroup as? ContactGroupOwned else { continue }
            guard let photoServerLabel = ownedGroup.publishedDetails.photoServerLabel else { continue }
            _ = GroupServerUserData.createForOwnedGroupDetails(ownedIdentity: try ownedIdentity.cryptoIdentity,
                                                               label: photoServerLabel,
                                                               groupUid: try ownedGroup.groupUid,
                                                               within: context)
        }
        
        // We scan each group V2 for which we are an administrator. If we are in charge of the profile picture (i.e., we are the uploader of the profile picture), we create a GroupV2ServerUserData entry
        
        for group in contactGroupsV2 {
            guard let serverPhotoInfo = group.trustedDetails?.serverPhotoInfo, let groupIdentifier = group.groupIdentifier else { continue }
            if try serverPhotoInfo.identity == ownedIdentity.cryptoIdentity {
                _ = try? GroupV2ServerUserData.getOrCreateIfRequiredForAdministratedGroupV2Details(
                    ownedIdentity: ownedIdentity.cryptoIdentity,
                    label: serverPhotoInfo.photoServerKeyAndLabel.label,
                    groupIdentifier: groupIdentifier,
                    within: context)
            }
        }
        
    }

}


// MARK: - Computing deterministic Seed and BackupSeed

extension OwnedIdentity {
        
    func getDeterministicSeed(diversifiedUsing data: Data, forProtocol seedProtocol: ObvConstants.SeedProtocol) throws -> Seed {
        let secretMACKey = try self.ownedCryptoIdentity.secretMACKey
        return try Self.getDeterministicSeed(diversifiedUsing: data, secretMACKey: secretMACKey, forProtocol: seedProtocol)
    }
    
    
    static func getDeterministicSeed(diversifiedUsing data: Data, secretMACKey: any MACKey, forProtocol seedProtocol: ObvConstants.SeedProtocol) throws -> Seed {
        guard !data.isEmpty else {
            throw ObvIdentityManagerError.diversificationDataCannotBeEmpty
        }
        let sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()
        let fixedByte = Data([seedProtocol.fixedByte])
        var hashInput = try MAC.compute(forData: fixedByte, withKey: secretMACKey)
        hashInput.append(data)
        let r = sha256.hash(hashInput)
        guard let seed = Seed(with: r) else {
            throw ObvIdentityManagerError.failedToTurnRandomIntoSeed
        }
        return seed
    }
    
    
    func getDeterministicBackupSeedForLegacyIdentity() throws -> BackupSeed {
        let secretMACKey = try self.ownedCryptoIdentity.secretMACKey
        return try Self.getDeterministicBackupSeedForLegacyIdentity(secretMACKey: secretMACKey)
    }
    
    
    static func getDeterministicBackupSeedForLegacyIdentity(secretMACKey: any MACKey) throws -> BackupSeed {
        let data = ObvConstants.BackupSeedForLegacyIdentity.hashPadding
        let sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()
        let fixedByte = Data([ObvConstants.BackupSeedForLegacyIdentity.macPayload])
        var hashInput = try MAC.compute(forData: fixedByte, withKey: secretMACKey)
        hashInput.append(data)
        let r = sha256.hash(hashInput)
        guard let backupSeed = BackupSeed(with: r.prefix(BackupSeed.byteLength)) else {
            throw ObvIdentityManagerError.failedToTurnRandomIntoSeed
        }
        return backupSeed
    }
    
}



// MARK: - For snapshots

extension OwnedIdentity {
    
    var syncSnapshotNode: OwnedIdentitySyncSnapshotNode {
        get throws {
            .init(ownedCryptoIdentity: try ownedCryptoIdentity,
                  contactIdentities: contactIdentities,
                  publishedIdentityDetails: publishedIdentityDetails,
                  keycloakServer: keycloakServer,
                  contactGroups: contactGroups,
                  contactGroupsV2: contactGroupsV2,
                  backupSeed: try backupSeed)
        }
    }
    
    
    var deviceSnapshotNode: OwnedIdentityDeviceSnapshotNode {
        get throws {
            .init(publishedIdentityDetails: publishedIdentityDetails,
                  isKeycloakManaged: isKeycloakManaged,
                  backupSeed: try backupSeed)
        }
    }

}


///  Snapshot used during a device backup
struct OwnedIdentityDeviceSnapshotNode: ObvSyncSnapshotNode, Codable {

    private let domain: Set<CodingKeys>
    private let publishedIdentityDetails: OwnedIdentityDetailsPublishedSyncSnapshotNode
    private let isKeycloakManaged: Bool
    private let backupSeed: BackupSeed
    
    let id = Self.generateIdentifier()

    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        case publishedIdentityDetails = "published_details"
        case isKeycloakManaged = "keycloak_managed"
        case backupSeed = "backup_seed"
        case domain = "domain"
    }

    private static let defaultDomain = Set(CodingKeys.allCases.filter({ $0 != .domain }))

    init(publishedIdentityDetails: OwnedIdentityDetailsPublished, isKeycloakManaged: Bool, backupSeed: BackupSeed) {
        
        self.publishedIdentityDetails = publishedIdentityDetails.snapshotNode
        self.isKeycloakManaged = isKeycloakManaged
        self.backupSeed = backupSeed
        
        self.domain = Self.defaultDomain
        
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(domain, forKey: .domain)
        try container.encode(publishedIdentityDetails, forKey: .publishedIdentityDetails)
        try container.encode(isKeycloakManaged, forKey: .isKeycloakManaged)
        try container.encode(backupSeed.raw, forKey: .backupSeed)
    }
 
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.domain = try values.decode(Set<CodingKeys>.self, forKey: .domain)
        self.publishedIdentityDetails = try values.decode(OwnedIdentityDetailsPublishedSyncSnapshotNode.self, forKey: .publishedIdentityDetails)
        self.isKeycloakManaged = try values.decodeIfPresent(Bool.self, forKey: .isKeycloakManaged) ?? false
        self.backupSeed = try values.decode(BackupSeed.self, forKey: .backupSeed)
    }

    enum ObvError: Error {
        case backupSeedParseError
    }
    
    
    /// Called when parsing a device backup downloaded from the server
    func toObvDeviceBackupFromServerProfile(ownedCryptoId: ObvCryptoId) throws -> ObvTypes.ObvDeviceBackupFromServer.Profile {
        
        let coreDetails = try publishedIdentityDetails.toObvIdentityCoreDetails()
        let photoServerLabel = publishedIdentityDetails.photoServerKeyAndLabel
        let encodedPhotoServerKeyAndLabel = try? photoServerLabel?.jsonEncode()
        
        let profile = ObvTypes.ObvDeviceBackupFromServer.Profile(
            ownedCryptoId: ownedCryptoId,
            isKeycloakManaged: isKeycloakManaged,
            backupSeed: backupSeed,
            coreDetails: coreDetails,
            encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel)
        
        return profile
        
    }
    
}


///  Snapshot used during a transfer
struct OwnedIdentitySyncSnapshotNode: ObvSyncSnapshotNode, Codable, Sendable {
    
    private let domain: Set<CodingKeys>
    fileprivate let privateIdentity: ObvOwnedCryptoIdentityPrivateSnapshotItem?
    private let publishedIdentityDetails: OwnedIdentityDetailsPublishedSyncSnapshotNode?
    private let keycloakServer: KeycloakServerSnapshotNode?
    fileprivate let backupSeed: BackupSeed
    private let contacts: [ObvCryptoIdentity: ContactIdentitySyncSnapshotNode]
    private let groupsV1: [GroupV1Identifier: ContactGroupSyncSnapshotNode]
    private let groupsV2: [GroupV2.Identifier: ContactGroupV2SyncSnapshotNode]

    let id = Self.generateIdentifier()

    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        case privateIdentity = "private_identity"
        case publishedIdentityDetails = "published_details"
        case keycloak = "keycloak"
        case contacts = "contacts"
        case groups = "groups"
        case groups2 = "groups2"
        case backupSeed = "backup_seed"
        case domain = "domain"
    }
    
    private static let defaultDomain = Set(CodingKeys.allCases.filter({ $0 != .domain }))

    
    init(ownedCryptoIdentity: ObvOwnedCryptoIdentity, contactIdentities: Set<ContactIdentity>, publishedIdentityDetails: OwnedIdentityDetailsPublished, keycloakServer: KeycloakServer?, contactGroups: Set<ContactGroup>, contactGroupsV2: Set<ContactGroupV2>, backupSeed: BackupSeed) {
        self.privateIdentity = ownedCryptoIdentity.snapshotItem
        self.publishedIdentityDetails = publishedIdentityDetails.snapshotNode
        self.keycloakServer = keycloakServer?.snapshotNode
        self.backupSeed = backupSeed
        // contacts
        do {
            let pairs: [(ObvCryptoIdentity, ContactIdentitySyncSnapshotNode)] = contactIdentities
                .compactMap { contact in
                    guard let cryptoIdentity = contact.cryptoIdentity else { assertionFailure(); return nil }
                    guard let syncSnapshot = contact.syncSnapshot else { assertionFailure(); return nil }
                    return (cryptoIdentity, syncSnapshot)
                }
            self.contacts = Dictionary(pairs, uniquingKeysWith: { (first, _) in assertionFailure(); return first })
        }
        // groupsV1
        do {
            let pairs: [(GroupV1Identifier, ContactGroupSyncSnapshotNode)] = contactGroups.compactMap {
                guard let groupV1Identifier = $0.groupV1Identifier else { assertionFailure(); return nil }
                guard let syncSnapshot = try? $0.syncSnapshot else { assertionFailure(); return nil }
                return (groupV1Identifier, syncSnapshot)
            }
            self.groupsV1 = Dictionary(pairs, uniquingKeysWith: { (first, _) in assertionFailure(); return first })
        }
        // groupsV2
        do {
            let keysAndValues: [(GroupV2.Identifier, ContactGroupV2SyncSnapshotNode)] = contactGroupsV2.compactMap { group in
                guard let groupIdentifier = group.groupIdentifier else { assertionFailure(); return nil }
                guard let snapshotNode = group.snapshotNode else { assertionFailure(); return nil }
                return (groupIdentifier, snapshotNode)
            }
            self.groupsV2 = Dictionary(keysAndValues, uniquingKeysWith: { (first, _) in assertionFailure(); return first })
        }
        self.domain = Self.defaultDomain
    }
    
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(domain, forKey: .domain)
        try container.encode(privateIdentity, forKey: .privateIdentity)
        try container.encode(publishedIdentityDetails, forKey: .publishedIdentityDetails)
        try container.encode(backupSeed, forKey: .backupSeed)
        try container.encodeIfPresent(keycloakServer, forKey: .keycloak)
        // Encode the contacts using the ObvCryptoIdentity as a JSON key
        do {
            let dict: [String: ContactIdentitySyncSnapshotNode] = .init(contacts, keyMapping: { $0.getIdentity().base64EncodedString() }, valueMapping: { $0 })
            try container.encode(dict, forKey: .contacts)
        }
        // Encode groupsV1 using the GroupV1Identifier as a JSON key
        do {
            let dict: [String: ContactGroupSyncSnapshotNode] = .init(groupsV1, keyMapping: { $0.description }, valueMapping: { $0 })
            try container.encode(dict, forKey: .groups)
        }
        // Encode groupsV2 using the GroupV2.Identifier as a JSON key
        do {
            let dict: [String: ContactGroupV2SyncSnapshotNode] = .init(groupsV2, keyMapping: { $0.description }, valueMapping: { $0 })
            try container.encode(dict, forKey: .groups2)
        }
    }
    
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.domain = try values.decode(Set<CodingKeys>.self, forKey: .domain)
        let privateIdentity = try values.decodeIfPresent(ObvOwnedCryptoIdentityPrivateSnapshotItem.self, forKey: .privateIdentity)
        self.privateIdentity = privateIdentity
        guard let secretMACKey = privateIdentity?.secretMACKey else {
            assertionFailure()
            throw ObvError.failedToParseSecretMACKey
        }
        self.publishedIdentityDetails = try values.decodeIfPresent(OwnedIdentityDetailsPublishedSyncSnapshotNode.self, forKey: .publishedIdentityDetails)
        self.keycloakServer = try values.decodeIfPresent(KeycloakServerSnapshotNode.self, forKey: .keycloak)
        self.backupSeed = try values.decodeIfPresent(BackupSeed.self, forKey: .backupSeed) ?? OwnedIdentity.getDeterministicBackupSeedForLegacyIdentity(secretMACKey: secretMACKey)
        // Decode contacts (the keys are the contact identities)
        do {
            let dict = try values.decodeIfPresent([String: ContactIdentitySyncSnapshotNode].self, forKey: .contacts) ?? [:]
            self.contacts = Dictionary(dict, keyMapping: { $0.base64EncodedToData?.identityToObvCryptoIdentity }, valueMapping: { $0 })
        }
        // Decode groupsV1 (the keys are GroupV1Identifier)
        do {
            let dict = try values.decodeIfPresent([String: ContactGroupSyncSnapshotNode].self, forKey: .groups) ?? [:]
            self.groupsV1 = Dictionary(dict, keyMapping: { GroupV1Identifier($0) }, valueMapping: { $0 })
        }
        // Decode groupsV2 (the keys are GroupV2.Identifier)
        do {
            let dict = try values.decodeIfPresent([String: ContactGroupV2SyncSnapshotNode].self, forKey: .groups2) ?? [:]
            self.groupsV2 = Dictionary(dict, keyMapping: { GroupV2.Identifier($0) }, valueMapping: { $0 })
        }
    }
    
    
    /// Set `allowOwnedIdentityToExist` iff this is used to simulate a restore (today, this only happens when parsing a new backup to display it to the user).
    func restoreInstance(cryptoIdentity: ObvCryptoIdentity, allowOwnedIdentityToExistInDatabase: Bool, within context: NSManagedObjectContext, associations: inout SnapshotNodeManagedObjectAssociations) throws {
        
        guard domain.contains(.privateIdentity) && domain.contains(.publishedIdentityDetails) else {
            assertionFailure()
            throw ObvError.tryingToRestoreIncompleteNode
        }
        
        let ownedIdentityExists = try OwnedIdentity.exists(cryptoIdentity, within: context)
        
        guard !ownedIdentityExists || allowOwnedIdentityToExistInDatabase else {
            assertionFailure("We are not allowed to restore an owned identity that already exists")
            throw ObvIdentityManagerError.ownedIdentityAlreadyExists
        }
        
        let ownedIdentity = try OwnedIdentity(cryptoIdentity: cryptoIdentity, snapshotNode: self, within: context)
        try associations.associate(ownedIdentity, to: self)

        let ownedCryptoIdentity = try ownedIdentity.cryptoIdentity
        let ownedIdentityIdentity = ownedCryptoIdentity.getIdentity()

        if domain.contains(.contacts) {
            try contacts.forEach { (cryptoIdentity, contactNode) in
                try contactNode.restoreInstance(within: context, contactCryptoId: cryptoIdentity, ownedIdentityIdentity: ownedIdentityIdentity, associations: &associations)
            }
        }

        guard let publishedIdentityDetails else {
            assertionFailure()
            throw ObvError.publishedIdentityDetailsAreNil
        }
        
        try publishedIdentityDetails.restoreInstance(within: context, associations: &associations)

        if domain.contains(.groups) {
            try groupsV1.forEach { (groupV1Identifier, groupV1Node) in
                try groupV1Node.restoreInstance(within: context, ownedCryptoIdentity: ownedCryptoIdentity, groupV1Identifier: groupV1Identifier, associations: &associations)
            }
        }

        if domain.contains(.groups2) {
            try groupsV2.forEach { (groupIdentifier, groupV2Node) in
                try groupV2Node.restoreInstance(within: context, groupIdentifier: groupIdentifier, ownedIdentity: ownedIdentityIdentity, associations: &associations)
            }
        }
        
        if domain.contains(.keycloak) {
            try keycloakServer?.restoreInstance(within: context, associations: &associations, rawOwnedIdentity: ownedIdentityIdentity)
        }
        
    }

    
    func restoreRelationships(associations: SnapshotNodeManagedObjectAssociations, prng: PRNGService, customDeviceName: String, within context: NSManagedObjectContext) throws {

        // Fetch all core data instances
        
        let ownedIdentity: OwnedIdentity = try associations.getObject(associatedTo: self, within: context)
                
        let contactGroupsV1: [GroupV1Identifier: ContactGroup] = try .init(groupsV1, keyMapping: { $0 }, valueMapping: { try associations.getObject(associatedTo: $0, within: context) })

        let contactGroupsV2: [GroupV2.Identifier: ContactGroupV2] = try .init(groupsV2, keyMapping: { $0 }, valueMapping: { try associations.getObject(associatedTo: $0, within: context) })
        
        let contactIdentities: [ObvCryptoIdentity: ContactIdentity] = try .init(contacts, keyMapping: { $0 }, valueMapping: { try associations.getObject(associatedTo: $0, within: context) })
        
        let currentDevice = OwnedDeviceSnapshotItem.generateNewCurrentDevice(prng: prng, customDeviceName: customDeviceName, within: context)

        guard let publishedIdentityDetails else {
            assertionFailure()
            throw ObvError.tryingToRestoreIncompleteNode
        }
        
        let ownedIdentityDetailsPublished: OwnedIdentityDetailsPublished = try associations.getObject(associatedTo: publishedIdentityDetails, within: context)
        
        let keycloakServer: KeycloakServer? = try associations.getObjectIfPresent(associatedTo: self.keycloakServer, within: context)

        // Restore the relationships of this instance

        ownedIdentity.restoreRelationships(
            contactGroups: Set(contactGroupsV1.values),
            contactGroupsV2: Set(contactGroupsV2.values),
            contactIdentities: Set(contactIdentities.values),
            currentDevice: currentDevice,
            publishedIdentityDetails: ownedIdentityDetailsPublished,
            keycloakServer: keycloakServer)

        // Restore the relationships of this instance relationships

        try self.contacts.forEach { (contactCryptoIdentity, contactNode) in
            try contactNode.restoreRelationships(associations: associations, within: context)
        }
        
        try self.publishedIdentityDetails?.restoreRelationships(associations: associations, within: context)

        try self.groupsV1.forEach { (groupV1Identifier, groupV1Node) in
            try groupV1Node.restoreRelationships(associations: associations, groupV1Identifier: groupV1Identifier, contactIdentities: contactIdentities, within: context)
        }
        
        try self.groupsV2.forEach { (groupIdentifier, groupV2Node) in
            try groupV2Node.restoreRelationships(associations: associations, ownedIdentity: ownedIdentity.cryptoIdentity.getIdentity(), contactIdentities: contactIdentities, within: context)
        }
        
        try self.keycloakServer?.restoreRelationships(associations: associations, within: context)
        
        // If there is a photoServerLabel within the published details, we create an instance of IdentityServerUserData
        
        if let photoServerLabel = publishedIdentityDetails.photoServerLabel {
            _ = IdentityServerUserData.createForOwnedIdentityDetails(ownedIdentity: try ownedIdentity.cryptoIdentity,
                                                                     label: photoServerLabel,
                                                                     within: context)
        }
        
        // We scan each owned group. For each, of there is a photoServerLabel within the published details, we create an instance of IdentityServerUserData
        
        for contactGroup in contactGroupsV1.values {
            guard let ownedGroup = contactGroup as? ContactGroupOwned else { continue }
            guard let photoServerLabel = ownedGroup.publishedDetails.photoServerLabel else { continue }
            _ = GroupServerUserData.createForOwnedGroupDetails(ownedIdentity: try ownedIdentity.cryptoIdentity,
                                                               label: photoServerLabel,
                                                               groupUid: try ownedGroup.groupUid,
                                                               within: context)
        }
        
        // We scan each group V2 for which we are an administrator. If we are in charge of the profile picture (i.e., we are the uploader of the profile picture), we create a GroupV2ServerUserData entry
        
        for group in contactGroupsV2.values {
            guard let serverPhotoInfo = group.trustedDetails?.serverPhotoInfo, let groupIdentifier = group.groupIdentifier else { continue }
            if try serverPhotoInfo.identity == ownedIdentity.cryptoIdentity {
                _ = try? GroupV2ServerUserData.getOrCreateIfRequiredForAdministratedGroupV2Details(
                    ownedIdentity: ownedIdentity.cryptoIdentity,
                    label: serverPhotoInfo.photoServerKeyAndLabel.label,
                    groupIdentifier: groupIdentifier,
                    within: context)
            }
        }
        
        // Refresh the keycloak badges
        
        ownedIdentity.refreshCertifiedByOwnKeycloakAndTrustedDetailsForAllContacts()
        
    }
    
    enum ObvError: Error {
        case duplicateContact
        case tryingToRestoreIncompleteNode
        case mismatchBetweenDomainAndValues
        case publishedIdentityDetailsAreNil
        case failedToParseSecretMACKey
    }
    
}


// MARK: - OwnedIdentity observers

protocol OwnedIdentityObserver: AnyObject {
    func previousBackedUpDeviceSnapShotIsObsoleteAsOwnedIdentityChanged() async
    func previousBackedUpProfileSnapShotIsObsoleteAsOwnedIdentityChangedOrWasInserted(ownedCryptoId: ObvCryptoId) async
    func anOwnedIdentityWasDeleted(deletedOwnedCryptoId: ObvCryptoIdentity) async
}

extension OwnedIdentityObserver {
    func previousBackedUpDeviceSnapShotIsObsoleteAsOwnedIdentityChanged() async {}
    func previousBackedUpProfileSnapShotIsObsoleteAsOwnedIdentityChangedOrWasInserted(ownedCryptoId: ObvCryptoId) async {}
    func anOwnedIdentityWasDeleted(deletedOwnedCryptoId: ObvCryptoIdentity) async {}
}

private actor ObserversHolder: OwnedIdentityObserver {
    
    private var observers = [WeakObserver]()
    
    private final class WeakObserver {
        private(set) weak var value: OwnedIdentityObserver?
        init(value: OwnedIdentityObserver?) {
            self.value = value
        }
    }

    func addObserver(_ newObserver: OwnedIdentityObserver) {
        self.observers.append(.init(value: newObserver))
    }

    // Implementing OwnedIdentityObserver

    func previousBackedUpProfileSnapShotIsObsoleteAsOwnedIdentityChangedOrWasInserted(ownedCryptoId: ObvCryptoId) async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for observer in observers.compactMap(\.value) {
                taskGroup.addTask { await observer.previousBackedUpProfileSnapShotIsObsoleteAsOwnedIdentityChangedOrWasInserted(ownedCryptoId: ownedCryptoId) }
            }
        }
    }
    
    func previousBackedUpDeviceSnapShotIsObsoleteAsOwnedIdentityChanged() async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for observer in observers.compactMap(\.value) {
                taskGroup.addTask { await observer.previousBackedUpDeviceSnapShotIsObsoleteAsOwnedIdentityChanged() }
            }
        }
    }
    
    func anOwnedIdentityWasDeleted(deletedOwnedCryptoId: ObvCryptoIdentity) async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for observer in observers.compactMap(\.value) {
                taskGroup.addTask { await observer.anOwnedIdentityWasDeleted(deletedOwnedCryptoId: deletedOwnedCryptoId) }
            }
        }
    }

}

// MARK: - Private Helpers

private extension String {
    
    var base64EncodedToData: Data? {
        guard let data = Data(base64Encoded: self) else { assertionFailure(); return nil }
        return data
    }
    
}


private extension Data {
    
    var identityToObvCryptoIdentity: ObvCryptoIdentity? {
        guard let cryptoIdentity = ObvCryptoIdentity(from: self) else { assertionFailure(); return nil }
        return cryptoIdentity
    }
    
}
