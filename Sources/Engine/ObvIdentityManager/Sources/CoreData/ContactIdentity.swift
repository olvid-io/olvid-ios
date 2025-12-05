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
import OlvidUtils
import ObvCrypto
import ObvTypes
import ObvEncoder
import ObvMetaManager
import ObvJWS


@objc(ContactIdentity)
final class ContactIdentity: NSManagedObject {
    
    // MARK: Internal constants
    
    static weak var delegateManager: ObvIdentityDelegateManager?
    private static let entityName = "ContactIdentity"
    private static var logSubsystem: String { delegateManager?.logSubsystem ?? ObvIdentityDelegateManager.defaultLogSubsystem }
    private static var logger: Logger = { Logger(subsystem: ContactIdentity.logSubsystem, category: "ContactIdentity") }()

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
        
    @NSManaged private(set) var contactGroups: Set<ContactGroup>
    @NSManaged private var contactGroupsOwned: Set<ContactGroupJoined>
    @NSManaged private(set) var devices: Set<ContactDevice>
    @NSManaged private(set) var groupMemberships: Set<ContactGroupV2Member>
    
    // Unique (together with `cryptoIdentity`)
    private(set) var ownedIdentity: OwnedIdentity? {
        get {
            return kvoSafePrimitiveValue(forKey: Predicate.Key.ownedIdentity.rawValue) as? OwnedIdentity
        }
        set {
            guard let newValue else { assertionFailure(); return }
            guard let ownedIdentityIdentity = try? newValue.cryptoIdentity.getIdentity() else { assertionFailure(); return }
            self.ownedIdentityIdentity = ownedIdentityIdentity
            kvoSafeSetPrimitiveValue(newValue, forKey: Predicate.Key.ownedIdentity.rawValue)
        }
    }
    
    @NSManaged private(set) var persistedTrustOrigins: Set<PersistedTrustOrigin>
    @NSManaged private(set) var publishedIdentityDetails: ContactIdentityDetailsPublished?
    
    /// Expected to be non-nil
    @NSManaged private(set) var trustedIdentityDetails: ContactIdentityDetailsTrusted?

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
    
    private var changedKeys = Set<String>()
    private var doNotNotifyOnOneToOneStatusChanged = false

    var isNotRevokedAsCompromisedOrIsForcefullyTrustedByUser: Bool {
        isForcefullyTrustedByUser || !isRevokedAsCompromised
    }
    
    // MARK: - Initializer
    
    /// This initializer enforces that there is a unique entry per `cryptoIdentity`, `ownedIdentity` pair.
    ///
    /// - Parameters:
    ///   - cryptoIdentity: The crypto identity of the contact identity to create.
    ///   - identityDetails: The identity details of the contact identity.
    ///   - ownedIdentity: The owned identity for which we add this contact.
    convenience init?(cryptoIdentity: ObvCryptoIdentity, identityCoreDetails: ObvIdentityCoreDetails, trustOrigin: TrustOrigin, ownedIdentity: OwnedIdentity, isKnownToBeOneToOne: Bool) {
        
        guard let context = ownedIdentity.managedObjectContext else {
            assertionFailure()
            return nil
        }
        
        // Integrity check
        do {
            guard try !ContactIdentity.exists(cryptoIdentity: cryptoIdentity, ownedIdentity: ownedIdentity, within: context) else {
                Self.logger.error("Cannot add the same contact identity twice")
                return nil
            }
        } catch let error {
            Self.logger.fault("\(error)")
            return nil
        }
        
        // Create a new entity
        let entityDescription = NSEntityDescription.entity(forEntityName: ContactIdentity.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
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
                                                                         version: -1) else { return nil }
        self.trustedIdentityDetails = trustedIdentityDetails
        self.publishedIdentityDetails = nil
        self.isCertifiedByOwnKeycloak = false // This is updated later
        self.isForcefullyTrustedByUser = false
        self.isRevokedAsCompromised = false
        
        // Attributes and relationships related to Trust Origins and Trust Levels
        guard let persistedTrustOrigin = PersistedTrustOrigin(trustOrigin: trustOrigin, contact: self) else { return nil }
        guard let trustLevel = persistedTrustOrigin.trustLevel else { return nil }
        self.trustLevelRaw = trustLevel.rawValue
        self.persistedTrustOrigins = Set([persistedTrustOrigin])
        
        // Once all is set, we can refresh the keycloak aspects
        do {
            try refreshCertifiedByOwnKeycloakAndTrustedDetails()
        } catch {
            assertionFailure()
        }
    }
    
    
    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(backupItem: ContactIdentityBackupItem, ownedIdentityIdentity: Data, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: ContactIdentity.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
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
    fileprivate convenience init(snapshotNode: ContactIdentitySyncSnapshotNode, contactCryptoId: ObvCryptoIdentity, ownedIdentityIdentity: Data, within context: NSManagedObjectContext) throws {
        let entityDescription = NSEntityDescription.entity(forEntityName: ContactIdentity.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
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


    func delete(failIfContactIsPartOfACommonGroup: Bool, within context: NSManagedObjectContext) throws {
        guard let ownedIdentity else {
            throw ObvError.associatedOwnedIdentityIsNil
        }
        guard let cryptoIdentity = self.cryptoIdentity else { assertionFailure(); throw ObvError.couldNotDecodeIdentity }
        if failIfContactIsPartOfACommonGroup {
            let numberOfCommonGroupV2 = try ContactGroupV2.countAllContactGroupV2WithContact(ownedIdentity: ownedIdentity.cryptoIdentity, contactIdentity: cryptoIdentity, within: context)
            guard numberOfCommonGroupV2 == 0 else {
                assertionFailure()
                throw ObvError.cannotDeleteContactIfSheIsPartOfGroupV2
            }
            guard contactGroups.isEmpty && contactGroupsOwned.isEmpty else {
                assertionFailure()
                throw ObvError.cannotDeleteContactIfSheIsPartOfGroupV1
            }
        }
        context.delete(self)
    }
    
    func setDateOfLastBootstrappedContactDeviceDiscovery(to newDate: Date) {
        self.rawDateOfLastBootstrappedContactDeviceDiscovery = newDate
    }
 
    
    // MARK: - Observers
    
    private static var observersHolder = ObserversHolder()
    
    static func addObvObserver(_ newObserver: ContactIdentityObserver) async {
        await observersHolder.addObserver(newObserver)
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
    func refreshCertifiedByOwnKeycloakAndTrustedDetails() throws {

        var newIsCertifiedByOwnKeycloak = false
        defer {
            if self.isCertifiedByOwnKeycloak != newIsCertifiedByOwnKeycloak {
                self.isCertifiedByOwnKeycloak = newIsCertifiedByOwnKeycloak
                isCertifiedByOwnKeycloakWasUpdated()
            }
        }

        guard let cryptoIdentity = self.cryptoIdentity else { assertionFailure(); throw ObvError.couldNotDecodeIdentity }
        
        guard let ownedIdentity else {
            assertionFailure()
            throw ObvError.associatedOwnedIdentityIsNil
        }
        
        guard ownedIdentity.isKeycloakManaged else {
            return
        }

        guard let details = publishedIdentityDetails ?? trustedIdentityDetails else {
            throw ObvError.couldNotGetTrustedIdentityDetails
        }
        let identityDetails = try details.getIdentityDetails()
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
                revokeAsCompromised() // This deletes the devices of the contact
                return
            }
        }
        
        let signedContactUserDetails: SignedObvKeycloakUserDetails
        do {
            signedContactUserDetails = try SignedObvKeycloakUserDetails.verifySignedUserDetails(signedUserDetails, with: ownKeycloakServer.jwks).signedUserDetails
        } catch {
            Self.logger.info("The signature on the contact signed details is not valid (this also happens if the server signing key changes). We consider this contact as not managed by our own keycloak,")
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
            guard let trustedIdentityDetails else {
                assertionFailure()
                throw ObvError.couldNotGetTrustedIdentityDetails
            }
            try trustedIdentityDetails.updateWithContactIdentityDetailsPublished(publishedIdentityDetails)
            try publishedIdentityDetails.delete()
            self.publishedIdentityDetails = nil
        }
        
        // If necessary, we update the trusted details using the signed details
        guard let trustedIdentityDetails else { throw ObvError.couldNotGetTrustedIdentityDetails }
        try trustedIdentityDetails.update(with: signedContactUserDetails)

        // If we reach this point, the contact is indeed certified by our own keycloak
        // Note that the local self.isCertifiedByOwnKeycloak variable is potentially modified in the `defer` statement.
        
        newIsCertifiedByOwnKeycloak = true
    }
    
    
    /// Called each time `isCertifiedByOwnKeycloak` is changed.
    private func isCertifiedByOwnKeycloakWasUpdated() {

        if isCertifiedByOwnKeycloak {
            
            // The contact just became certified by the same keycloak than the one certifying our own identity
            // We should send a ping to that contact. A notification will be sent in the didSave method for that purpose.
            
            // Add a "keycloak certified" trust origin if there isn't already one
            
            if let ownKeycloakServerURL = self.ownedIdentity?.keycloakServer?.serverURL {
                let trustOrigin = TrustOrigin.keycloak(timestamp: Date(), keycloakServer: ownKeycloakServerURL)
                do {
                    try addTrustOriginIfTrustWouldBeIncreased(trustOrigin)
                } catch {
                    Self.logger.fault("Could not add Keycloak trust origin: \(error.localizedDescription)")
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
                        try keycloakGroup.moveOtherMemberToPendingMembersOfKeycloakGroup(otherMemberCryptoIdentity: cryptoIdentity)
                    } catch {
                        assertionFailure(error.localizedDescription)
                    }
                }
        }
        
    }
    
    
    func getSignedUserDetails() throws -> SignedObvKeycloakUserDetails? {
        guard isNotRevokedAsCompromisedOrIsForcefullyTrustedByUser else { return nil }
        guard let details = publishedIdentityDetails ?? trustedIdentityDetails else {
            throw ObvError.couldNotGetTrustedIdentityDetails
        }
        let identityDetails = try details.getIdentityDetails()
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
    
        
    func updateContactPhoto(with url: URL?, version: Int, within context: NSManagedObjectContext) throws {
        if let publishedIdentityDetails = self.publishedIdentityDetails, publishedIdentityDetails.version == version {
            try publishedIdentityDetails.setContactPhoto(with: url)
        }
        guard let trustedIdentityDetails else { throw ObvError.couldNotGetTrustedIdentityDetails }
        if trustedIdentityDetails.version == version {
            try trustedIdentityDetails.setContactPhoto(with: url)
        }
    }

    
    func updateContactPhoto(withData photoData: Data, version: Int, within context: NSManagedObjectContext) throws {
        if let publishedIdentityDetails = self.publishedIdentityDetails, publishedIdentityDetails.version == version {
            try publishedIdentityDetails.setContactPhoto(data: photoData)
        }
        guard let trustedIdentityDetails else { throw ObvError.couldNotGetTrustedIdentityDetails }
        if trustedIdentityDetails.version == version {
            try trustedIdentityDetails.setContactPhoto(data: photoData)
        }
    }

    
    func updateTrustedDetailsWithPublishedDetails(_ obvIdentityDetails: ObvIdentityDetails) throws {
        
        // We check that the identity details that were passed as a parameter are identical to the current published identity details of this contact
        guard let publishedIdentityDetails = self.publishedIdentityDetails else { assertionFailure(); return }
        guard try publishedIdentityDetails.getIdentityDetails() == obvIdentityDetails else { assertionFailure(); return }
        
        // We do *not* consider the published/trusted version here. We were asked to trust the published details, so we trust them.
        // We can update the trusted details and delete the published details
        
        guard let trustedIdentityDetails else { throw ObvError.couldNotGetTrustedIdentityDetails }
        try trustedIdentityDetails.updateWithContactIdentityDetailsPublished(publishedIdentityDetails)
        try publishedIdentityDetails.delete()

    }
    
    
    func updatePublishedDetailsAndTryToAutoTrustThem(with newContactIdentityDetailsElements: IdentityDetailsElements, allowVersionDowngrade: Bool) throws {
        
        if let currentPublishedDetails = self.publishedIdentityDetails {
            guard allowVersionDowngrade || newContactIdentityDetailsElements.version > currentPublishedDetails.version else { return }
            try currentPublishedDetails.updateWithNewContactIdentityDetailsElements(newContactIdentityDetailsElements)
        } else {
            guard let trustedIdentityDetails else { throw ObvError.couldNotGetTrustedIdentityDetails }
            guard allowVersionDowngrade || newContactIdentityDetailsElements.version > trustedIdentityDetails.version else { return }
            guard ContactIdentityDetailsPublished(contactIdentity: self, contactIdentityDetailsElements: newContactIdentityDetailsElements) != nil else { throw ObvError.couldNotCreateContactIdentityDetailsPublished }
            assert(self.publishedIdentityDetails != nil)
            if trustedIdentityDetails.photoServerKeyAndLabel == self.publishedIdentityDetails?.photoServerKeyAndLabel {
                // We copy the photo found in the trusted details into the published details
                if let trustedPhotoURL = try trustedIdentityDetails.getPhotoURL(), FileManager.default.fileExists(atPath: trustedPhotoURL.path) {
                    try publishedIdentityDetails?.setContactPhoto(with: trustedPhotoURL)
                }
            }
        }
        
        // If we reach this point, we have published details. We now try to "auto-trust" them.

        try tryToAutoTrustPublishedDetails()
    }
    
    
    private func tryToAutoTrustPublishedDetails() throws {
        
        try refreshCertifiedByOwnKeycloakAndTrustedDetails()
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
        
        guard let trustedIdentityDetails else { throw ObvError.couldNotGetTrustedIdentityDetails }
        let trustedDetails = try trustedIdentityDetails.getIdentityDetails()
        let publishedDetails = try publishedIdentityDetails.getIdentityDetails()
        guard publishedDetails.coreDetails.hasVisuallyIdenticalFirstNameAndLastName(than: trustedDetails.coreDetails) else {
            // Since the details displayed to the user are different in the published details than in the trusted details, we cannot auto-trust them
            Self.logger.info("Fields are different")
            return
        }
        
        // The visible fields of the published details are identical to the trusted fields. The remaining question: do we accept the profile picture?
        // We do in exactly two situations: when the version of the trusted details is -1, and when the profile picture is actually identical in both the trusted and published details.

        guard trustedIdentityDetails.version == -1 || trustedIdentityDetails.photoServerKeyAndLabel == publishedIdentityDetails.photoServerKeyAndLabel else {
            Self.logger.info("We cannot autotrust contact details (trusted details version is %d). Photo server key and label are different.")
            return
        }

        // If we reach this point, we can auto-trust the published details
        try updateTrustedDetailsWithPublishedDetails(publishedDetails)

    }
    
    
    func revokeAsCompromised() {

        guard !self.isRevokedAsCompromised else { return }
        self.isRevokedAsCompromised = true
        
        if !isForcefullyTrustedByUser {
            self.devices.forEach { contactDevice in
                do {
                    try contactDevice.deleteContactDevice() // This will eventually delete the secure channels
                } catch {
                    Self.logger.fault("Could not delete a device of a revoked contact. We continue.")
                    assertionFailure()
                    // Continue anyway
                }
            }
        }
    }
    
    
    func setForcefullyTrustedByUser(to newValue: Bool) {
        guard self.isForcefullyTrustedByUser != newValue else { return }
        self.isForcefullyTrustedByUser = newValue
        if !isNotRevokedAsCompromisedOrIsForcefullyTrustedByUser {
            self.devices.forEach { contactDevice in
                do {
                    try contactDevice.deleteContactDevice() // This will eventually delete the secure channels
                } catch {
                    Self.logger.fault("Could not delete a device of a revoked contact. We continue.")
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
    
    func addTrustOriginIfTrustWouldBeIncreased(_ trustOrigin: TrustOrigin) throws {
        let existingTrustOrigins = self.trustOrigins
        guard trustOrigin.addsTrustWhenAddedToAll(otherTrustOrigins: existingTrustOrigins) else {
            // Since the new trust origin does not increase trust, we do no add it (it would certainly duplicate one that already exists)
            return
        }
        guard let persistedTrustOrigin = PersistedTrustOrigin(trustOrigin: trustOrigin, contact: self) else {
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
    
    func addIfNotExistDeviceWith(uid: UID, createdDuringChannelCreation: Bool) throws {
        guard self.isNotRevokedAsCompromisedOrIsForcefullyTrustedByUser else {
            assertionFailure()
            throw ObvError.contactIsRevokedAsCompromisedAndNotForcefullyTrustedByUser
        }
        let existingDeviceUids = devices.compactMap { try? $0.uid }
        if !existingDeviceUids.contains(uid) {
            guard try ContactDevice(uid: uid, contactIdentity: self, createdDuringChannelCreation: createdDuringChannelCreation) != nil else {
                Self.logger.fault("Could not add a contact device")
                throw ObvError.couldNotCreateContactDevice
            }
        }
    }
    
    
    private func removeIfExistsDeviceWith(uid: UID, flowId: FlowIdentifier) throws {
        guard let context = self.managedObjectContext else {
            Self.logger.fault("The context is not set in removeIfExistsDeviceWith")
            assertionFailure()
            throw ObvError.obvContextIsNil
        }
        for device in devices {
            guard try device.uid == uid else { continue }
            context.delete(device)
        }
    }
    
    
    private func updateIfExistsDeviceWith(with deviceOnServer: ContactDeviceDiscoveryResult.Device, serverCurrentTimestamp: Date) throws {
        guard let device = try self.devices.first(where: { try $0.uid == deviceOnServer.uid }) else { assertionFailure(); return }
        if let deviceBlobOnServer = deviceOnServer.deviceBlobOnServer {
            guard let cryptoIdentity else { assertionFailure(); return }
            try deviceBlobOnServer.checkChallengeResponse(for: cryptoIdentity)
        }
        try device.updateWithContactDeviceDiscoveryResultDevice(deviceOnServer, serverCurrentTimestamp: serverCurrentTimestamp)
    }
    
    
    func processContactDeviceDiscoveryResult(_ contactDeviceDiscoveryResult: ContactDeviceDiscoveryResult, flowId: FlowIdentifier) throws {
        
        if self.wasContactRecentlyOnline != contactDeviceDiscoveryResult.wasContactRecentlyOnline {
            self.wasContactRecentlyOnline = contactDeviceDiscoveryResult.wasContactRecentlyOnline
        }
        
        if self.serverTimestampOfLastContactDiscovery != contactDeviceDiscoveryResult.serverCurrentTimestamp {
            self.serverTimestampOfLastContactDiscovery = contactDeviceDiscoveryResult.serverCurrentTimestamp
        }
        
        // Delete, create, and update devices
        
        let knownDeviceUIDs = Set(self.devices.compactMap { try? $0.uid })
        let correctDeviceUIDs = Set(contactDeviceDiscoveryResult.devices.map(\.uid))
        let deviceUIDsToRemove = knownDeviceUIDs.subtracting(correctDeviceUIDs)
        let deviceUIDsToAdd = correctDeviceUIDs.subtracting(knownDeviceUIDs)
        
        try deviceUIDsToRemove.forEach { try removeIfExistsDeviceWith(uid: $0, flowId: flowId) }
        try deviceUIDsToAdd.forEach { try addIfNotExistDeviceWith(uid: $0, createdDuringChannelCreation: false) }
        try contactDeviceDiscoveryResult.devices.forEach {
            try updateIfExistsDeviceWith(with: $0, serverCurrentTimestamp: contactDeviceDiscoveryResult.serverCurrentTimestamp)
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
        guard let device = try self.devices.first(where: { try $0.uid == uid }) else {
            assertionFailure()
            throw ObvError.couldNotFindContactDevice
        }
        return device.latestChannelCreationPingTimestamp
    }
    
    
    func setLatestChannelCreationPingTimestampOfContactDevice(withUID uid: UID, to date: Date) throws {
        guard let device = try self.devices.first(where: { try $0.uid == uid }) else { return }
        device.setLatestChannelCreationPingTimestamp(to: date)
    }
    
}


// MARK: - Capabilities

extension ContactIdentity {
    
    func setRawCapabilitiesOfDeviceWithUID(_ deviceUID: UID, newRawCapabilities: Set<String>) throws {
        guard let device = try self.devices.first(where: { try $0.uid == deviceUID }) else {
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
    
    func processTrustContactDetailsSyncAtom(serializedIdentityDetailsElements: Data) throws {
        let identityDetailsElements = try IdentityDetailsElements(serializedIdentityDetailsElements)
        guard let publishedIdentityDetails else {
            // No published details to trust, nothing left to do
            return
        }
        // If the local published details for this contact do match the details the user decided to trust on another owned device,
        // we trust these published now.
        // First first construct a IdentityDetailsElements struct on the basis of the local, published details of the contact
        let localPublishedIdentityDetailsElements = try publishedIdentityDetails.getIdentityDetailsElements()
        // We can compare the IdentityDetailsElements that were trusted on the other owned device with the published IdentityDetailsElements on this device
        // If they are identical, we can trust the local published details
        if identityDetailsElements.fieldsAreTheSameButVersionAndSignedDetailsAreNotConsidered(than: localPublishedIdentityDetailsElements) {
            let obvIdentityDetails = try publishedIdentityDetails.getIdentityDetails()
            try self.updateTrustedDetailsWithPublishedDetails(obvIdentityDetails)
        }
    }
    
}


// MARK: - Using pre-keys for encryption

extension ContactIdentity {
    
    func wrap(_ messageKey: any AuthenticatedEncryptionKey, forContactDeviceUID uid: UID, with ownedPrivateKeyForAuthentication: any PrivateKeyForAuthentication, and ownedPublicKeyForAuthentication: any PublicKeyForAuthentication, prng: any PRNGService) throws -> EncryptedData? {
        
        guard let contactDevice = try self.devices.first(where: { try $0.uid == uid }) else {
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
        fileprivate static func withContactIdentifier(_ contactIdentifier: ObvContactIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.withOwnedCryptoIdentity(contactIdentifier.ownedCryptoId.cryptoIdentity),
                Self.withContactCryptoIdentity(contactIdentifier.contactCryptoId.cryptoIdentity),
            ])
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
    
    
    static func getFetchedResultsController(contactIdentifier: ObvContactIdentifier, within context: NSManagedObjectContext) -> NSFetchedResultsController<ContactIdentity> {
        let request: NSFetchRequest<ContactIdentity> = ContactIdentity.fetchRequest()
        request.predicate = Self.Predicate.withContactIdentifier(contactIdentifier)
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.rawIdentity.rawValue, ascending: true)]
        request.fetchLimit = 1
        let frc = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil)
        return frc
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

    static func get(contactIdentity: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws -> ContactIdentity? {
        let request: NSFetchRequest<ContactIdentity> = ContactIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withContactCryptoIdentity(contactIdentity),
            Predicate.withOwnedCryptoIdentity(ownedIdentity),
        ])
        request.fetchLimit = 1
        let item = try context.fetch(request).first
        return item
    }

    static func get(contactIdentity: ObvCryptoIdentity, ownedIdentity: OwnedIdentity) throws -> ContactIdentity? {
        guard let context = ownedIdentity.managedObjectContext else { throw ObvIdentityManagerError.contextIsNil }
        let request: NSFetchRequest<ContactIdentity> = ContactIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withContactCryptoIdentity(contactIdentity),
            Predicate.withOwnedCryptoIdentity(try ownedIdentity.cryptoIdentity),
        ])
        request.fetchLimit = 1
        let item = try context.fetch(request).first
        return item
    }

    static func getAll(within context: NSManagedObjectContext) throws -> [ContactIdentity] {
        let request: NSFetchRequest<ContactIdentity> = ContactIdentity.fetchRequest()
        let items = try context.fetch(request)
        return items
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

    static func exists(cryptoIdentity: ObvCryptoIdentity, ownedIdentity: OwnedIdentity, within context: NSManagedObjectContext) throws -> Bool {
        let request: NSFetchRequest<ContactIdentity> = ContactIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withContactCryptoIdentity(cryptoIdentity),
            Predicate.withOwnedCryptoIdentity(try ownedIdentity.cryptoIdentity),
        ])
        request.fetchLimit = 1
        request.propertiesToFetch = []
        let item = try context.fetch(request).first
        return item != nil
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
            ownedIdentityCryptoIdentityOnDeletion = try? ownedIdentity.cryptoIdentity
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
            Self.logger.info("Insertion of a ContactIdentity during a snapshot restore --> we don't send any notification")
            return
        }
        
        guard let delegateManager = Self.delegateManager else {
            Self.logger.fault("The delegate manager is not set (5)")
            assertionFailure()
            return
        }
        
        if isInserted, let ownedIdentity, let cryptoIdentity = self.cryptoIdentity {
            
            do {
                Self.logger.debug("Sending a ContactIdentityIsNowTrusted notification")
                do {
                    let contactIdentity = try ObvContactIdentity(contactIdentity: self)
                    Task { await Self.observersHolder.contactWasInserted(contactIdentity: contactIdentity) }
                } catch {
                    assertionFailure()
                }
            }
            
            do {
                ObvIdentityNotificationNew.contactIdentityOneToOneStatusChanged(
                    ownedIdentity: try ownedIdentity.cryptoIdentity,
                    contactIdentity: cryptoIdentity)
                .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
            } catch {
                assertionFailure()
            }
            
        } else if isDeleted, let ownedIdentityCryptoIdentityOnDeletion, let rawIdentityOnDeletion, let cryptoIdentity = ObvCryptoIdentity(from: rawIdentityOnDeletion) {
            
            Self.logger.debug("Sending a ContactWasDeleted notification")
            ObvIdentityNotificationNew.contactWasDeleted(ownedCryptoIdentity: ownedIdentityCryptoIdentityOnDeletion,
                                                         contactCryptoIdentity: cryptoIdentity)
            .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
            
        } else if let ownedIdentity, let cryptoIdentity {
            
            if !changedKeys.isEmpty {
                
                //ObvDisplayableLogs.shared.log("[ContactIdentity] Will send contactWasUpdatedWithinTheIdentityManager notification as changedKeys = \(changedKeys)")
                
                do {
                    let contactIdentity = try ObvContactIdentity(contactIdentity: self)
                    Task { await Self.observersHolder.contactWasUpdated(contactIdentity: contactIdentity) }
                } catch {
                    Self.logger.fault("Could not notify about the fact that this contact was updated: \(error.localizedDescription, privacy: .public)")
                    assertionFailure()
                }
                
            }
            
            if changedKeys.contains(Predicate.Key.isRevokedAsCompromised.rawValue) && self.isRevokedAsCompromised {
                
                do {
                    ObvIdentityNotificationNew.contactWasRevokedAsCompromised(
                        ownedIdentity: try ownedIdentity.cryptoIdentity,
                        contactIdentity: cryptoIdentity)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
                } catch {
                    assertionFailure()
                }
                
            }
            
            if changedKeys.contains(Predicate.Key.rawOneToOneStatus.rawValue) {
                
                if !doNotNotifyOnOneToOneStatusChanged {
                    
                    do {
                        ObvIdentityNotificationNew.contactIdentityOneToOneStatusChanged(
                            ownedIdentity: try ownedIdentity.cryptoIdentity,
                            contactIdentity: cryptoIdentity)
                        .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
                    } catch {
                        assertionFailure()
                    }
                    
                }
                
            }
            
            if changedKeys.contains(Predicate.Key.isCertifiedByOwnKeycloak.rawValue) {
                
                do {
                    ObvIdentityNotificationNew.contactIsCertifiedByOwnKeycloakStatusChanged(
                        ownedIdentity: try ownedIdentity.cryptoIdentity,
                        contactIdentity: cryptoIdentity,
                        newIsCertifiedByOwnKeycloak: isCertifiedByOwnKeycloak)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
                } catch {
                    assertionFailure()
                }
                
            }
            
        }
        
        // Potentially notify that the previous backed up profile snapshot is obsolete
        // For a list of all the entities that can perform a similar notification, see `OwnedIdentity`
        
        if !isDeleted {
            let previousBackedUpProfileSnapShotIsObsolete: Bool
            if isInserted {
                previousBackedUpProfileSnapShotIsObsolete = true
            } else if changedKeys.contains(Predicate.Key.persistedTrustOrigins.rawValue) ||
                        changedKeys.contains(Predicate.Key.publishedIdentityDetails.rawValue) ||
                        changedKeys.contains(Predicate.Key.trustedIdentityDetails.rawValue) ||
                        changedKeys.contains(Predicate.Key.trustLevelRaw.rawValue) ||
                        changedKeys.contains(Predicate.Key.isRevokedAsCompromised.rawValue) ||
                        changedKeys.contains(Predicate.Key.isForcefullyTrustedByUser.rawValue) ||
                        changedKeys.contains(Predicate.Key.rawOneToOneStatus.rawValue) {
                previousBackedUpProfileSnapShotIsObsolete = true
            } else {
                previousBackedUpProfileSnapShotIsObsolete = false
            }
            if previousBackedUpProfileSnapShotIsObsolete {
                if let ownedCryptoId = try? ObvCryptoId(identity: self.ownedIdentityIdentity) {
                    Task { await Self.observersHolder.previousBackedUpProfileSnapShotIsObsoleteAsContactIdentityChanged(ownedCryptoId: ownedCryptoId) }
                } else {
                    assertionFailure()
                }
            }
        }

    }
}


// MARK: - For Backup purposes

extension ContactIdentity {
    
    var backupItem: ContactIdentityBackupItem? {
        guard let trustedIdentityDetails else { assertionFailure(); return nil }
        return try? ContactIdentityBackupItem(rawIdentity: rawIdentity,
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

    fileprivate init(rawIdentity: Data, persistedTrustOrigins: Set<PersistedTrustOrigin>, publishedIdentityDetails: ContactIdentityDetailsPublished?, trustedIdentityDetails: ContactIdentityDetailsTrusted, contactGroupsOwned: Set<ContactGroupJoined>, trustLevelRaw: String, isRevokedAsCompromised: Bool, isForcefullyTrustedByUser: Bool, oneToOneStatus: OneToOneStatusOfContactIdentity) throws {
        self.rawIdentity = rawIdentity
        self.persistedTrustOrigins = Set(persistedTrustOrigins.map { $0.backupItem })
        self.publishedIdentityDetails = publishedIdentityDetails?.backupItem
        self.trustedIdentityDetails = trustedIdentityDetails.backupItem
        self.contactGroupsOwnedByContact = try Set(contactGroupsOwned.map { try $0.backupItem })
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
    
    func restoreInstance(within context: NSManagedObjectContext, ownedIdentityIdentity: Data, associations: inout BackupItemObjectAssociations) throws {
        let contactIdentity = ContactIdentity(backupItem: self, ownedIdentityIdentity: ownedIdentityIdentity, within: context)
        try associations.associate(contactIdentity, to: self)
        _ = try persistedTrustOrigins.map { try $0.restoreInstance(within: context, associations: &associations) }
        try publishedIdentityDetails?.restoreInstance(within: context, associations: &associations)
        _ = try trustedIdentityDetails.restoreInstance(within: context, associations: &associations)
        _ = try contactGroupsOwnedByContact.map { try $0.restoreInstance(within: context, associations: &associations) }
    }

    func restoreRelationships(associations: BackupItemObjectAssociations, within context: NSManagedObjectContext) throws {
        let contactIdentity: ContactIdentity = try associations.getObject(associatedTo: self, within: context)
        // Restore the relationships of this instance
        let contactGroupsOwned: Set<ContactGroupJoined> = Set(try self.contactGroupsOwnedByContact.map({ try associations.getObject(associatedTo: $0, within: context) }))
        let persistedTrustOrigins: Set<PersistedTrustOrigin> = Set(try self.persistedTrustOrigins.map({ try associations.getObject(associatedTo: $0, within: context) }))
        let publishedIdentityDetails: ContactIdentityDetailsPublished? = try associations.getObjectIfPresent(associatedTo: self.publishedIdentityDetails, within: context)
        let trustedIdentityDetails: ContactIdentityDetailsTrusted = try associations.getObject(associatedTo: self.trustedIdentityDetails, within: context)
        contactIdentity.restoreRelationships(contactGroupsOwned: contactGroupsOwned,
                                             persistedTrustOrigins: persistedTrustOrigins,
                                             publishedIdentityDetails: publishedIdentityDetails,
                                             trustedIdentityDetails: trustedIdentityDetails)
        // Restore the relationships with this instance relationships
        _ = try self.persistedTrustOrigins.map({ try $0.restoreRelationships(associations: associations, within: context) })
        try self.publishedIdentityDetails?.restoreRelationships(associations: associations, within: context)
        try self.trustedIdentityDetails.restoreRelationships(associations: associations, within: context)
        _ = try self.contactGroupsOwnedByContact.map({ try $0.restoreRelationships(associations: associations, within: context) })
    }

}


// MARK: - For Snapshot purposes

extension ContactIdentity {
    
    var syncSnapshot: ContactIdentitySyncSnapshotNode? {
        guard let trustedIdentityDetails else { assertionFailure(); return nil }
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



struct ContactIdentitySyncSnapshotNode: ObvSyncSnapshotNode, Sendable {
    
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
    
    
    func restoreInstance(within context: NSManagedObjectContext, contactCryptoId: ObvCryptoIdentity, ownedIdentityIdentity: Data, associations: inout SnapshotNodeManagedObjectAssociations) throws {

        guard domain.contains(.trustedIdentityDetails) else {
            throw ObvError.tryingToRestoreIncompleteSnapshot
        }
        
        let contactIdentity = try ContactIdentity(snapshotNode: self, contactCryptoId: contactCryptoId, ownedIdentityIdentity: ownedIdentityIdentity, within: context)
        try associations.associate(contactIdentity, to: self)

        if domain.contains(.persistedTrustOrigins) {
            try persistedTrustOrigins.forEach { trustOriginSnapshotItem in
                try trustOriginSnapshotItem.restoreInstance(within: context, associations: &associations)
            }
        }

        if domain.contains(.publishedIdentityDetails) {
            try publishedIdentityDetails?.restoreInstance(within: context, associations: &associations)
        }

        try trustedIdentityDetails?.restoreInstance(within: context, associations: &associations)
        
    }

    
    func restoreRelationships(associations: SnapshotNodeManagedObjectAssociations, within context: NSManagedObjectContext) throws {

        let contactIdentity: ContactIdentity = try associations.getObject(associatedTo: self, within: context)

        // Restore the relationships of this instance
        
        let persistedTrustOrigins: Set<PersistedTrustOrigin> = Set(try self.persistedTrustOrigins.map({ try associations.getObject(associatedTo: $0, within: context) }))

        let publishedIdentityDetails: ContactIdentityDetailsPublished? = try associations.getObjectIfPresent(associatedTo: self.publishedIdentityDetails, within: context)

        guard let trustedIdentityDetails else {
            assertionFailure()
            throw ObvError.tryingToRestoreIncompleteSnapshot
        }
        
        let contactIdentityDetailsTrusted: ContactIdentityDetailsTrusted = try associations.getObject(associatedTo: trustedIdentityDetails, within: context)

        contactIdentity.restoreRelationships(persistedTrustOrigins: persistedTrustOrigins,
                                             publishedIdentityDetails: publishedIdentityDetails,
                                             trustedIdentityDetails: contactIdentityDetailsTrusted)


        // Restore the relationships with this instance relationships
        
        try self.persistedTrustOrigins.forEach { try $0.restoreRelationships(associations: associations, within: context) }

        try self.publishedIdentityDetails?.restoreRelationships(associations: associations, within: context)

        try self.trustedIdentityDetails?.restoreRelationships(associations: associations, within: context)

    }

    
    enum ObvError: Error {
        case tryingToRestoreIncompleteSnapshot
    }

}


// MARK: - ContactIdentity observers

protocol ContactIdentityObserver: AnyObject {
    func previousBackedUpProfileSnapShotIsObsoleteAsContactIdentityChanged(ownedCryptoId: ObvCryptoId) async
    func contactWasUpdated(contactIdentity: ObvContactIdentity) async
    func contactWasInserted(contactIdentity: ObvContactIdentity) async
}


private actor ObserversHolder: ContactIdentityObserver {
    
    private var observers = [WeakObserver]()
    
    private final class WeakObserver {
        private(set) weak var value: ContactIdentityObserver?
        init(value: ContactIdentityObserver?) {
            self.value = value
        }
    }

    func addObserver(_ newObserver: ContactIdentityObserver) {
        self.observers.append(.init(value: newObserver))
    }

    // Implementing OwnedIdentityObserver

    func previousBackedUpProfileSnapShotIsObsoleteAsContactIdentityChanged(ownedCryptoId: ObvCryptoId) async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for observer in observers.compactMap(\.value) {
                taskGroup.addTask { await observer.previousBackedUpProfileSnapShotIsObsoleteAsContactIdentityChanged(ownedCryptoId: ownedCryptoId) }
            }
        }
    }

    
    func contactWasUpdated(contactIdentity: ObvContactIdentity) async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for observer in observers.compactMap(\.value) {
                taskGroup.addTask { await observer.contactWasUpdated(contactIdentity: contactIdentity) }
            }
        }
    }
    
    
    func contactWasInserted(contactIdentity: ObvContactIdentity) async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for observer in observers.compactMap(\.value) {
                taskGroup.addTask { await observer.contactWasInserted(contactIdentity: contactIdentity) }
            }
        }
    }

}
