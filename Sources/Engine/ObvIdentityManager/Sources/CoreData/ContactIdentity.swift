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
import os.log
import OlvidUtils
import ObvCrypto
import ObvTypes
import ObvEncoder
import ObvMetaManager
import ObvJWS


@objc(ContactIdentity)
final class ContactIdentity: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "ContactIdentity"
        
    // MARK: Attributes
    
    @NSManaged private(set) var isCertifiedByOwnKeycloak: Bool
    @NSManaged private(set) var isForcefullyTrustedByUser: Bool
    @NSManaged private(set) var isRevokedAsCompromised: Bool
    @NSManaged private(set) var ownedIdentityIdentity: Data // Unique (together with `rawIdentity`)
    @NSManaged private var rawDateOfLastBootstrappedContactDeviceDiscovery: Date?
    @NSManaged private var rawIdentity: Data // Unique (together with `ownedIdentityIdentity`)
    @NSManaged private var rawOneToOneStatus: NSNumber? // Expected to be non-nil
    @NSManaged private var trustLevelRaw: String
    @NSManaged private var rawWasContactRecentlyOnline: NSNumber? // Expected to be non-nil
    @NSManaged private var serverTimestampOfLastContactDiscovery: Date? // May be nil
        
    // MARK: Relationships
        
    private(set) var contactGroups: Set<ContactGroup> {
        get {
            let res = kvoSafePrimitiveValue(forKey: Predicate.Key.contactGroups.rawValue) as! Set<ContactGroup>
            return Set(res.map { $0.delegateManager = delegateManager; $0.obvContext = self.obvContext; return $0 })
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: Predicate.Key.contactGroups.rawValue)
        }
    }
    private var contactGroupsOwned: Set<ContactGroupJoined> {
        get {
            let res = kvoSafePrimitiveValue(forKey: Predicate.Key.contactGroupsOwned.rawValue) as! Set<ContactGroupJoined>
            return Set(res.map { $0.delegateManager = delegateManager; $0.obvContext = self.obvContext; return $0 })
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: Predicate.Key.contactGroupsOwned.rawValue)
        }
    }
    private(set) var devices: Set<ContactDevice> {
        get {
            let res = kvoSafePrimitiveValue(forKey: Predicate.Key.devices.rawValue) as! Set<ContactDevice>
            return Set(res.map { $0.delegateManager = delegateManager; $0.obvContext = self.obvContext; return $0 })
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: Predicate.Key.devices.rawValue)
        }
    }
    private(set) var groupMemberships: Set<ContactGroupV2Member> {
        get {
            let res = kvoSafePrimitiveValue(forKey: Predicate.Key.groupMemberships.rawValue) as! Set<ContactGroupV2Member>
            return Set(res.map { $0.obvContext = self.obvContext; return $0 })
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: Predicate.Key.groupMemberships.rawValue)
        }
    }
    
    // Unique (together with `cryptoIdentity`)
    private(set) var ownedIdentity: OwnedIdentity? {
        get {
            guard let res = kvoSafePrimitiveValue(forKey: Predicate.Key.ownedIdentity.rawValue) as? OwnedIdentity else { return nil }
            res.delegateManager = delegateManager
            res.obvContext = self.obvContext
            return res
        }
        set {
            guard let newValue else { assertionFailure(); return }
            self.ownedIdentityIdentity = newValue.cryptoIdentity.getIdentity()
            kvoSafeSetPrimitiveValue(newValue, forKey: Predicate.Key.ownedIdentity.rawValue)
        }
    }
    
    private(set) var persistedTrustOrigins: Set<PersistedTrustOrigin> {
        get {
            let items = kvoSafePrimitiveValue(forKey: Predicate.Key.persistedTrustOrigins.rawValue) as! Set<PersistedTrustOrigin>
            return Set(items.map { $0.obvContext = self.obvContext; return $0 })
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: Predicate.Key.persistedTrustOrigins.rawValue)
        }
    }
    
    private(set) var publishedIdentityDetails: ContactIdentityDetailsPublished? {
        get {
            let res = kvoSafePrimitiveValue(forKey: Predicate.Key.publishedIdentityDetails.rawValue) as! ContactIdentityDetailsPublished?
            res?.delegateManager = delegateManager
            res?.obvContext = self.obvContext
            return res
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: Predicate.Key.publishedIdentityDetails.rawValue)
        }
    }
    
    private(set) var trustedIdentityDetails: ContactIdentityDetailsTrusted {
        get {
            let res = kvoSafePrimitiveValue(forKey: Predicate.Key.trustedIdentityDetails.rawValue) as! ContactIdentityDetailsTrusted
            res.delegateManager = delegateManager
            res.obvContext = self.obvContext
            return res
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: Predicate.Key.trustedIdentityDetails.rawValue)
        }
    }

    // MARK: -
    
    private(set) var wasContactRecentlyOnline: Bool {
        get {
            guard let rawWasContactRecentlyOnline else { assertionFailure(); return true }
            return rawWasContactRecentlyOnline.boolValue
        }
        set {
            let new = NSNumber(booleanLiteral: newValue)
            if self.rawWasContactRecentlyOnline != new {
                self.rawWasContactRecentlyOnline = new
            }
        }
    }
    
    
    private(set) var oneToOneStatus: OneToOneStatusOfContactIdentity {
        get {
            guard let rawValue = rawOneToOneStatus?.intValue,
                  let status = OneToOneStatusOfContactIdentity(rawValue: rawValue) else {
                assertionFailure()
                return .toBeDefined
            }
            return status
        }
        set {
            guard self.rawOneToOneStatus?.intValue != newValue.rawValue else { return }
            // If we change from .toBeDefined to .notOneToOne, we don't notify on didSave
            doNotNotifyOnOneToOneStatusChanged = (rawOneToOneStatus?.intValue == OneToOneStatusOfContactIdentity.toBeDefined.rawValue) && (newValue == .notOneToOne)
            self.rawOneToOneStatus = NSNumber(integerLiteral: newValue.rawValue)
        }
    }
    
    // Expected to be non nil
    var cryptoIdentity: ObvCryptoIdentity? {
        guard let cryptoIdentity = ObvCryptoIdentity(from: rawIdentity) else { assertionFailure(); return nil }
        return cryptoIdentity
    }
    
    var identity: Data {
        return rawIdentity
    }

    
    // Expected to be non nil
    var contactIdentifier: ObvContactIdentifier? {
        guard let cryptoIdentity, let ownedCryptoId = ObvCryptoIdentity(from: ownedIdentityIdentity) else { assertionFailure(); return nil }
        return ObvContactIdentifier(contactCryptoIdentity: cryptoIdentity, ownedCryptoIdentity: ownedCryptoId)
    }
    

    var trustOrigins: [TrustOrigin] {
        persistedTrustOrigins.sorted(by: { $0.timestamp > $1.timestamp }).compactMap { $0.trustOrigin }
    }
    
    // The following vars are only used to implement the ContactDeleted notification
    private var ownedIdentityCryptoIdentityOnDeletion: ObvCryptoIdentity?
    private var rawIdentityOnDeletion: Data?
    
    weak var delegateManager: ObvIdentityDelegateManager?
    
    weak var obvContext: ObvContext?

    private var changedKeys = Set<String>()
    private var doNotNotifyOnOneToOneStatusChanged = false

    var isRevokedAsCompromisedAndNotForcefullyTrustedByUser: Bool {
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
    convenience init?(cryptoIdentity: ObvCryptoIdentity, identityCoreDetails: ObvIdentityCoreDetails, trustOrigin: TrustOrigin, ownedIdentity: OwnedIdentity, isKnownToBeOneToOne: Bool, delegateManager: ObvIdentityDelegateManager) {
        
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
        self.rawIdentity = cryptoIdentity.getIdentity()
        self.oneToOneStatus = isKnownToBeOneToOne ? .oneToOne : .toBeDefined
        self.rawWasContactRecentlyOnline = NSNumber(booleanLiteral: true)
        self.serverTimestampOfLastContactDiscovery = nil
        
        // Simple relationships
        self.contactGroups = Set<ContactGroup>()
        self.devices = Set<ContactDevice>()
        self.groupMemberships = Set<ContactGroupV2Member>()
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
    fileprivate convenience init(backupItem: ContactIdentityBackupItem, ownedIdentityIdentity: Data, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: ContactIdentity.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.rawIdentity = backupItem.rawIdentity
        self.trustLevelRaw = backupItem.trustLevelRaw
        self.isRevokedAsCompromised = backupItem.isRevokedAsCompromised
        self.isForcefullyTrustedByUser = backupItem.isForcefullyTrustedByUser
        self.rawWasContactRecentlyOnline = NSNumber(booleanLiteral: true)
        self.serverTimestampOfLastContactDiscovery = nil
        if let isOneToOne = backupItem.isOneToOne {
            self.oneToOneStatus = isOneToOne ? .oneToOne : .notOneToOne
        } else {
            self.oneToOneStatus = .toBeDefined
        }
        self.ownedIdentityIdentity = ownedIdentityIdentity
    }
    
    
    /// Used when restoring a backup
    fileprivate func restoreRelationships(contactGroupsOwned: Set<ContactGroupJoined>, persistedTrustOrigins: Set<PersistedTrustOrigin>, publishedIdentityDetails: ContactIdentityDetailsPublished?, trustedIdentityDetails: ContactIdentityDetailsTrusted) {
        /* contactGroups is set within ContactGroup */
        self.contactGroupsOwned = contactGroupsOwned
        self.devices = Set<ContactDevice>()
        /* ownedIdentity is set within OwnedIdentity */
        self.persistedTrustOrigins = persistedTrustOrigins
        self.publishedIdentityDetails = publishedIdentityDetails
        self.trustedIdentityDetails = trustedIdentityDetails
    }

    
    /// Used when restoring a snapshot
    fileprivate func restoreRelationships(persistedTrustOrigins: Set<PersistedTrustOrigin>, publishedIdentityDetails: ContactIdentityDetailsPublished?, trustedIdentityDetails: ContactIdentityDetailsTrusted) {
        /* contactGroups is set within ContactGroup */
        /* contactGroupsOwned is set within ContactGroup */
        self.devices = Set<ContactDevice>()
        /* ownedIdentity is set within OwnedIdentity */
        self.persistedTrustOrigins = persistedTrustOrigins
        self.publishedIdentityDetails = publishedIdentityDetails
        self.trustedIdentityDetails = trustedIdentityDetails
    }

    private var isInsertedWhileRestoringSyncSnapshot = false
    
    /// Used *exclusively* during a snapshot restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(snapshotNode: ContactIdentitySyncSnapshotNode, contactCryptoId: ObvCryptoIdentity, ownedIdentityIdentity: Data, within obvContext: ObvContext) throws {
        let entityDescription = NSEntityDescription.entity(forEntityName: ContactIdentity.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.rawIdentity = contactCryptoId.getIdentity()
        self.trustLevelRaw = snapshotNode.trustLevelRaw ?? TrustLevel.zero.rawValue
        self.isRevokedAsCompromised = snapshotNode.isRevokedAsCompromised ?? false
        self.isForcefullyTrustedByUser = snapshotNode.isForcefullyTrustedByUser ?? false
        self.rawWasContactRecentlyOnline = NSNumber(booleanLiteral: true)
        self.serverTimestampOfLastContactDiscovery = nil
        if let isOneToOne = snapshotNode.isOneToOne {
            self.oneToOneStatus = isOneToOne ? .oneToOne : .notOneToOne
        } else {
            self.oneToOneStatus = .toBeDefined
        }
        self.ownedIdentityIdentity = ownedIdentityIdentity
        self.isCertifiedByOwnKeycloak = false // This is updated later, in the restoreRelationships(associations:prng:customDeviceName:delegateManager:within:) of OwnedIdentitySyncSnapshotNode
        
        // Prevents the sending of notifications
        isInsertedWhileRestoringSyncSnapshot = true
    }


    func delete(delegateManager: ObvIdentityDelegateManager, failIfContactIsPartOfACommonGroup: Bool, within obvContext: ObvContext) throws {
        self.delegateManager = delegateManager
        guard let ownedIdentity else {
            throw ObvError.associatedOwnedIdentityIsNil
        }
        guard let cryptoIdentity = self.cryptoIdentity else { assertionFailure(); throw ObvError.couldNotDecodeIdentity }
        if failIfContactIsPartOfACommonGroup {
            let numberOfCommonGroupV2 = try ContactGroupV2.countAllContactGroupV2WithContact(ownedIdentity: ownedIdentity.cryptoIdentity, contactIdentity: cryptoIdentity, delegateManager: delegateManager, within: obvContext)
            guard numberOfCommonGroupV2 == 0 else {
                assertionFailure()
                throw ObvError.cannotDeleteContactIfSheIsPartOfGroupV2
            }
            guard contactGroups.isEmpty && contactGroupsOwned.isEmpty else {
                assertionFailure()
                throw ObvError.cannotDeleteContactIfSheIsPartOfGroupV1
            }
        }
        obvContext.delete(self)
    }
    
    func setDateOfLastBootstrappedContactDeviceDiscovery(to newDate: Date) {
        self.rawDateOfLastBootstrappedContactDeviceDiscovery = newDate
    }
    
}


// MARK: Errors

extension ContactIdentity {
    
    enum ObvError: Error {
        case associatedOwnedIdentityIsNil
        case couldNotDecodeIdentity
        case cannotDeleteContactIfSheIsPartOfGroupV1
        case cannotDeleteContactIfSheIsPartOfGroupV2
        case obvContextIsNil
        case couldNotGetIdentityDetails
        case couldNotCreateContactIdentityDetailsPublished
        case publishedIdentityDetailsAreNil
        case couldNotGetTrustedIdentityDetails
        case couldNotGetPublishedIdentityDetails
        case couldNotCreatePersistedTrustOrigin
        case couldNotGetPersistedTrustOriginTrustLevel
        case contactIsRevokedAsCompromisedAndNotForcefullyTrustedByUser
        case delegateManagerIsNil
        case couldNotCreateContactDevice
        case couldNotFindContactDevice
        case couldNotFindContact
    }
    
}


// MARK: - Managing trusted and published details, and photos

extension ContactIdentity {
 
    /// This method is the one to call to update the `isCertifiedByOwnKeycloak` flag. If the contact is indeed managed by the same keycloak than the one of the owned identity,
    /// it also updates the published/trusted details to match the values found in the signed details of the contact. Of course, if our owned identity is not managed or if there are no signed details,
    /// this method only sets the `isCertifiedByOwnKeycloak` flag to `false`.
    func refreshCertifiedByOwnKeycloakAndTrustedDetails(delegateManager: ObvIdentityDelegateManager) throws {

        var newIsCertifiedByOwnKeycloak = false
        defer {
            if self.isCertifiedByOwnKeycloak != newIsCertifiedByOwnKeycloak {
                self.isCertifiedByOwnKeycloak = newIsCertifiedByOwnKeycloak
                isCertifiedByOwnKeycloakWasUpdated(delegateManager: delegateManager)
            }
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactIdentity.entityName)

        guard let obvContext = self.obvContext else { assertionFailure(); throw ObvError.obvContextIsNil }
        guard let cryptoIdentity = self.cryptoIdentity else { assertionFailure(); throw ObvError.couldNotDecodeIdentity }
        
        guard let ownedIdentity else {
            assertionFailure()
            throw ObvError.associatedOwnedIdentityIsNil
        }
        
        guard ownedIdentity.isKeycloakManaged else {
            return
        }

        let details = publishedIdentityDetails ?? trustedIdentityDetails
        guard let identityDetails = details.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory) else {
            throw ObvError.couldNotGetIdentityDetails
        }
        guard let signedUserDetails = identityDetails.coreDetails.signedUserDetails else {
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

        let revocations = try KeycloakRevokedIdentity.get(keycloakServer: ownKeycloakServer, identity: cryptoIdentity)

        do {
            let revocationsCompromised = revocations.filter({ (try? $0.revocationType) == .compromised })
            guard revocationsCompromised.isEmpty else {
                assert(newIsCertifiedByOwnKeycloak == false)
                revokeAsCompromised(delegateManager: delegateManager) // This deletes the devices of the contact
                return
            }
        }
        
        let signedContactUserDetails: SignedObvKeycloakUserDetails
        do {
            signedContactUserDetails = try SignedObvKeycloakUserDetails.verifySignedUserDetails(signedUserDetails, with: ownKeycloakServer.jwks).signedUserDetails
        } catch {
            os_log("The signature on the contact signed details is not valid (this also happens if the server signing key changes). We consider this contact as not managed by our own keycloak,", log: log, type: .info)
            assert(newIsCertifiedByOwnKeycloak == false)
            return
        }
        if let timestampOfSignedContactUserDetails = signedContactUserDetails.timestamp {
            let revocationsLeftCompany = revocations.filter({ (try? $0.revocationType) == .leftCompany && $0.revocationTimestamp > timestampOfSignedContactUserDetails })
            guard revocationsLeftCompany.isEmpty else {
                // The user left the company after the signature of his details --> unmark as certified
                assert(newIsCertifiedByOwnKeycloak == false)
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
        // Note that the local self.isCertifiedByOwnKeycloak variable is potentially modified in the `defer` statement.
        
        newIsCertifiedByOwnKeycloak = true
    }
    
    
    /// Called each time `isCertifiedByOwnKeycloak` is changed.
    private func isCertifiedByOwnKeycloakWasUpdated(delegateManager: ObvIdentityDelegateManager) {

        let logger = Logger(subsystem: delegateManager.logSubsystem, category: "ContactIdentity")

        if isCertifiedByOwnKeycloak {
            
            // The contact just became certified by the same keycloak than the one certifying our own identity
            // We should send a ping to that contact. A notification will be sent in the didSave method for that purpose.
            
            // Add a "keycloak certified" trust origin if there isn't already one
            
            if let ownKeycloakServerURL = self.ownedIdentity?.keycloakServer?.serverURL {
                let trustOrigin = TrustOrigin.keycloak(timestamp: Date(), keycloakServer: ownKeycloakServerURL)
                do {
                    try addTrustOriginIfTrustWouldBeIncreased(trustOrigin, delegateManager: delegateManager)
                } catch {
                    logger.fault("Could not add Keycloak trust origin: \(error.localizedDescription)")
                    assertionFailure() // In production, continue anyway
                }
            }
            
        } else {
            
            // The contact is not certified anymore. If our own identity is still certified, we must demote this contact from all keycloak groups (move her from members back to pending members)
            
            guard ownedIdentity?.isKeycloakManaged == true else {
                // Since our owned identity is not keycloak certified, there is nothing to do concerning keycloak groups. They will be deleted anyway.
                return
            }
            
            self.groupMemberships
                .compactMap({ $0.contactGroup })
                .filter({ $0.groupIdentifier?.category == .keycloak })
                .forEach { keycloakGroup in
                    guard let cryptoIdentity else { assertionFailure(); return }
                    do {
                        try keycloakGroup.moveOtherMemberToPendingMembersOfKeycloakGroup(otherMemberCryptoIdentity: cryptoIdentity, delegateManager: delegateManager)
                    } catch {
                        assertionFailure(error.localizedDescription)
                    }
                }
        }
        
    }
    
    
    func getSignedUserDetails(identityPhotosDirectory: URL) throws -> SignedObvKeycloakUserDetails? {
        guard isRevokedAsCompromisedAndNotForcefullyTrustedByUser else { return nil }
        let details = publishedIdentityDetails ?? trustedIdentityDetails
        guard let identityDetails = details.getIdentityDetails(identityPhotosDirectory: identityPhotosDirectory) else {
            throw ObvError.couldNotGetIdentityDetails
        }
        guard let ownedIdentity else {
            throw ObvError.associatedOwnedIdentityIsNil
        }
        guard let signedUserDetails = identityDetails.coreDetails.signedUserDetails else {
            return nil
        }
        guard let ownKeycloakServer = ownedIdentity.keycloakServer else {
            return nil
        }
        let signedContactUserDetails = try SignedObvKeycloakUserDetails.verifySignedUserDetails(signedUserDetails, with: ownKeycloakServer.jwks).signedUserDetails
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
        
        guard let obvContext = self.obvContext else { assertionFailure(); throw ObvError.obvContextIsNil }
        
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
            guard ContactIdentityDetailsPublished(contactIdentity: self, contactIdentityDetailsElements: newContactIdentityDetailsElements, delegateManager: delegateManager) != nil else { throw ObvError.couldNotCreateContactIdentityDetailsPublished }
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
            throw ObvError.publishedIdentityDetailsAreNil
        }
        
        // If we reach this point, the published details have a higher version than the trusted details. We try to "auto-trust" these published details.
        // We "auto-trust" if the published details are visually identical to the trust ones of the following fields:
        // - first name
        // - last name
        // - profile picture
        
        guard let trustedDetails = trustedIdentityDetails.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory) else {
            throw ObvError.couldNotGetTrustedIdentityDetails
        }
        guard let publishedDetails = publishedIdentityDetails.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory) else {
            throw ObvError.couldNotGetPublishedIdentityDetails
        }
        guard publishedDetails.coreDetails.hasVisuallyIdenticalFirstNameAndLastName(than: trustedDetails.coreDetails) else {
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
        try updateTrustedDetailsWithPublishedDetails(publishedDetails, delegateManager: delegateManager)

    }
    
    
    func revokeAsCompromised(delegateManager: ObvIdentityDelegateManager) {

        guard !self.isRevokedAsCompromised else { return }
        self.isRevokedAsCompromised = true
        
        if !isForcefullyTrustedByUser {
            self.devices.forEach { contactDevice in
                let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactIdentity.entityName)
                do {
                    try contactDevice.deleteContactDevice() // This will eventually delete the secure channels
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
        if !isRevokedAsCompromisedAndNotForcefullyTrustedByUser {
            self.devices.forEach { contactDevice in
                let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactIdentity.entityName)
                do {
                    try contactDevice.deleteContactDevice() // This will eventually delete the secure channels
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
    
    func addTrustOriginIfTrustWouldBeIncreased(_ trustOrigin: TrustOrigin, delegateManager: ObvIdentityDelegateManager) throws {
        let existingTrustOrigins = self.trustOrigins
        guard trustOrigin.addsTrustWhenAddedToAll(otherTrustOrigins: existingTrustOrigins) else {
            // Since the new trust origin does not increase trust, we do no add it (it would certainly duplicate one that already exists)
            return
        }
        guard let persistedTrustOrigin = PersistedTrustOrigin(trustOrigin: trustOrigin, contact: self, delegateManager: delegateManager) else {
            assertionFailure()
            throw ObvError.couldNotCreatePersistedTrustOrigin
        }
        guard let trustOriginTrustLevel = persistedTrustOrigin.trustLevel else {
            assertionFailure()
            throw ObvError.couldNotGetPersistedTrustOriginTrustLevel
        }
        if self.trustLevel < trustOriginTrustLevel {
            self.trustLevelRaw = trustOriginTrustLevel.rawValue
        }
    }

}

// MARK: - ContactDevice management

extension ContactIdentity {
    
    func addIfNotExistDeviceWith(uid: UID, createdDuringChannelCreation: Bool, flowId: FlowIdentifier) throws {
        guard self.isRevokedAsCompromisedAndNotForcefullyTrustedByUser else {
            assertionFailure()
            throw ObvError.contactIsRevokedAsCompromisedAndNotForcefullyTrustedByUser
        }
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: "ContactIdentity")
            os_log("The delegate manager is not set (3)", log: log, type: .fault)
            throw ObvError.delegateManagerIsNil
        }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: "ContactIdentity")
        let existingDeviceUids = devices.map { $0.uid }
        if !existingDeviceUids.contains(uid) {
            guard ContactDevice(uid: uid, contactIdentity: self, createdDuringChannelCreation: createdDuringChannelCreation, flowId: flowId, delegateManager: delegateManager) != nil else {
                os_log("Could not add a contact device", log: log, type: .fault)
                throw ObvError.couldNotCreateContactDevice
            }
        }
    }
    
    
    private func removeIfExistsDeviceWith(uid: UID, flowId: FlowIdentifier) throws {
        guard let obvContext = self.obvContext else {
            let log = OSLog(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: "ContactIdentity")
            os_log("The obvContext is not set in removeIfExistsDeviceWith", log: log, type: .fault)
            throw ObvError.obvContextIsNil
        }
        for device in devices {
            guard device.uid == uid else { continue }
            obvContext.delete(device)
        }
    }
    
    
    private func updateIfExistsDeviceWith(with deviceOnServer: ContactDeviceDiscoveryResult.Device, serverCurrentTimestamp: Date, log: OSLog) throws {
        guard let device = self.devices.first(where: { $0.uid == deviceOnServer.uid }) else { assertionFailure(); return }
        if let deviceBlobOnServer = deviceOnServer.deviceBlobOnServer {
            guard let cryptoIdentity else { assertionFailure(); return }
            try deviceBlobOnServer.checkChallengeResponse(for: cryptoIdentity)
        }
        try device.updateWithContactDeviceDiscoveryResultDevice(deviceOnServer, serverCurrentTimestamp: serverCurrentTimestamp, log: log)
    }
    
    
    func processContactDeviceDiscoveryResult(_ contactDeviceDiscoveryResult: ContactDeviceDiscoveryResult, log: OSLog, flowId: FlowIdentifier) throws {
        
        if self.wasContactRecentlyOnline != contactDeviceDiscoveryResult.wasContactRecentlyOnline {
            self.wasContactRecentlyOnline = contactDeviceDiscoveryResult.wasContactRecentlyOnline
        }
        
        if self.serverTimestampOfLastContactDiscovery != contactDeviceDiscoveryResult.serverCurrentTimestamp {
            self.serverTimestampOfLastContactDiscovery = contactDeviceDiscoveryResult.serverCurrentTimestamp
        }
        
        // Delete, create, and update devices
        
        let knownDeviceUIDs = Set(self.devices.map(\.uid))
        let correctDeviceUIDs = Set(contactDeviceDiscoveryResult.devices.map(\.uid))
        let deviceUIDsToRemove = knownDeviceUIDs.subtracting(correctDeviceUIDs)
        let deviceUIDsToAdd = correctDeviceUIDs.subtracting(knownDeviceUIDs)
        
        try deviceUIDsToRemove.forEach { try removeIfExistsDeviceWith(uid: $0, flowId: flowId) }
        try deviceUIDsToAdd.forEach { try addIfNotExistDeviceWith(uid: $0, createdDuringChannelCreation: false, flowId: flowId) }
        try contactDeviceDiscoveryResult.devices.forEach {
            try updateIfExistsDeviceWith(with: $0, serverCurrentTimestamp: contactDeviceDiscoveryResult.serverCurrentTimestamp, log: log)
        }
        
    }
    
    
    func markAsRecentlyOnline() {
        if !self.wasContactRecentlyOnline {
            self.wasContactRecentlyOnline = true
        }
    }
    
}

// MARK: - Latest Channel Creation Ping Timestamp for contact devices

extension ContactIdentity {
    
    func getLatestChannelCreationPingTimestampOfContactDevice(withUID uid: UID) throws -> Date? {
        guard let device = self.devices.first(where: { $0.uid == uid }) else {
            assertionFailure()
            throw ObvError.couldNotFindContactDevice
        }
        return device.latestChannelCreationPingTimestamp
    }
    
    
    func setLatestChannelCreationPingTimestampOfContactDevice(withUID uid: UID, to date: Date) throws {
        guard let device = self.devices.first(where: { $0.uid == uid }) else { return }
        device.setLatestChannelCreationPingTimestamp(to: date)
    }
    
}


// MARK: - Capabilities

extension ContactIdentity {
    
    func setRawCapabilitiesOfDeviceWithUID(_ deviceUID: UID, newRawCapabilities: Set<String>) throws {
        guard let device = self.devices.first(where: { $0.uid == deviceUID }) else {
            throw ObvError.couldNotFindContactDevice
        }
        device.setRawCapabilities(newRawCapabilities: newRawCapabilities)
        // Before v0.11.1, we used to call setIsOneToOne(to: true) for contacts not having the oneToneContacts capability, for legacy reasons. We don't do that anymore.
    }
    
    
    /// Returns `nil` if the contact capabilities are not known yet (i.e., when no contact device has capabilities)
    var allCapabilities: Set<ObvCapability>? {
        let capabilitiesOfDevicesWithKnownCapabilities = devices.compactMap({ $0.allCapabilities })
        guard !capabilitiesOfDevicesWithKnownCapabilities.isEmpty else { return nil }
        var capabilities = Set<ObvCapability>()
        ObvCapability.allCases.forEach { capability in
            if capabilitiesOfDevicesWithKnownCapabilities.allSatisfy({ $0.contains(capability) }) {
                capabilities.insert(capability)
            }
        }
        assert(capabilities.contains(.oneToOneContacts))
        return capabilities
    }
    
}


// MARK: - Capabilities

extension ContactIdentity {
    
    func setIsOneToOne(to newIsOneToOne: Bool, reasonToLog: String) {
        let newOneToOneStatus: OneToOneStatusOfContactIdentity = newIsOneToOne ? .oneToOne : .notOneToOne
        if self.oneToOneStatus != newOneToOneStatus {
            //ObvDisplayableLogs.shared.log("[🫂][ContactIdentity] Setting OneToOneStatus to \(newOneToOneStatus): \(reasonToLog)")
            self.oneToOneStatus = newOneToOneStatus
        }
    }
    
}


// MARK: - Syncing between owned devices

extension ContactIdentity {
    
    func processTrustContactDetailsSyncAtom(serializedIdentityDetailsElements: Data, delegateManager: ObvIdentityDelegateManager) throws {
        let identityDetailsElements = try IdentityDetailsElements(serializedIdentityDetailsElements)
        guard let publishedIdentityDetails else {
            // No published details to trust, nothing left to do
            return
        }
        // If the local published details for this contact do match the details the user decided to trust on another owned device,
        // we trust these published now.
        // First first construct a IdentityDetailsElements struct on the basis of the local, published details of the contact
        guard let localPublishedIdentityDetailsElements = publishedIdentityDetails.getIdentityDetailsElements(identityPhotosDirectory: delegateManager.identityPhotosDirectory) else {
            assertionFailure()
            throw ObvError.couldNotGetPublishedIdentityDetails
        }
        // We can compare the IdentityDetailsElements that were trusted on the other owned device with the published IdentityDetailsElements on this device
        // If they are identical, we can trust the local published details
        if identityDetailsElements.fieldsAreTheSameButVersionAndSignedDetailsAreNotConsidered(than: localPublishedIdentityDetailsElements) {
            guard let obvIdentityDetails = publishedIdentityDetails.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory) else {
                assertionFailure()
                throw ObvError.couldNotGetPublishedIdentityDetails
            }
            try self.updateTrustedDetailsWithPublishedDetails(obvIdentityDetails, delegateManager: delegateManager)
        }
    }
    
}


// MARK: - Using pre-keys for encryption

extension ContactIdentity {
    
    func wrap(_ messageKey: any AuthenticatedEncryptionKey, forContactDeviceUID uid: UID, with ownedPrivateKeyForAuthentication: any PrivateKeyForAuthentication, and ownedPublicKeyForAuthentication: any PublicKeyForAuthentication, prng: any PRNGService) throws -> EncryptedData? {
        
        guard let contactDevice = self.devices.first(where: { $0.uid == uid }) else {
            assertionFailure()
            throw ObvError.couldNotFindContactDevice
        }
        
        let wrappedMessageKey = try contactDevice.wrap(messageKey,
                                                       with: ownedPrivateKeyForAuthentication,
                                                       and: ownedPublicKeyForAuthentication,
                                                       prng: prng)
        
        return wrappedMessageKey
        
    }
    
}


// MARK: - Convenience DB getters

extension ContactIdentity {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ContactIdentity> {
        return NSFetchRequest<ContactIdentity>(entityName: ContactIdentity.entityName)
    }
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case isCertifiedByOwnKeycloak = "isCertifiedByOwnKeycloak"
            case isForcefullyTrustedByUser = "isForcefullyTrustedByUser"
            case rawOneToOneStatus = "rawOneToOneStatus"
            case isRevokedAsCompromised = "isRevokedAsCompromised"
            case ownedIdentityIdentity = "ownedIdentityIdentity"
            case rawDateOfLastBootstrappedContactDeviceDiscovery = "rawDateOfLastBootstrappedContactDeviceDiscovery"
            case rawIdentity = "rawIdentity"
            case serverTimestampOfLastContactDiscovery = "serverTimestampOfLastContactDiscovery"
            case trustLevelRaw = "trustLevelRaw"
            // Relationships
            case contactGroups = "contactGroups"
            case contactGroupsOwned = "contactGroupsOwned"
            case devices = "devices"
            case groupMemberships = "groupMemberships"
            case ownedIdentity = "ownedIdentity"
            case persistedTrustOrigins = "persistedTrustOrigins"
            case publishedIdentityDetails = "publishedIdentityDetails"
            case trustedIdentityDetails = "trustedIdentityDetails"
        }
        fileprivate static func withContactCryptoIdentity(_ contactIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawIdentity, EqualToData: contactIdentity.getIdentity())
        }
        fileprivate static func withOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.ownedIdentityIdentity, EqualToData: ownedCryptoIdentity.getIdentity())
        }
        fileprivate static func withOwnedIdentiy(_ ownedIdentity: OwnedIdentity) -> NSPredicate {
            withOwnedCryptoIdentity(ownedIdentity.cryptoIdentity)
        }
        fileprivate static var withoutDevice: NSPredicate {
            NSPredicate(withZeroCountForKey: Key.devices)
        }
        fileprivate static func withServerTimestampOfLastContactDiscovery(earlierThan date: Date) -> NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(withNilValueForKey: Key.serverTimestampOfLastContactDiscovery),
                NSPredicate(Key.serverTimestampOfLastContactDiscovery, earlierThan: date),
            ])
        }
        fileprivate static var withActiveOwnedIdentity: NSPredicate {
            let key = [Key.ownedIdentity.rawValue, OwnedIdentity.Predicate.Key.isActive.rawValue].joined(separator: ".")
            return NSPredicate(key, is: true)
        }
    }
    
    static func getDateOfLastBootstrappedContactDeviceDiscovery(contactIdentity: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws -> Date {
        let request: NSFetchRequest<ContactIdentity> = ContactIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withContactCryptoIdentity(contactIdentity),
            Predicate.withOwnedCryptoIdentity(ownedIdentity),
        ])
        request.fetchLimit = 1
        guard let item = (try context.fetch(request)).first else {
            throw ObvError.couldNotFindContact
        }
        return item.rawDateOfLastBootstrappedContactDeviceDiscovery ?? .distantPast
    }

    static func get(contactIdentity: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity, delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) throws -> ContactIdentity? {
        let request: NSFetchRequest<ContactIdentity> = ContactIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withContactCryptoIdentity(contactIdentity),
            Predicate.withOwnedCryptoIdentity(ownedIdentity),
        ])
        request.fetchLimit = 1
        let item = (try obvContext.fetch(request)).first
        item?.delegateManager = delegateManager
        return item
    }

    static func get(contactIdentity: ObvCryptoIdentity, ownedIdentity: OwnedIdentity, delegateManager: ObvIdentityDelegateManager) throws -> ContactIdentity? {
        guard let obvContext = ownedIdentity.obvContext else { throw ObvIdentityManagerError.contextIsNil }
        let request: NSFetchRequest<ContactIdentity> = ContactIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withContactCryptoIdentity(contactIdentity),
            Predicate.withOwnedCryptoIdentity(ownedIdentity.cryptoIdentity),
        ])
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
    
    static func getCryptoIdentitiesOfContactsWithoutDevice(ownedCryptoId: ObvCryptoIdentity, within context: NSManagedObjectContext) throws -> Set<ObvCryptoIdentity> {
        let request: NSFetchRequest<ContactIdentity> = ContactIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoIdentity(ownedCryptoId),
            Predicate.withoutDevice,
        ])
        request.fetchBatchSize = 500
        let items = try context.fetch(request)
        let contactCryptoIdentities = items.compactMap({ $0.cryptoIdentity })
        return Set(contactCryptoIdentities)
    }

    static func exists(cryptoIdentity: ObvCryptoIdentity, ownedIdentity: OwnedIdentity, within obvContext: ObvContext) throws -> Bool {
        let request: NSFetchRequest<ContactIdentity> = ContactIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withContactCryptoIdentity(cryptoIdentity),
            Predicate.withOwnedIdentiy(ownedIdentity),
        ])
        return try obvContext.count(for: request) != 0
    }
    
    
    static func getContactsOfAllActiveOwnedIdentitiesRequiringContactDeviceDiscovery(within context: NSManagedObjectContext) throws -> Set<ObvContactIdentifier> {
        let request: NSFetchRequest<ContactIdentity> = ContactIdentity.fetchRequest()
        let dateLimit = Date.now.addingTimeInterval(-ObvConstants.contactDeviceDiscoveryTimeInterval)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withActiveOwnedIdentity,
            Predicate.withServerTimestampOfLastContactDiscovery(earlierThan: dateLimit),
        ])
        request.propertiesToFetch = [
            Predicate.Key.rawIdentity.rawValue,
            Predicate.Key.ownedIdentityIdentity.rawValue,
        ]
        request.fetchBatchSize = 500
        let items = try context.fetch(request)
        let contactIdentifiers = items.compactMap({ $0.contactIdentifier })
        return Set(contactIdentifiers)
    }
    
}


// MARK: - Reacting to updates

extension ContactIdentity {
    
    override func prepareForDeletion() {
        super.prepareForDeletion()
        // In case we are actually deleting an owned identity, `ownedIdentity` may be nil at this point.
        guard let managedObjectContext else { assertionFailure(); return }
        guard managedObjectContext.concurrencyType != .mainQueueConcurrencyType else { return }
        if let ownedIdentity {
            ownedIdentityCryptoIdentityOnDeletion = ownedIdentity.cryptoIdentity
        }
        self.rawIdentityOnDeletion = rawIdentity
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
            doNotNotifyOnOneToOneStatusChanged = false
            isInsertedWhileRestoringSyncSnapshot = false
        }
        
        guard !isInsertedWhileRestoringSyncSnapshot else {
            assert(isInserted)
            let log = OSLog.init(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: String(describing: Self.self))
            os_log("Insertion of a ContactIdentity during a snapshot restore --> we don't send any notification", log: log, type: .info)
            return
        }
        
        guard let delegateManager = delegateManager else {
            let log = OSLog.init(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: String(describing: Self.self))
            os_log("The delegate manager is not set (5)", log: log, type: .fault)
            return
        }

        let log = OSLog.init(subsystem: delegateManager.logSubsystem, category: String(describing: Self.self))

        assert(obvContext != nil)
        let flowId = obvContext?.flowId ?? FlowIdentifier()
        
        if isInserted, let ownedIdentity, let cryptoIdentity = self.cryptoIdentity {

            do {
                os_log("Sending a ContactIdentityIsNowTrusted notification", log: log, type: .debug)
                ObvIdentityNotificationNew.contactIdentityIsNowTrusted(contactIdentity: cryptoIdentity, ownedIdentity: ownedIdentity.ownedCryptoIdentity.getObvCryptoIdentity(), flowId: flowId)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
            }
            
            ObvIdentityNotificationNew.contactIdentityOneToOneStatusChanged(
                ownedIdentity: ownedIdentity.cryptoIdentity,
                contactIdentity: cryptoIdentity,
                flowId: flowId)
            .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)

        } else if isDeleted, let ownedIdentityCryptoIdentityOnDeletion, let rawIdentityOnDeletion, let cryptoIdentity = ObvCryptoIdentity(from: rawIdentityOnDeletion) {
                        
            os_log("Sending a ContactWasDeleted notification", log: log, type: .debug)
            ObvIdentityNotificationNew.contactWasDeleted(ownedCryptoIdentity: ownedIdentityCryptoIdentityOnDeletion,
                                                         contactCryptoIdentity: cryptoIdentity)
            .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)

        } else if let ownedIdentity, let cryptoIdentity {
                        
            if !changedKeys.isEmpty {
                
                //ObvDisplayableLogs.shared.log("[ContactIdentity] Will send contactWasUpdatedWithinTheIdentityManager notification as changedKeys = \(changedKeys)")
                
                ObvIdentityNotificationNew.contactWasUpdatedWithinTheIdentityManager(ownedIdentity: ownedIdentity.cryptoIdentity, contactIdentity: cryptoIdentity, flowId: flowId)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)

            }
            
            if changedKeys.contains(Predicate.Key.isForcefullyTrustedByUser.rawValue) || changedKeys.contains(Predicate.Key.isRevokedAsCompromised.rawValue) {
                
                ObvIdentityNotificationNew.contactIsActiveChanged(
                    ownedIdentity: ownedIdentity.cryptoIdentity,
                    contactIdentity: cryptoIdentity,
                    isActive: isRevokedAsCompromisedAndNotForcefullyTrustedByUser,
                    flowId: flowId)
                .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)

            }
            
            if changedKeys.contains(Predicate.Key.isRevokedAsCompromised.rawValue) && self.isRevokedAsCompromised {
                
                ObvIdentityNotificationNew.contactWasRevokedAsCompromised(
                    ownedIdentity: ownedIdentity.cryptoIdentity,
                    contactIdentity: cryptoIdentity,
                    flowId: flowId)
                .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)

            }
            
            if changedKeys.contains(Predicate.Key.rawOneToOneStatus.rawValue) {
                
                if !doNotNotifyOnOneToOneStatusChanged {
                    
                    ObvIdentityNotificationNew.contactIdentityOneToOneStatusChanged(
                        ownedIdentity: ownedIdentity.cryptoIdentity,
                        contactIdentity: cryptoIdentity,
                        flowId: flowId)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
                    
                }

            }
            
            if changedKeys.contains(Predicate.Key.isCertifiedByOwnKeycloak.rawValue) {
                
                ObvIdentityNotificationNew.contactIsCertifiedByOwnKeycloakStatusChanged(
                    ownedIdentity: ownedIdentity.cryptoIdentity,
                    contactIdentity: cryptoIdentity,
                    newIsCertifiedByOwnKeycloak: isCertifiedByOwnKeycloak)
                .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)

            }
            
        }

    }
}


// MARK: - For Backup purposes

extension ContactIdentity {
    
    var backupItem: ContactIdentityBackupItem {
        return ContactIdentityBackupItem(rawIdentity: rawIdentity,
                                         persistedTrustOrigins: persistedTrustOrigins,
                                         publishedIdentityDetails: publishedIdentityDetails,
                                         trustedIdentityDetails: trustedIdentityDetails,
                                         contactGroupsOwned: contactGroupsOwned,
                                         trustLevelRaw: trustLevelRaw,
                                         isRevokedAsCompromised: isRevokedAsCompromised,
                                         isForcefullyTrustedByUser: isForcefullyTrustedByUser,
                                         oneToOneStatus: oneToOneStatus)
    }

}


struct ContactIdentityBackupItem: Codable, Hashable {
    
    fileprivate let rawIdentity: Data
    fileprivate let persistedTrustOrigins: Set<PersistedTrustOriginBackupItem>
    fileprivate let publishedIdentityDetails: ContactIdentityDetailsPublishedBackupItem?
    fileprivate let trustedIdentityDetails: ContactIdentityDetailsTrustedBackupItem
    let contactGroupsOwnedByContact: Set<ContactGroupJoinedBackupItem>
    fileprivate let trustLevelRaw: String
    fileprivate let isRevokedAsCompromised: Bool
    fileprivate let isForcefullyTrustedByUser: Bool
    fileprivate let isOneToOne: Bool?

    private static let errorDomain = String(describing: ContactIdentityBackupItem.self)

    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    fileprivate init(rawIdentity: Data, persistedTrustOrigins: Set<PersistedTrustOrigin>, publishedIdentityDetails: ContactIdentityDetailsPublished?, trustedIdentityDetails: ContactIdentityDetailsTrusted, contactGroupsOwned: Set<ContactGroupJoined>, trustLevelRaw: String, isRevokedAsCompromised: Bool, isForcefullyTrustedByUser: Bool, oneToOneStatus: OneToOneStatusOfContactIdentity) {
        self.rawIdentity = rawIdentity
        self.persistedTrustOrigins = Set(persistedTrustOrigins.map { $0.backupItem })
        self.publishedIdentityDetails = publishedIdentityDetails?.backupItem
        self.trustedIdentityDetails = trustedIdentityDetails.backupItem
        self.contactGroupsOwnedByContact = Set(contactGroupsOwned.map { $0.backupItem })
        self.trustLevelRaw = trustLevelRaw
        self.isRevokedAsCompromised = isRevokedAsCompromised
        self.isForcefullyTrustedByUser = isForcefullyTrustedByUser
        switch oneToOneStatus {
        case .oneToOne:
            self.isOneToOne = true
        case .notOneToOne:
            self.isOneToOne = false
        case .toBeDefined:
            self.isOneToOne = nil
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case rawIdentity = "contact_identity"
        case persistedTrustOrigins = "trust_origins"
        case publishedIdentityDetails = "published_details"
        case trustedIdentityDetails = "trusted_details"
        case contactGroupsOwned = "contact_groups" // Group owned by this contact, joined by the associated owned identity
        case trustLevelRaw = "trust_level"
        case isRevokedAsCompromised = "revoked"
        case isForcefullyTrustedByUser = "forcefully_trusted"
        case isOneToOne = "one_to_one"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawIdentity, forKey: .rawIdentity)
        try container.encode(persistedTrustOrigins, forKey: .persistedTrustOrigins)
        try container.encodeIfPresent(publishedIdentityDetails, forKey: .publishedIdentityDetails)
        try container.encode(trustedIdentityDetails, forKey: .trustedIdentityDetails)
        try container.encode(contactGroupsOwnedByContact, forKey: .contactGroupsOwned)
        try container.encode(trustLevelRaw, forKey: .trustLevelRaw)
        try container.encode(isRevokedAsCompromised, forKey: .isRevokedAsCompromised)
        try container.encode(isForcefullyTrustedByUser, forKey: .isForcefullyTrustedByUser)
        try container.encodeIfPresent(isOneToOne, forKey: .isOneToOne)
    }
 
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.rawIdentity = try values.decode(Data.self, forKey: .rawIdentity)
        self.persistedTrustOrigins = try values.decode(Set<PersistedTrustOriginBackupItem>.self, forKey: .persistedTrustOrigins)
        self.publishedIdentityDetails = try values.decodeIfPresent(ContactIdentityDetailsPublishedBackupItem.self, forKey: .publishedIdentityDetails)
        self.trustedIdentityDetails = try values.decode(ContactIdentityDetailsTrustedBackupItem.self, forKey: .trustedIdentityDetails)
        self.contactGroupsOwnedByContact = try values.decode(Set<ContactGroupJoinedBackupItem>.self, forKey: .contactGroupsOwned)
        self.trustLevelRaw = try values.decode(String.self, forKey: .trustLevelRaw)
        self.isRevokedAsCompromised = try values.decodeIfPresent(Bool.self, forKey: .isRevokedAsCompromised) ?? false
        self.isForcefullyTrustedByUser = try values.decodeIfPresent(Bool.self, forKey: .isForcefullyTrustedByUser) ?? false
        self.isOneToOne = try values.decodeIfPresent(Bool.self, forKey: .isOneToOne)
    }
    
    func restoreInstance(within obvContext: ObvContext, ownedIdentityIdentity: Data, associations: inout BackupItemObjectAssociations) throws {
        let contactIdentity = ContactIdentity(backupItem: self, ownedIdentityIdentity: ownedIdentityIdentity, within: obvContext)
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


// MARK: - For Snapshot purposes

extension ContactIdentity {
    
    var syncSnapshot: ContactIdentitySyncSnapshotNode {
        return ContactIdentitySyncSnapshotNode(
            persistedTrustOrigins: persistedTrustOrigins,
            publishedIdentityDetails: publishedIdentityDetails,
            trustedIdentityDetails: trustedIdentityDetails,
            trustLevelRaw: trustLevelRaw,
            isRevokedAsCompromised: isRevokedAsCompromised,
            isForcefullyTrustedByUser: isForcefullyTrustedByUser,
            oneToOneStatus: oneToOneStatus)
    }

}



struct ContactIdentitySyncSnapshotNode: ObvSyncSnapshotNode {
    
    private let domain: Set<CodingKeys>
    private let trustedIdentityDetails: ContactIdentityDetailsTrustedSyncSnapShotNode?
    private let publishedIdentityDetails: ContactIdentityDetailsPublishedSyncSnapshotNode?
    private let persistedTrustOrigins: Set<PersistedTrustOriginSyncSnapshotItem>
    fileprivate let isOneToOne: Bool?
    fileprivate let isRevokedAsCompromised: Bool?
    fileprivate let isForcefullyTrustedByUser: Bool?
    fileprivate let trustLevelRaw: String? // only used for backup/transfer, not taken into account when comparing for synchronization

    let id = Self.generateIdentifier()

    private static let defaultDomain = Set(CodingKeys.allCases.filter({ $0 != .domain }))

    
    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        case trustedIdentityDetails = "trusted_details"
        case publishedIdentityDetails = "published_details"
        case isOneToOne = "one_to_one"
        case isRevokedAsCompromised = "revoked"
        case isForcefullyTrustedByUser = "forcefully_trusted"
        case trustLevelRaw = "trust_level"
        case persistedTrustOrigins = "trust_origins"
        case domain = "domain"
    }

    
    fileprivate init(persistedTrustOrigins: Set<PersistedTrustOrigin>, publishedIdentityDetails: ContactIdentityDetailsPublished?, trustedIdentityDetails: ContactIdentityDetailsTrusted, trustLevelRaw: String, isRevokedAsCompromised: Bool, isForcefullyTrustedByUser: Bool, oneToOneStatus: OneToOneStatusOfContactIdentity) {
        self.trustedIdentityDetails = trustedIdentityDetails.snapshotNode
        self.publishedIdentityDetails = publishedIdentityDetails?.snapshotNode
        self.persistedTrustOrigins = Set(persistedTrustOrigins.map { $0.snapshotItem })
        self.trustLevelRaw = trustLevelRaw
        self.isRevokedAsCompromised = isRevokedAsCompromised ? true : nil
        self.isForcefullyTrustedByUser = isForcefullyTrustedByUser ? true : nil
        switch oneToOneStatus {
        case .oneToOne:
            self.isOneToOne = true
        case .notOneToOne:
            self.isOneToOne = false
        case .toBeDefined:
            self.isOneToOne = nil
        }
        self.domain = Self.defaultDomain
    }

    
    // Synthesized implementation of encode(to encoder: Encoder)
    

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rawKeys = try values.decode(Set<String>.self, forKey: .domain)
        self.domain = Set(rawKeys.compactMap({ CodingKeys(rawValue: $0) }))
        self.trustedIdentityDetails = try values.decodeIfPresent(ContactIdentityDetailsTrustedSyncSnapShotNode.self, forKey: .trustedIdentityDetails)
        self.publishedIdentityDetails = try values.decodeIfPresent(ContactIdentityDetailsPublishedSyncSnapshotNode.self, forKey: .publishedIdentityDetails)
        self.persistedTrustOrigins = try values.decodeIfPresent(Set<PersistedTrustOriginSyncSnapshotItem>.self, forKey: .persistedTrustOrigins) ?? Set([])
        self.isOneToOne = try values.decodeIfPresent(Bool.self, forKey: .isOneToOne)
        self.isRevokedAsCompromised = try values.decodeIfPresent(Bool.self, forKey: .isRevokedAsCompromised)
        self.isForcefullyTrustedByUser = try values.decodeIfPresent(Bool.self, forKey: .isForcefullyTrustedByUser)
        self.trustLevelRaw = try values.decodeIfPresent(String.self, forKey: .trustLevelRaw)
    }
    
    
    func restoreInstance(within obvContext: ObvContext, contactCryptoId: ObvCryptoIdentity, ownedIdentityIdentity: Data, associations: inout SnapshotNodeManagedObjectAssociations) throws {

        guard domain.contains(.trustedIdentityDetails) else {
            throw ObvError.tryingToRestoreIncompleteSnapshot
        }
        
        let contactIdentity = try ContactIdentity(snapshotNode: self, contactCryptoId: contactCryptoId, ownedIdentityIdentity: ownedIdentityIdentity, within: obvContext)
        try associations.associate(contactIdentity, to: self)

        if domain.contains(.persistedTrustOrigins) {
            try persistedTrustOrigins.forEach { trustOriginSnapshotItem in
                try trustOriginSnapshotItem.restoreInstance(within: obvContext, associations: &associations)
            }
        }

        if domain.contains(.publishedIdentityDetails) {
            try publishedIdentityDetails?.restoreInstance(within: obvContext, associations: &associations)
        }

        try trustedIdentityDetails?.restoreInstance(within: obvContext, associations: &associations)
        
    }

    
    func restoreRelationships(associations: SnapshotNodeManagedObjectAssociations, within obvContext: ObvContext) throws {

        let contactIdentity: ContactIdentity = try associations.getObject(associatedTo: self, within: obvContext)

        // Restore the relationships of this instance
        
        let persistedTrustOrigins: Set<PersistedTrustOrigin> = Set(try self.persistedTrustOrigins.map({ try associations.getObject(associatedTo: $0, within: obvContext) }))

        let publishedIdentityDetails: ContactIdentityDetailsPublished? = try associations.getObjectIfPresent(associatedTo: self.publishedIdentityDetails, within: obvContext)

        guard let trustedIdentityDetails else {
            assertionFailure()
            throw ObvError.tryingToRestoreIncompleteSnapshot
        }
        
        let contactIdentityDetailsTrusted: ContactIdentityDetailsTrusted = try associations.getObject(associatedTo: trustedIdentityDetails, within: obvContext)

        contactIdentity.restoreRelationships(persistedTrustOrigins: persistedTrustOrigins,
                                             publishedIdentityDetails: publishedIdentityDetails,
                                             trustedIdentityDetails: contactIdentityDetailsTrusted)


        // Restore the relationships with this instance relationships
        
        try self.persistedTrustOrigins.forEach { try $0.restoreRelationships(associations: associations, within: obvContext) }

        try self.publishedIdentityDetails?.restoreRelationships(associations: associations, within: obvContext)

        try self.trustedIdentityDetails?.restoreRelationships(associations: associations, within: obvContext)

    }

    
    enum ObvError: Error {
        case tryingToRestoreIncompleteSnapshot
    }

}
