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
import OlvidUtils
import ObvCrypto
import ObvTypes
import ObvEncoder
import ObvMetaManager
import JWS


@objc(ContactIdentity)
final class ContactIdentity: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "ContactIdentity"
    static let cryptoIdentityKey = "cryptoIdentity"
    private static let devicesKey = "devices"
    static let ownedIdentityKey = "ownedIdentity"
    private static let ownedIdentityCryptoIdentityKey = [ownedIdentityKey, OwnedIdentity.cryptoIdentityKey].joined(separator: ".")
    private static let persistedTrustOriginsKey = "persistedTrustOrigins"
    private static let trustOriginsKey = "trustOrigins"
    private static let contactGroupsKey = "contactGroups"
    private static let contactGroupsOwnedKey = "contactGroupsOwned"
    private static let publishedIdentityDetailsKey = "publishedIdentityDetails"
    private static let trustedIdentityDetailsKey = "trustedIdentityDetails"
    private static let errorDomain = "ContactIdentity"
    private static let isCertifiedByOwnKeycloak = "isCertifiedByOwnKeycloak"
    private static let isRevokedAsCompromisedKey = "isRevokedAsCompromised"
    private static let isForcefullyTrustedByUserKey = "isForcefullyTrustedByUser"
    
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { ContactIdentity.makeError(message: message) }

    // MARK: Attributes
    
    @NSManaged private(set) var cryptoIdentity: ObvCryptoIdentity // Unique (together with `ownedIdentity`)
    @NSManaged private(set) var isCertifiedByOwnKeycloak: Bool
    @NSManaged private(set) var isForcefullyTrustedByUser: Bool
    @NSManaged private(set) var isRevokedAsCompromised: Bool
    @NSManaged private var trustLevelRaw: String
    
    // MARK: Relationships
    
    private(set) var contactGroups: Set<ContactGroup> {
        get {
            let res = kvoSafePrimitiveValue(forKey: ContactIdentity.contactGroupsKey) as! Set<ContactGroup>
            return Set(res.map { $0.delegateManager = delegateManager; $0.obvContext = self.obvContext; return $0 })
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: ContactIdentity.contactGroupsKey)
        }
    }
    private var contactGroupsOwned: Set<ContactGroupJoined> {
        get {
            let res = kvoSafePrimitiveValue(forKey: ContactIdentity.contactGroupsOwnedKey) as! Set<ContactGroupJoined>
            return Set(res.map { $0.delegateManager = delegateManager; $0.obvContext = self.obvContext; return $0 })
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: ContactIdentity.contactGroupsOwnedKey)
        }
    }
    private(set) var devices: Set<ContactDevice> {
        get {
            let res = kvoSafePrimitiveValue(forKey: ContactIdentity.devicesKey) as! Set<ContactDevice>
            return Set(res.map { $0.delegateManager = delegateManager; $0.obvContext = self.obvContext; return $0 })
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: ContactIdentity.devicesKey)
        }
    }
    // Unique (together with `cryptoIdentity`)
    private(set) var ownedIdentity: OwnedIdentity {
        get {
            let res = kvoSafePrimitiveValue(forKey: ContactIdentity.ownedIdentityKey) as! OwnedIdentity
            res.delegateManager = delegateManager
            res.obvContext = self.obvContext
            return res
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: ContactIdentity.ownedIdentityKey)
        }
    }
    
    private(set) var persistedTrustOrigins: Set<PersistedTrustOrigin> {
        get {
            let items = kvoSafePrimitiveValue(forKey: ContactIdentity.persistedTrustOriginsKey) as! Set<PersistedTrustOrigin>
            return Set(items.map { $0.obvContext = self.obvContext; return $0 })
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: ContactIdentity.persistedTrustOriginsKey)
        }
    }
    
    private(set) var publishedIdentityDetails: ContactIdentityDetailsPublished? {
        get {
            let res = kvoSafePrimitiveValue(forKey: ContactIdentity.publishedIdentityDetailsKey) as! ContactIdentityDetailsPublished?
            res?.delegateManager = delegateManager
            res?.obvContext = self.obvContext
            return res
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: ContactIdentity.publishedIdentityDetailsKey)
        }
    }
    
    private(set) var trustedIdentityDetails: ContactIdentityDetailsTrusted {
        get {
            let res = kvoSafePrimitiveValue(forKey: ContactIdentity.trustedIdentityDetailsKey) as! ContactIdentityDetailsTrusted
            res.delegateManager = delegateManager
            res.obvContext = self.obvContext
            return res
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: ContactIdentity.trustedIdentityDetailsKey)
        }
    }
    
    // MARK: Other variables
    
    var trustOrigins: [TrustOrigin] {
        persistedTrustOrigins.sorted(by: { $0.timestamp > $1.timestamp }).compactMap { $0.trustOrigin }
    }
    
    // The following vars are only used to implement the ContactDeleted notification
    private var ownedIdentityCryptoIdentityOnDeletion: ObvCryptoIdentity?
    private var trustedContactIdentityDetailsOnDeletion: ObvIdentityDetails?
    
    private var trustLevelWasIncreased = false
    
    weak var delegateManager: ObvIdentityDelegateManager?
    
    var obvContext: ObvContext?

    private var changedKeys = Set<String>()

    var isActive: Bool {
        isForcefullyTrustedByUser || !isRevokedAsCompromised
    }
    
    // MARK: - Initializer
    
    /// This initializer enforces that there is a unique entry per `cryptoIdentity`, `ownedIdentity` pair.
    ///
    /// - Parameters:
    ///   - cryptoIdentity: The crypto identity of the contact identity to create.
    ///   - identityDetails: The identity details of the contact identity.
    ///   - ownedIdentity: The owned identity for which we add this contact.
    ///   - delegateManager: The `ObvIdentityDelegateManager`.
    convenience init?(cryptoIdentity: ObvCryptoIdentity, identityCoreDetails: ObvIdentityCoreDetails, trustOrigin: TrustOrigin, ownedIdentity: OwnedIdentity, delegateManager: ObvIdentityDelegateManager) {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: "ContactIdentity")
        guard let obvContext = ownedIdentity.obvContext else {
            os_log("Could not get context", log: log, type: .fault)
            return nil
        }
        
        // Integrity check
        do {
            guard try !ContactIdentity.exists(cryptoIdentity: cryptoIdentity, ownedIdentity: ownedIdentity, within: obvContext) else {
                os_log("Cannot add the same contact identity twice", log: log, type: .error)
                return nil
            }
        } catch let error {
            os_log("%@", log: log, type: .fault, error.localizedDescription)
            return nil
        }
        
        // Create a new entity
        let entityDescription = NSEntityDescription.entity(forEntityName: ContactIdentity.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        
        // Simple attributes
        self.cryptoIdentity = cryptoIdentity
        
        // Simple relationships
        self.contactGroups = Set<ContactGroup>()
        self.devices = Set<ContactDevice>()
        self.ownedIdentity = ownedIdentity
        guard let trustedIdentityDetails = ContactIdentityDetailsTrusted(contactIdentity: self,
                                                                         identityCoreDetails: identityCoreDetails,
                                                                         version: -1,
                                                                         delegateManager: delegateManager) else { return nil }
        self.trustedIdentityDetails = trustedIdentityDetails
        self.publishedIdentityDetails = nil
        self.isCertifiedByOwnKeycloak = false // This is updated later
        self.isForcefullyTrustedByUser = false
        self.isRevokedAsCompromised = false
        
        // Attributes and relationships related to Trust Origins and Trust Levels
        guard let persistedTrustOrigin = PersistedTrustOrigin(trustOrigin: trustOrigin, contact: self, delegateManager: delegateManager) else { return nil }
        guard let trustLevel = persistedTrustOrigin.trustLevel else { return nil }
        self.trustLevelRaw = trustLevel.rawValue
        self.persistedTrustOrigins = Set([persistedTrustOrigin])
        
        // And the rest
        self.delegateManager = delegateManager
        
        // Once all is set, we can refresh the keycloak aspects
        do {
            try refreshCertifiedByOwnKeycloakAndTrustedDetails(delegateManager: delegateManager)
        } catch {
            assertionFailure()
        }
    }
    
    
    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(backupItem: ContactIdentityBackupItem, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: ContactIdentity.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.cryptoIdentity = backupItem.cryptoIdentity
        self.trustLevelRaw = backupItem.trustLevelRaw
        self.isRevokedAsCompromised = backupItem.isRevokedAsCompromised
        self.isForcefullyTrustedByUser = backupItem.isForcefullyTrustedByUser
    }
    
    fileprivate func restoreRelationships(contactGroupsOwned: Set<ContactGroupJoined>, persistedTrustOrigins: Set<PersistedTrustOrigin>, publishedIdentityDetails: ContactIdentityDetailsPublished?, trustedIdentityDetails: ContactIdentityDetailsTrusted) {
        /* contactGroups is set within ContactGroup */
        self.contactGroupsOwned = contactGroupsOwned
        self.devices = Set<ContactDevice>()
        /* ownedIdentity is set within OwnedIdentity */
        self.persistedTrustOrigins = persistedTrustOrigins
        self.publishedIdentityDetails = publishedIdentityDetails
        self.trustedIdentityDetails = trustedIdentityDetails
    }

    
    func delete(delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) {
        self.delegateManager = delegateManager
        obvContext.delete(self)
    }
    
}


// MARK: - Managing trusted and published details, and photos

extension ContactIdentity {
 
    /// This method is the one to call to update the `isCertifiedByOwnKeycloak` flag. If the contact is indeed managed by the same keycloak than the one of the owned identity,
    /// it also updates the published/trusted details to match the values found in the signed details of the contact. Of course, if our owned identity is not managed or if there are no signed details,
    /// this method only sets the `isCertifiedByOwnKeycloak` flag to `false`.
    func refreshCertifiedByOwnKeycloakAndTrustedDetails(delegateManager: ObvIdentityDelegateManager) throws {

        isCertifiedByOwnKeycloak = false

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactIdentity.entityName)

        guard let obvContext = self.obvContext else { assertionFailure(); throw makeError(message: "Could not find ObvContext") }
        
        guard ownedIdentity.isKeycloakManaged else {
            return
        }

        let details = publishedIdentityDetails ?? trustedIdentityDetails
        guard let signedUserDetails = details.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory).coreDetails.signedUserDetails else {
            return
        }
        
        // If we reach this point, the owned identity is managed by keycloak and the contact has signed details.
                
        guard let ownKeycloakServer = ownedIdentity.keycloakServer else {
            assertionFailure("Since the owned identity is keycloak managed, we expect a server here")
            return
        }

        
        // We check whether the identity is part of the KeycloakRevokedIdentity table.
        // Among the returned revocation, look for those that have a compromised type. If there is one, this contact should be revoked as compromised and we return.
        // If the identity is not compromised, look for revocations that are more recent than the details signature, and uncertify the identity if one is found

        let revocations = try KeycloakRevokedIdentity.get(keycloakServer: ownKeycloakServer, identity: self.cryptoIdentity)

        do {
            let revocationsCompromised = revocations.filter({ (try? $0.revocationType) == .compromised })
            guard revocationsCompromised.isEmpty else {
                assert(isCertifiedByOwnKeycloak == false)
                revokeAsCompromised(delegateManager: delegateManager) // This deletes the devices of the contact
                return
            }
        }
        
        let signedContactUserDetails: SignedUserDetails
        do {
            signedContactUserDetails = try SignedUserDetails.verifySignedUserDetails(signedUserDetails, with: ownKeycloakServer.jwks).signedUserDetails
        } catch {
            os_log("The signature on the contact signed details is not valid (this also happens if the server signing key changes). We consider this contact as not managed by our own keycloak,", log: log, type: .info)
            assert(isCertifiedByOwnKeycloak == false)
            return
        }
        if let timestampOfSignedContactUserDetails = signedContactUserDetails.timestamp {
            let revocationsLeftCompany = revocations.filter({ (try? $0.revocationType) == .leftCompany && $0.revocationTimestamp > timestampOfSignedContactUserDetails })
            guard revocationsLeftCompany.isEmpty else {
                // The user left the company after the signature of his details --> unmark as certified
                assert(isCertifiedByOwnKeycloak == false)
                return
            }
        }
                
        // If we reach this point, the contact has details that are signed by our keycloak server.
        
        // We check that the signature on these details is not too old. If this is the case, we don't trust them since they should have been updated since then.
        
        if let timestampOfSignedContactUserDetails = signedContactUserDetails.timestamp {
            guard abs(timestampOfSignedContactUserDetails.timeIntervalSinceNow) < ObvConstants.keycloakSignatureValidity else {
                return
            }
        }
        
        // If these details are not trusted yet, we trust them now.
        
        if let publishedIdentityDetails = self.publishedIdentityDetails {
            try trustedIdentityDetails.updateWithContactIdentityDetailsPublished(publishedIdentityDetails, delegateManager: delegateManager)
            try publishedIdentityDetails.delete(identityPhotosDirectory: delegateManager.identityPhotosDirectory, within: obvContext)
            self.publishedIdentityDetails = nil
        }
        
        // If necessary, we update the trusted details using the signed details
        try trustedIdentityDetails.update(with: signedContactUserDetails, delegateManager: delegateManager)

        // If we reach this point, the contact is indeed certified by our own keycloak
        
        isCertifiedByOwnKeycloak = true
    }
    
    
    func getSignedUserDetails(identityPhotosDirectory: URL) throws -> SignedUserDetails? {
        let details = publishedIdentityDetails ?? trustedIdentityDetails
        guard let signedUserDetails = details.getIdentityDetails(identityPhotosDirectory: identityPhotosDirectory).coreDetails.signedUserDetails else {
            return nil
        }
        guard let ownKeycloakServer = ownedIdentity.keycloakServer else {
            return nil
        }
        let signedContactUserDetails = try SignedUserDetails.verifySignedUserDetails(signedUserDetails, with: ownKeycloakServer.jwks).signedUserDetails
        return signedContactUserDetails
    }
    
        
    func updateContactPhoto(with url: URL?, version: Int, delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) throws {
        if let publishedIdentityDetails = self.publishedIdentityDetails, publishedIdentityDetails.version == version {
            try publishedIdentityDetails.setContactPhoto(with: url, delegateManager: delegateManager)
        }
        if self.trustedIdentityDetails.version == version {
            try self.trustedIdentityDetails.setContactPhoto(with: url, delegateManager: delegateManager)
        }
    }

    
    func updateContactPhoto(withData photoData: Data, version: Int, delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) throws {
        if let publishedIdentityDetails = self.publishedIdentityDetails, publishedIdentityDetails.version == version {
            try publishedIdentityDetails.setContactPhoto(data: photoData, delegateManager: delegateManager)
        }
        if self.trustedIdentityDetails.version == version {
            try self.trustedIdentityDetails.setContactPhoto(data: photoData, delegateManager: delegateManager)
        }
    }

    
    func updateTrustedDetailsWithPublishedDetails(_ obvIdentityDetails: ObvIdentityDetails, delegateManager: ObvIdentityDelegateManager) throws {
        
        guard let obvContext = self.obvContext else { assertionFailure(); throw makeError(message: "Could not find ObvContext") }
        
        // We check that the identity details that were passed as a parameter are identical to the current published identity details of this contact
        guard let publishedIdentityDetails = self.publishedIdentityDetails else { assertionFailure(); return }
        guard publishedIdentityDetails.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory) == obvIdentityDetails else { assertionFailure(); return }
        
        // We do *not* consider the published/trusted version here. We were asked to trust the published details, so we trust them.
        // We can update the trusted details and delete the published details
        
        try trustedIdentityDetails.updateWithContactIdentityDetailsPublished(publishedIdentityDetails, delegateManager: delegateManager)
        try publishedIdentityDetails.delete(identityPhotosDirectory: delegateManager.identityPhotosDirectory, within: obvContext)

    }
    
    
    func updatePublishedDetailsAndTryToAutoTrustThem(with newContactIdentityDetailsElements: IdentityDetailsElements, allowVersionDowngrade: Bool, delegateManager: ObvIdentityDelegateManager) throws {
        
        if let currentPublishedDetails = self.publishedIdentityDetails {
            guard allowVersionDowngrade || newContactIdentityDetailsElements.version > currentPublishedDetails.version else { return }
            try currentPublishedDetails.updateWithNewContactIdentityDetailsElements(newContactIdentityDetailsElements, delegateManager: delegateManager)
        } else {
            guard allowVersionDowngrade || newContactIdentityDetailsElements.version > trustedIdentityDetails.version else { return }
            guard ContactIdentityDetailsPublished(contactIdentity: self, contactIdentityDetailsElements: newContactIdentityDetailsElements, delegateManager: delegateManager) != nil else { throw makeError(message: "Could not create ContactIdentityDetailsPublished") }
            assert(self.publishedIdentityDetails != nil)
            if self.trustedIdentityDetails.photoServerKeyAndLabel == self.publishedIdentityDetails?.photoServerKeyAndLabel {
                // We copy the photo found in the trusted details into the published details
                if let trustedPhotoURL = trustedIdentityDetails.getPhotoURL(identityPhotosDirectory: delegateManager.identityPhotosDirectory), FileManager.default.fileExists(atPath: trustedPhotoURL.path) {
                    try publishedIdentityDetails?.setContactPhoto(with: trustedPhotoURL, delegateManager: delegateManager)
                }
            }
        }
        
        // If we reach this point, we have published details. We now try to "auto-trust" them.

        try tryToAutoTrustPublishedDetails(delegateManager: delegateManager)
    }
    
    
    private func tryToAutoTrustPublishedDetails(delegateManager: ObvIdentityDelegateManager) throws {
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactIdentity.entityName)

        try refreshCertifiedByOwnKeycloakAndTrustedDetails(delegateManager: delegateManager)
        guard !isCertifiedByOwnKeycloak else {
            // If the contact is certified by our own keycloak, the call to refreshCertifiedByOwnKeycloakAndTrustedDetails has done all the work of updating the trusted details and deleting the published details
            assert(self.publishedIdentityDetails == nil)
            return
        }

        // If we reach this point, the contact is not managed by our own keycloak and we have published details that we may auto-trust.
        
        guard let publishedIdentityDetails = self.publishedIdentityDetails else {
            assertionFailure()
            throw makeError(message: "Published details are nil although they should not be at this point. This is a bug.")
        }
        
        // If we reach this point, the published details have a higher version than the trusted details. We try to "auto-trust" these published details
        
        let publishedCoreDetails = publishedIdentityDetails.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory).coreDetails
        let trustedCoreDetails = trustedIdentityDetails.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory).coreDetails
        guard publishedCoreDetails.fieldsAreTheSameAndSignedDetailsAreNotConsidered(than: trustedCoreDetails) else {
            // Since the details displayed to the user are different in the published details than in the trusted details, we cannot auto-trust them
            os_log("Fields are different", log: log, type: .info)
            return
        }
        
        // The visible fields of the published details are identical to the trusted fields. The remaining question: do we accept the profile picture?
        // We do in exactly two situations: when the version of the trusted details is -1, and when the profile picture is actually identical in both the trusted and published details.

        guard trustedIdentityDetails.version == -1 || trustedIdentityDetails.photoServerKeyAndLabel == publishedIdentityDetails.photoServerKeyAndLabel else {
            os_log("We cannot autotrust contact details (trusted details version is %d). Photo server key and label are different.", log: log, type: .info, trustedIdentityDetails.version)
            return
        }

        // If we reach this point, we can auto-trust the published details
        try updateTrustedDetailsWithPublishedDetails(publishedIdentityDetails.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory), delegateManager: delegateManager)

    }
    
    
    func revokeAsCompromised(delegateManager: ObvIdentityDelegateManager) {

        guard !self.isRevokedAsCompromised else { return }
        self.isRevokedAsCompromised = true
        
        if !isForcefullyTrustedByUser {
            self.devices.forEach { contactDevice in
                let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactIdentity.entityName)
                do {
                    try contactDevice.delete() // This will eventually delete the secure channels
                } catch {
                    os_log("Could not delete a device of a revoked contact. We continue.", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    // Continue anyway
                }
            }
        }
    }
    
    
    func setForcefullyTrustedByUser(to newValue: Bool, delegateManager: ObvIdentityDelegateManager) {
        guard self.isForcefullyTrustedByUser != newValue else { return }
        self.isForcefullyTrustedByUser = newValue
        if !isActive {
            self.devices.forEach { contactDevice in
                let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactIdentity.entityName)
                do {
                    try contactDevice.delete() // This will eventually delete the secure channels
                } catch {
                    os_log("Could not delete a device of a revoked contact. We continue.", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    // Continue anyway
                }
            }
        }
    }
}


// MARK: - Trust Level and Trust Origins

extension ContactIdentity {
    
    var trustLevel: TrustLevel {
        return TrustLevel(rawValue: self.trustLevelRaw)!
    }
    
    func addTrustOrigin(_ trustOrigin: TrustOrigin) throws {
        guard let delegateManager = self.delegateManager else { throw NSError() }
        guard let persistedTrustOrigin = PersistedTrustOrigin(trustOrigin: trustOrigin, contact: self, delegateManager: delegateManager) else { throw NSError() }
        guard let trustOriginTrustLevel = persistedTrustOrigin.trustLevel else { throw NSError() }
        if self.trustLevel < trustOriginTrustLevel {
            self.trustLevelRaw = trustOriginTrustLevel.rawValue
            trustLevelWasIncreased = true
        }
    }

}

// MARK: - ContactDevice management

extension ContactIdentity {
    
    func addIfNotExistDeviceWith(uid: UID, flowId: FlowIdentifier) throws {
        guard self.isActive else { throw makeError(message: "Cannot add a device to an inactive contact") }
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: "ContactIdentity")
            os_log("The delegate manager is not set (3)", log: log, type: .fault)
            throw ContactIdentity.makeError(message: "The delegate manager is not set (3)")
        }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: "ContactIdentity")
        let existingDeviceUids = devices.map { $0.uid }
        if !existingDeviceUids.contains(uid) {
            guard ContactDevice(uid: uid, contactIdentity: self, flowId: flowId, delegateManager: delegateManager) != nil else {
                os_log("Could not add a contact device", log: log, type: .fault)
                throw ContactIdentity.makeError(message: "Could not add a contact device")
            }
        }
    }
    
    func removeIfExistsDeviceWith(uid: UID, flowId: FlowIdentifier) throws {
        guard let obvContext = self.obvContext else {
            let log = OSLog(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: "ContactIdentity")
            os_log("The obvContext is not set in removeIfExistsDeviceWith", log: log, type: .fault)
            throw ContactIdentity.makeError(message: "The obvContext is not set in removeIfExistsDeviceWith")
        }
        for device in devices {
            guard device.uid == uid else { continue }
            obvContext.delete(device)
        }
    }
}


// MARK: - Capabilities

extension ContactIdentity {
    
    func setRawCapabilitiesOfDeviceWithUID(_ deviceUID: UID, newRawCapabilities: Set<String>) throws {
        guard let device = self.devices.first(where: { $0.uid == deviceUID }) else {
            throw makeError(message: "Could not find contact device")
        }
        device.setRawCapabilities(newRawCapabilities: newRawCapabilities)
    }
    
    
    var allCapabilities: Set<ObvCapability> {
        var capabilities = Set<ObvCapability>()
        ObvCapability.allCases.forEach { capability in
            switch capability {
            case .webrtcContinuousICE:
                if devices.allSatisfy({ $0.allCapabilities.contains(capability) }) {
                    capabilities.insert(capability)
                }
            }
        }
        return capabilities
    }
    
}


// MARK: - Convenience DB getters

extension ContactIdentity {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ContactIdentity> {
        return NSFetchRequest<ContactIdentity>(entityName: ContactIdentity.entityName)
    }
    
    class func get(contactIdentity: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity, delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) throws -> ContactIdentity? {
        let request: NSFetchRequest<ContactIdentity> = ContactIdentity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        ContactIdentity.cryptoIdentityKey, contactIdentity,
                                        ContactIdentity.ownedIdentityCryptoIdentityKey, ownedIdentity)
        request.fetchLimit = 1
        let item = (try obvContext.fetch(request)).first
        item?.delegateManager = delegateManager
        return item
    }

    static func getAll(delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) -> [ContactIdentity]? {
        let request: NSFetchRequest<ContactIdentity> = ContactIdentity.fetchRequest()
        let items = try? obvContext.fetch(request)
        return items?.map { $0.delegateManager = delegateManager; return $0 }
    }

    static func exists(cryptoIdentity: ObvCryptoIdentity, ownedIdentity: OwnedIdentity, within obvContext: ObvContext) throws -> Bool {
        let request: NSFetchRequest<ContactIdentity> = ContactIdentity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        ContactIdentity.cryptoIdentityKey, cryptoIdentity,
                                        ContactIdentity.ownedIdentityCryptoIdentityKey, ownedIdentity.ownedCryptoIdentity.getObvCryptoIdentity())
        return try obvContext.count(for: request) != 0
    }
}


// MARK: - Reacting to updates

extension ContactIdentity {
    
    override func prepareForDeletion() {
        super.prepareForDeletion()
        
        guard let delegateManager = delegateManager else { assertionFailure(); return }
        ownedIdentityCryptoIdentityOnDeletion = ownedIdentity.cryptoIdentity
        trustedContactIdentityDetailsOnDeletion = trustedIdentityDetails.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
        
    }
    
    override func willSave() {
        super.willSave()
        
        if isUpdated {
            changedKeys = Set<String>(self.changedValues().keys)
        }

    }
    
    override func didSave() {
        super.didSave()
                
        defer {
            changedKeys.removeAll()
        }
        
        guard let delegateManager = delegateManager else {
            let log = OSLog.init(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: String(describing: Self.self))
            os_log("The delegate manager is not set (5)", log: log, type: .fault)
            return
        }

        let log = OSLog.init(subsystem: delegateManager.logSubsystem, category: String(describing: Self.self))

        assert(obvContext != nil)
        let flowId = obvContext?.flowId ?? FlowIdentifier()
        
        if isInserted {

            do {
                os_log("Sending a ContactIdentityIsNowTrusted notification", log: log, type: .debug)
                let notification = ObvIdentityNotificationNew.contactIdentityIsNowTrusted(contactIdentity: cryptoIdentity, ownedIdentity: ownedIdentity.ownedCryptoIdentity.getObvCryptoIdentity(), flowId: flowId)
                notification.postOnBackgroundQueue(within: delegateManager.notificationDelegate)
            }
            
            do {
                os_log("Sending a ContactTrustLevelWasIncreased notification", log: log, type: .debug)
                let NotificationType = ObvIdentityNotification.ContactTrustLevelWasIncreased.self
                let userInfo = [NotificationType.Key.ownedIdentity: self.ownedIdentity.cryptoIdentity,
                                NotificationType.Key.contactIdentity: self.cryptoIdentity,
                                NotificationType.Key.trustLevelOfContactIdentity: self.trustLevel,
                                NotificationType.Key.flowId: flowId] as [String: Any]
                DispatchQueue(label: "Queue created in ContactIdentity for posting a ContactTrustLevelWasIncreased notification").async {
                    delegateManager.notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
                }
            }
                
        } else if isDeleted {
                        
            os_log("Sending a ContactWasDeleted notification", log: log, type: .debug)
            ObvIdentityNotificationNew.contactWasDeleted(ownedCryptoIdentity: ownedIdentityCryptoIdentityOnDeletion!,
                                                         contactCryptoIdentity: cryptoIdentity,
                                                         contactTrustedIdentityDetails: trustedContactIdentityDetailsOnDeletion!)
                .postOnBackgroundQueue(within: delegateManager.notificationDelegate)
            
        } else {
                        
            if !changedKeys.isEmpty {
                
                ObvIdentityNotificationNew.contactWasUpdatedWithinTheIdentityManager(ownedIdentity: self.ownedIdentity.cryptoIdentity, contactIdentity: self.cryptoIdentity, flowId: flowId)
                    .postOnBackgroundQueue(within: delegateManager.notificationDelegate)
                
            }
            
            if changedKeys.contains(ContactIdentity.isForcefullyTrustedByUserKey) || changedKeys.contains(ContactIdentity.isRevokedAsCompromisedKey) {
                
                ObvIdentityNotificationNew.contactIsActiveChanged(
                    ownedIdentity: ownedIdentity.cryptoIdentity,
                    contactIdentity: cryptoIdentity,
                    isActive: isActive,
                    flowId: flowId)
                    .postOnBackgroundQueue(within: delegateManager.notificationDelegate)
                
            }
            
            if changedKeys.contains(ContactIdentity.isRevokedAsCompromisedKey) && self.isRevokedAsCompromised {
                
                ObvIdentityNotificationNew.contactWasRevokedAsCompromised(
                    ownedIdentity: ownedIdentity.cryptoIdentity,
                    contactIdentity: cryptoIdentity,
                    flowId: flowId)
                    .postOnBackgroundQueue(within: delegateManager.notificationDelegate)
                
            }
            
        }

        if trustLevelWasIncreased {
            
            let NotificationType = ObvIdentityNotification.ContactTrustLevelWasIncreased.self
            let userInfo = [NotificationType.Key.ownedIdentity: self.ownedIdentity.cryptoIdentity,
                            NotificationType.Key.contactIdentity: self.cryptoIdentity,
                            NotificationType.Key.trustLevelOfContactIdentity: self.trustLevel,
                            NotificationType.Key.flowId: flowId] as [String: Any]
            DispatchQueue(label: "Queue created in ContactIdentity for posting a ContactTrustLevelWasIncreased notification").async {
                delegateManager.notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
            }
            
            trustLevelWasIncreased = false
            
        }

    }
}


// MARK: - For Backup purposes

extension ContactIdentity {
    
    var backupItem: ContactIdentityBackupItem {
        return ContactIdentityBackupItem(cryptoIdentity: cryptoIdentity,
                                         persistedTrustOrigins: persistedTrustOrigins,
                                         publishedIdentityDetails: publishedIdentityDetails,
                                         trustedIdentityDetails: trustedIdentityDetails,
                                         contactGroupsOwned: contactGroupsOwned,
                                         trustLevelRaw: trustLevelRaw,
                                         isRevokedAsCompromised: isRevokedAsCompromised,
                                         isForcefullyTrustedByUser: isForcefullyTrustedByUser)
    }

}


struct ContactIdentityBackupItem: Codable, Hashable {
    
    fileprivate let cryptoIdentity: ObvCryptoIdentity
    fileprivate let persistedTrustOrigins: Set<PersistedTrustOriginBackupItem>
    fileprivate let publishedIdentityDetails: ContactIdentityDetailsPublishedBackupItem?
    fileprivate let trustedIdentityDetails: ContactIdentityDetailsTrustedBackupItem
    let contactGroupsOwnedByContact: Set<ContactGroupJoinedBackupItem>
    fileprivate let trustLevelRaw: String
    fileprivate let isRevokedAsCompromised: Bool
    fileprivate let isForcefullyTrustedByUser: Bool

    private static let errorDomain = String(describing: ContactIdentityBackupItem.self)

    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    fileprivate init(cryptoIdentity: ObvCryptoIdentity, persistedTrustOrigins: Set<PersistedTrustOrigin>, publishedIdentityDetails: ContactIdentityDetailsPublished?, trustedIdentityDetails: ContactIdentityDetailsTrusted, contactGroupsOwned: Set<ContactGroupJoined>, trustLevelRaw: String, isRevokedAsCompromised: Bool, isForcefullyTrustedByUser: Bool) {
        self.cryptoIdentity = cryptoIdentity
        self.persistedTrustOrigins = Set(persistedTrustOrigins.map { $0.backupItem })
        self.publishedIdentityDetails = publishedIdentityDetails?.backupItem
        self.trustedIdentityDetails = trustedIdentityDetails.backupItem
        self.contactGroupsOwnedByContact = Set(contactGroupsOwned.map { $0.backupItem })
        self.trustLevelRaw = trustLevelRaw
        self.isRevokedAsCompromised = isRevokedAsCompromised
        self.isForcefullyTrustedByUser = isForcefullyTrustedByUser
    }
    
    enum CodingKeys: String, CodingKey {
        case cryptoIdentity = "contact_identity"
        case persistedTrustOrigins = "trust_origins"
        case publishedIdentityDetails = "published_details"
        case trustedIdentityDetails = "trusted_details"
        case contactGroupsOwned = "contact_groups" // Group owned by this contact, joined by the associated owned identity
        case trustLevelRaw = "trust_level"
        case isRevokedAsCompromised = "revoked"
        case isForcefullyTrustedByUser = "forcefully_trusted"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cryptoIdentity.getIdentity(), forKey: .cryptoIdentity)
        try container.encode(persistedTrustOrigins, forKey: .persistedTrustOrigins)
        try container.encodeIfPresent(publishedIdentityDetails, forKey: .publishedIdentityDetails)
        try container.encode(trustedIdentityDetails, forKey: .trustedIdentityDetails)
        try container.encode(contactGroupsOwnedByContact, forKey: .contactGroupsOwned)
        try container.encode(trustLevelRaw, forKey: .trustLevelRaw)
        try container.encode(isRevokedAsCompromised, forKey: .isRevokedAsCompromised)
        try container.encode(isForcefullyTrustedByUser, forKey: .isForcefullyTrustedByUser)
    }
 
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let identity = try values.decode(Data.self, forKey: .cryptoIdentity)
        guard let cryptoIdentity = ObvCryptoIdentity(from: identity) else {
            throw ContactIdentityBackupItem.makeError(message: "Could not parse crypto identity")
        }
        self.cryptoIdentity = cryptoIdentity
        self.persistedTrustOrigins = try values.decode(Set<PersistedTrustOriginBackupItem>.self, forKey: .persistedTrustOrigins)
        self.publishedIdentityDetails = try values.decodeIfPresent(ContactIdentityDetailsPublishedBackupItem.self, forKey: .publishedIdentityDetails)
        self.trustedIdentityDetails = try values.decode(ContactIdentityDetailsTrustedBackupItem.self, forKey: .trustedIdentityDetails)
        self.contactGroupsOwnedByContact = try values.decode(Set<ContactGroupJoinedBackupItem>.self, forKey: .contactGroupsOwned)
        self.trustLevelRaw = try values.decode(String.self, forKey: .trustLevelRaw)
        self.isRevokedAsCompromised = try values.decodeIfPresent(Bool.self, forKey: .isRevokedAsCompromised) ?? false
        self.isForcefullyTrustedByUser = try values.decodeIfPresent(Bool.self, forKey: .isForcefullyTrustedByUser) ?? false
    }
    
    func restoreInstance(within obvContext: ObvContext, associations: inout BackupItemObjectAssociations) throws {
        let contactIdentity = ContactIdentity(backupItem: self, within: obvContext)
        try associations.associate(contactIdentity, to: self)
        _ = try persistedTrustOrigins.map { try $0.restoreInstance(within: obvContext, associations: &associations) }
        try publishedIdentityDetails?.restoreInstance(within: obvContext, associations: &associations)
        _ = try trustedIdentityDetails.restoreInstance(within: obvContext, associations: &associations)
        _ = try contactGroupsOwnedByContact.map { try $0.restoreInstance(within: obvContext, associations: &associations) }
    }

    func restoreRelationships(associations: BackupItemObjectAssociations, within obvContext: ObvContext) throws {
        let contactIdentity: ContactIdentity = try associations.getObject(associatedTo: self, within: obvContext)
        // Restore the relationships of this instance
        let contactGroupsOwned: Set<ContactGroupJoined> = Set(try self.contactGroupsOwnedByContact.map({ try associations.getObject(associatedTo: $0, within: obvContext) }))
        let persistedTrustOrigins: Set<PersistedTrustOrigin> = Set(try self.persistedTrustOrigins.map({ try associations.getObject(associatedTo: $0, within: obvContext) }))
        let publishedIdentityDetails: ContactIdentityDetailsPublished? = try associations.getObjectIfPresent(associatedTo: self.publishedIdentityDetails, within: obvContext)
        let trustedIdentityDetails: ContactIdentityDetailsTrusted = try associations.getObject(associatedTo: self.trustedIdentityDetails, within: obvContext)
        contactIdentity.restoreRelationships(contactGroupsOwned: contactGroupsOwned,
                                             persistedTrustOrigins: persistedTrustOrigins,
                                             publishedIdentityDetails: publishedIdentityDetails,
                                             trustedIdentityDetails: trustedIdentityDetails)
        // Restore the relationships with this instance relationships
        _ = try self.persistedTrustOrigins.map({ try $0.restoreRelationships(associations: associations, within: obvContext) })
        try self.publishedIdentityDetails?.restoreRelationships(associations: associations, within: obvContext)
        try self.trustedIdentityDetails.restoreRelationships(associations: associations, within: obvContext)
        _ = try self.contactGroupsOwnedByContact.map({ try $0.restoreRelationships(associations: associations, within: obvContext) })
    }

}
