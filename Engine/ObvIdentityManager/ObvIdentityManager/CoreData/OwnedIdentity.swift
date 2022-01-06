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
import ObvEncoder
import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils
import JWS

@objc(OwnedIdentity)
final class OwnedIdentity: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "OwnedIdentity"
    private static let ownedCryptoIdentityKey = "ownedCryptoIdentity"
    static let cryptoIdentityKey = "cryptoIdentity"
    private static let contactIdentitiesKey = "contactIdentities"
    private static let currentDeviceKey = "currentDevice"
    private static let otherDevicesKey = "otherDevices"
    private static let publishedIdentityDetailsKey = "publishedIdentityDetails"
    private static let contactGroupsKey = "contactGroups"
    private static let isActiveKey = "isActive"
    private static let keycloakServerKey = "keycloakServer"
    
    private static let errorDomain = String(describing: OwnedIdentity.self)

    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { OwnedIdentity.makeError(message: message) }

    // MARK: Attributes
    
    @NSManaged private(set) var apiKey: UUID
    // The following var is only used for filtering/searching purposes. It should *only* be set within the setter of `ownedCryptoIdentity`
    @NSManaged private(set) var cryptoIdentity: ObvCryptoIdentity // Unique (not enforced)
    @NSManaged private(set) var isActive: Bool
    private(set) var ownedCryptoIdentity: ObvOwnedCryptoIdentity {
        get {
            return kvoSafePrimitiveValue(forKey: OwnedIdentity.ownedCryptoIdentityKey) as! ObvOwnedCryptoIdentity
        }
        set {
            self.cryptoIdentity = newValue.getObvCryptoIdentity() // Set the cryptoIdentity
            kvoSafeSetPrimitiveValue(newValue, forKey: OwnedIdentity.ownedCryptoIdentityKey)
        }
    }

    // MARK: Relationships
    
    private(set) var keycloakServer: KeycloakServer? {
        get {
            guard let res = kvoSafePrimitiveValue(forKey: OwnedIdentity.keycloakServerKey) as? KeycloakServer else { return nil }
            res.delegateManager = delegateManager
            res.obvContext = obvContext
            return res
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: OwnedIdentity.keycloakServerKey)
        }
    }
    private(set) var contactGroups: Set<ContactGroup> {
        get {
            let res = kvoSafePrimitiveValue(forKey: OwnedIdentity.contactGroupsKey) as! Set<ContactGroup>
            return Set(res.map { $0.delegateManager = delegateManager; $0.obvContext = self.obvContext; return $0 })
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: OwnedIdentity.contactGroupsKey)
        }
    }
    private(set) var contactIdentities: Set<ContactIdentity> {
        get {
            let res = kvoSafePrimitiveValue(forKey: OwnedIdentity.contactIdentitiesKey) as! Set<ContactIdentity>
            return Set(res.map { $0.delegateManager = delegateManager; $0.obvContext = self.obvContext; return $0 })
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: OwnedIdentity.contactIdentitiesKey)
        }
    }
    private(set) var currentDevice: OwnedDevice {
        get {
            let res = kvoSafePrimitiveValue(forKey: OwnedIdentity.currentDeviceKey) as! OwnedDevice
            res.delegateManager = delegateManager
            res.obvContext = self.obvContext
            return res
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: OwnedIdentity.currentDeviceKey)
        }
    }
    private(set) var otherDevices: Set<OwnedDevice> {
        get {
            let res = kvoSafePrimitiveValue(forKey: OwnedIdentity.otherDevicesKey) as! Set<OwnedDevice>
            return Set(res.map { $0.delegateManager = delegateManager; $0.obvContext = self.obvContext; return $0 })
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: OwnedIdentity.otherDevicesKey)
        }
    }
    private(set) var publishedIdentityDetails: OwnedIdentityDetailsPublished {
        get {
            let item = kvoSafePrimitiveValue(forKey: OwnedIdentity.publishedIdentityDetailsKey) as! OwnedIdentityDetailsPublished
            item.obvContext = self.obvContext
            return item
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: OwnedIdentity.publishedIdentityDetailsKey)
        }
    }

    // MARK: Other variables
    
    weak var delegateManager: ObvIdentityDelegateManager?
    var obvContext: ObvContext?
    var currentDeviceUid: UID {
        return currentDevice.uid
    }

    private var changedKeys = Set<String>()

    // MARK: - Initializer
    
    /// This initializer purpose is to create a longterm owned identity
    convenience init?(apiKey: UUID, serverURL: URL, identityDetails: ObvIdentityDetails, accordingTo pkEncryptionImplemByteId: PublicKeyEncryptionImplementationByteId, and authEmplemByteId: AuthenticationImplementationByteId, keycloakState: ObvKeycloakState?, using prng: PRNGService, delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) {
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: OwnedIdentity.entityName)
        let entityDescription = NSEntityDescription.entity(forEntityName: OwnedIdentity.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.delegateManager = delegateManager
        self.apiKey = apiKey
        // An owned identity is always active on creation. Several places within the engine assume this behaviour.
        self.isActive = true
        self.ownedCryptoIdentity = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL,
                                                              forAuthenticationImplementationId: authEmplemByteId,
                                                              andPublicKeyEncryptionImplementationByteId: pkEncryptionImplemByteId,
                                                              using: prng)
        self.contactIdentities = Set<ContactIdentity>()
        guard let device = OwnedDevice(ownedIdentity: self, with: prng, delegateManager: delegateManager) else {
            os_log("Could not create a current device for the new owned identity", log: log, type: .fault)
            return nil
        }
        self.currentDevice = device
        self.otherDevices = Set<OwnedDevice>()
        self.contactGroups = Set<ContactGroup>()
        guard let publishedIdentityDetails = OwnedIdentityDetailsPublished(ownedIdentity: self, identityDetails: identityDetails, version: 0, delegateManager: delegateManager) else { return nil }
        self.publishedIdentityDetails = publishedIdentityDetails
        if let keycloakState = keycloakState {
            do {
                self.keycloakServer = try KeycloakServer(keycloakState: keycloakState, managedOwnedIdentity: self)
            } catch {
                os_log("Could not create a KeycloakServer for the new owned identity", log: log, type: .fault)
                return nil
            }
        } else {
            self.keycloakServer = nil
        }
        
        let cryptoIdentity = self.cryptoIdentity
        try? obvContext.addContextDidSaveCompletionHandler { error in
            guard error == nil else { assertionFailure(); return }
            ObvIdentityNotificationNew.newOwnedIdentityWithinIdentityManager(cryptoIdentity: cryptoIdentity)
                .postOnBackgroundQueue(within: delegateManager.notificationDelegate)
        }
    }
    
    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    convenience init(backupItem: OwnedIdentityBackupItem, notificationDelegate: ObvNotificationDelegate, within obvContext: ObvContext) throws {
        let entityDescription = NSEntityDescription.entity(forEntityName: OwnedIdentity.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.apiKey = backupItem.apiKey
        // We do *not* use the backupItem.isActive value. This information is used at the ObvIdentityManagerImplementation level, to decide whether to ask for reactivation of this owned identity or not.
        self.isActive = false
        self.cryptoIdentity = backupItem.cryptoIdentity
        guard let ownedCryptoIdentity = backupItem.ownedCryptoIdentity else {
            throw OwnedIdentity.makeError(message: "Could not recover owned crypto identity")
        }
        self.ownedCryptoIdentity = ownedCryptoIdentity
        
        try obvContext.addContextDidSaveCompletionHandler { error in
            guard error == nil else { assertionFailure(); return }
            ObvIdentityNotificationNew.newOwnedIdentityWithinIdentityManager(cryptoIdentity: backupItem.cryptoIdentity)
                .postOnBackgroundQueue(within: notificationDelegate)
        }
        
    }

    fileprivate func restoreRelationships(contactGroups: Set<ContactGroup>, contactIdentities: Set<ContactIdentity>, currentDevice: OwnedDevice, publishedIdentityDetails: OwnedIdentityDetailsPublished, keycloakServer: KeycloakServer?) {
        self.contactGroups = contactGroups
        self.contactIdentities = contactIdentities
        self.currentDevice = currentDevice
        /* maskingUid is nil */
        self.otherDevices = Set<OwnedDevice>()
        self.publishedIdentityDetails = publishedIdentityDetails
        self.keycloakServer = keycloakServer
    }

    func delete(within obvContext: ObvContext) throws {
        try publishedIdentityDetails.delete(within: obvContext)
        obvContext.delete(self)
    }
}


// MARK: - Details and owned identity management

extension OwnedIdentity {
    
    func updatePublishedDetailsWithNewDetails(_ newIdentityDetails: ObvIdentityDetails, delegateManager: ObvIdentityDelegateManager) throws {
        guard let obvContext = self.obvContext else {
            assertionFailure()
            throw makeError(message: "Could not find obv context")
        }
        try self.publishedIdentityDetails.updateWithNewIdentityDetails(newIdentityDetails,
                                                                       delegateManager: delegateManager,
                                                                       within: obvContext)
    }
    
    
    func setAPIKey(to newApiKey: UUID, keycloakServerURL: URL?) throws {
        if let currentKeycloakServerURL = keycloakServer?.serverURL {
            guard currentKeycloakServerURL == keycloakServerURL else {
                assertionFailure()
                throw makeError(message: "Error: trying to set an api key on a keycloak managed identity without specifying the keycloak server.")
            }
        }
        self.apiKey = newApiKey
    }

    
    func updatePhoto(withData photoData: Data, version: Int, delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) throws {
        if self.publishedIdentityDetails.version == version {
            try self.publishedIdentityDetails.setPhoto(data: photoData, creatingNewFileIn: delegateManager.identityPhotosDirectory, notificationDelegate: delegateManager.notificationDelegate, within: obvContext)
        }
    }

    
    func deactivate() {
        isActive = false
    }
    
    func reactivate() {
        isActive = true
    }

}



// MARK: - Keycloak management

extension OwnedIdentity {

    var isKeycloakManaged: Bool {
        self.keycloakServer != nil
    }
    
    func unbindFromKeycloak(delegateManager: ObvIdentityDelegateManager) throws {
        keycloakServer?.obvContext = obvContext
        try keycloakServer?.delete()
        keycloakServer = nil
        refreshCertifiedByOwnKeycloakAndTrustedDetailsForAllContacts(delegateManager: delegateManager)
    }
    
    func bindToKeycloak(keycloakState: ObvKeycloakState, delegateManager: ObvIdentityDelegateManager) throws {
        // If there is a previous keycloak server, we unbind from this old server before setting the new one
        if self.keycloakServer != nil {
            try unbindFromKeycloak(delegateManager: delegateManager)
        }
        self.keycloakServer = try KeycloakServer(keycloakState: keycloakState, managedOwnedIdentity: self)
        refreshCertifiedByOwnKeycloakAndTrustedDetailsForAllContacts(delegateManager: delegateManager)
    }
    
    private func refreshCertifiedByOwnKeycloakAndTrustedDetailsForAllContacts(delegateManager: ObvIdentityDelegateManager) {
        for contact in contactIdentities {
            do {
                try contact.refreshCertifiedByOwnKeycloakAndTrustedDetails(delegateManager: delegateManager)
            } catch {
                // In production, we continue anyway
                assertionFailure()
            }
        }
    }
    
    
    func setOwnedIdentityKeycloakSignatureKey(_ keycloakServersignatureVerificationKey: ObvJWK?, delegateManager: ObvIdentityDelegateManager) throws {
        guard isKeycloakManaged else { throw makeError(message: "Owned identity is not keycloak managed. Cannot set keycloak server signature key") }
        keycloakServer?.setServerSignatureVerificationKey(keycloakServersignatureVerificationKey)
        refreshCertifiedByOwnKeycloakAndTrustedDetailsForAllContacts(delegateManager: delegateManager)
    }

    
    func verifyAndAddRevocationList(signedRevocations: [String], revocationListTimetamp: Date, delegateManager: ObvIdentityDelegateManager) throws -> Set<ObvCryptoIdentity> {
        assert(keycloakServer != nil)
        return try keycloakServer?.verifyAndAddRevocationList(signedRevocations: signedRevocations, revocationListTimetamp: revocationListTimetamp, delegateManager: delegateManager) ?? Set<ObvCryptoIdentity>()
    }

    
    func pruneOldKeycloakRevokedContacts(delegateManager: ObvIdentityDelegateManager) {
        assert(keycloakServer != nil)
        do {
            try keycloakServer?.pruneOldKeycloakRevokedIdentities()
        } catch {
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: OwnedIdentity.entityName)
            os_log("Could not prune old keycloak revoked identities: %{public}@", log: log, type: .fault, error.localizedDescription)
        }
    }
    
    
    /// Each time we update the revocation lists of the keycloak server of a managed owned identity, we also update its
    /// `latestRevocationListTimetamp`. Consequently, we want to uncertify managed contacts whose details are
    /// older than this timestamp minus, e.g., two months.
    func uncertifyExpiredSignedContactDetails(delegateManager: ObvIdentityDelegateManager) {
        assert(keycloakServer != nil)
        let certifiedContacts = contactIdentities.filter({ $0.isCertifiedByOwnKeycloak })
        certifiedContacts.forEach { contact in
            do {
                try contact.refreshCertifiedByOwnKeycloakAndTrustedDetails(delegateManager: delegateManager)
            } catch {
                let log = OSLog(subsystem: delegateManager.logSubsystem, category: OwnedIdentity.entityName)
                os_log("Could not refresh the isCertifiedByOwnKeycloak of one of our contacts: %{public}@", log: log, type: .fault, error.localizedDescription)
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
    
}

// MARK: - ContactDevice management

extension OwnedIdentity {
    
    func addRemoteDeviceWith(uid: UID) throws {
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: "OwnedIdentity")
            os_log("The delegate manager is not set (6)", log: log, type: .fault)
            throw makeError(message: "The delegate manager is not set (6)")
        }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: "OwnedIdentity")
        guard OwnedDevice(remoteDeviceUid: uid, ownedIdentity: self, delegateManager: delegateManager) != nil else {
            os_log("Could not add a remote device", log: log, type: .fault)
            throw makeError(message: "Could not add a remote device")
        }
    }
    
}


// MARK: - Keychain management

extension OwnedIdentity {
    
    private func iOSSecItemAdd(ownedCryptoIdentity: ObvOwnedCryptoIdentity) throws {
        guard let delegateManager = self.delegateManager else {
            throw makeError(message: "The delegate manager is not set")
        }
        let identity = ownedCryptoIdentity.getObvCryptoIdentity().getIdentity()
        let encodedOwnedCryptoIdentity = ownedCryptoIdentity.encode()
        let accessGroup = delegateManager.sharedContainerIdentifier
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                     kSecAttrAccount as String: identity,
                                     kSecValueData as String: encodedOwnedCryptoIdentity.rawData,
                                     kSecAttrAccessGroup as String: accessGroup]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            if let delegateManager = self.delegateManager {
                let log = OSLog(subsystem: delegateManager.logSubsystem, category: "OwnedIdentity")
                os_log("Keychain error: %@", log: log, type: .fault, status.description)
            }
            throw makeError(message: "Keychain error: \(status.description)")
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
            if let delegateManager = self.delegateManager {
                let log = OSLog(subsystem: delegateManager.logSubsystem, category: "OwnedIdentity")
                os_log("Keychain error: %@", log: log, type: .fault, status.description)
            }
            throw NSError()
        }
        
        guard let existingItem = item as? [String: Any],
            let encodedOwnedCryptoIdentityRawData = existingItem[kSecValueData as String] as? Data,
            let encodedOwnedCryptoIdentity = ObvEncoded(withRawData: encodedOwnedCryptoIdentityRawData),
            let ownedCryptoIdentity = ObvOwnedCryptoIdentity(encodedOwnedCryptoIdentity) else {
                if let delegateManager = self.delegateManager {
                    let log = OSLog(subsystem: delegateManager.logSubsystem, category: "OwnedIdentity")
                    os_log("Could not extract owned identity from keychain item", log: log, type: .fault)
                }
                throw NSError()
        }

        return ownedCryptoIdentity
    }
    
}


// MARK: - Convenience DB getters
extension OwnedIdentity {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<OwnedIdentity> {
        return NSFetchRequest<OwnedIdentity>(entityName: entityName)
    }

    static func get(_ identity: ObvCryptoIdentity, delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) throws -> OwnedIdentity? {
        let request: NSFetchRequest<OwnedIdentity> = OwnedIdentity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", OwnedIdentity.cryptoIdentityKey, identity)
        let item = (try obvContext.fetch(request)).first
        item?.delegateManager = delegateManager
        return item
    }
    
    static func getAll(delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) throws -> [OwnedIdentity] {
        let request: NSFetchRequest<OwnedIdentity> = OwnedIdentity.fetchRequest()
        let items = try obvContext.fetch(request)
        return items.map { $0.delegateManager = delegateManager; return $0 }
    }
    
    static func getApiKey(_ identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> UUID {
        let request: NSFetchRequest<OwnedIdentity> = OwnedIdentity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", OwnedIdentity.cryptoIdentityKey, identity)
        request.fetchLimit = 1
        guard let item = try obvContext.fetch(request).first else { throw NSError() }
        return item.apiKey
    }
}


// MARK: - Sending notifications

extension OwnedIdentity {
    
    override func willSave() {
        super.willSave()
        if !isInserted {
            changedKeys = Set<String>(self.changedValues().keys)
        }
    }
    
    override func didSave() {
        super.didSave()
        
        defer {
            changedKeys.removeAll()
        }

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: OwnedIdentity.entityName)
            os_log("The delegate manager is not set (7)", log: log, type: .fault)
            // This will certainly happen during a backup restore. Not sure this is a good thing...
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            let log = OSLog(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: OwnedIdentity.entityName)
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: OwnedIdentity.entityName)
        
        if isInserted {
            os_log("A new owned identity was inserted", log: log, type: .debug)
        } else if isDeleted {
            os_log("An owned identity was deleted", log: log, type: .debug)
        }
        
        if changedKeys.contains(OwnedIdentity.isActiveKey) {
            if self.isActive {
                guard let flowId = obvContext?.flowId else { assertionFailure(); return }
                let notification = ObvIdentityNotificationNew.ownedIdentityWasReactivated(ownedCryptoIdentity: self.ownedCryptoIdentity.getObvCryptoIdentity(), flowId: flowId)
                notification.postOnBackgroundQueue(within: notificationDelegate)
            } else {
                guard let flowId = obvContext?.flowId else { assertionFailure(); return }
                let notification = ObvIdentityNotificationNew.ownedIdentityWasDeactivated(ownedCryptoIdentity: self.ownedCryptoIdentity.getObvCryptoIdentity(), flowId: flowId)
                notification.postOnBackgroundQueue(within: notificationDelegate)
            }
        }
        
        if changedKeys.contains(OwnedIdentity.keycloakServerKey) {
            guard let flowId = obvContext?.flowId else { assertionFailure(); return }
            ObvIdentityNotificationNew.ownedIdentityKeycloakServerChanged(ownedCryptoIdentity: self.ownedCryptoIdentity.getObvCryptoIdentity(), flowId: flowId)
                .postOnBackgroundQueue(within: notificationDelegate)
        }
        
        // Send a backupableManagerDatabaseContentChanged notification
        if isInserted || isDeleted || isUpdated || !changedKeys.isEmpty {
            guard let flowId = obvContext?.flowId else {
                os_log("Could not notify that this backupable manager database content changed", log: log, type: .fault)
                assertionFailure()
                return
            }
            let notification = ObvBackupNotification.backupableManagerDatabaseContentChanged(flowId: flowId)
            notification.postOnDispatchQueue(withLabel: "Queue for sending a backupableManagerDatabaseContentChanged notification", within: notificationDelegate)
        }

    }
}


// MARK: - For Backup purposes

extension OwnedIdentity {
    
    var backupItem: OwnedIdentityBackupItem {
        let contactGroupsOwned = contactGroups.filter { $0 is ContactGroupOwned } as! Set<ContactGroupOwned>
        return OwnedIdentityBackupItem(apiKey: apiKey,
                                       ownedCryptoIdentity: ownedCryptoIdentity,
                                       contactIdentities: contactIdentities,
                                       currentDevice: currentDevice,
                                       otherDevices: otherDevices,
                                       publishedIdentityDetails: publishedIdentityDetails,
                                       contactGroupsOwned: contactGroupsOwned,
                                       keycloakServer: keycloakServer,
                                       isActive: isActive)
    }

}


struct OwnedIdentityBackupItem: Codable, Hashable {
    
    fileprivate let apiKey: UUID
    fileprivate let privateIdentity: ObvOwnedCryptoIdentityPrivateBackupItem
    let cryptoIdentity: ObvCryptoIdentity
    fileprivate let contactIdentities: Set<ContactIdentityBackupItem>
    let publishedIdentityDetails: OwnedIdentityDetailsPublishedBackupItem
    fileprivate let ownedGroups: Set<ContactGroupOwnedBackupItem>?
    let keycloakServer: KeycloakServerBackupItem?
    let isActive: Bool

    private static let errorDomain = String(describing: Self.self)

    var ownedCryptoIdentity: ObvOwnedCryptoIdentity? {
        return privateIdentity.getOwnedIdentity(cryptoIdentity: cryptoIdentity)
    }
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    fileprivate init(apiKey: UUID, ownedCryptoIdentity: ObvOwnedCryptoIdentity, contactIdentities: Set<ContactIdentity>, currentDevice: OwnedDevice, otherDevices: Set<OwnedDevice>, publishedIdentityDetails: OwnedIdentityDetailsPublished, contactGroupsOwned: Set<ContactGroupOwned>, keycloakServer: KeycloakServer?, isActive: Bool) {
        self.apiKey = apiKey
        self.cryptoIdentity = ownedCryptoIdentity.getObvCryptoIdentity()
        self.privateIdentity = ownedCryptoIdentity.privateBackupItem
        self.contactIdentities = Set(contactIdentities.map { $0.backupItem })
        self.publishedIdentityDetails = publishedIdentityDetails.backupItem
        self.ownedGroups = contactGroupsOwned.isEmpty ? nil : Set(contactGroupsOwned.map { $0.backupItem })
        self.keycloakServer = keycloakServer?.backupItem
        self.isActive = isActive
    }
    
    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case privateIdentity = "private_identity"
        case cryptoIdentity = "owned_identity"
        case contactIdentities = "contact_identities"
        case publishedIdentityDetails = "published_details"
        case ownedGroups = "owned_groups"
        case keycloak = "keycloak"
        case isActive = "active"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(cryptoIdentity.getIdentity(), forKey: .cryptoIdentity)
        try container.encode(privateIdentity, forKey: .privateIdentity)
        try container.encode(contactIdentities, forKey: .contactIdentities)
        try container.encode(publishedIdentityDetails, forKey: .publishedIdentityDetails)
        try container.encodeIfPresent(ownedGroups, forKey: .ownedGroups)
        try container.encode(isActive, forKey: .isActive)
        do {
            try container.encodeIfPresent(keycloakServer, forKey: .keycloak)
        } catch {
            assertionFailure("Could not backup keycloak server: \(error.localizedDescription)")
            // In production, we continue anyway
        }
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.apiKey = try values.decode(UUID.self, forKey: .apiKey)
        self.privateIdentity = try values.decode(ObvOwnedCryptoIdentityPrivateBackupItem.self, forKey: .privateIdentity)
        let identity = try values.decode(Data.self, forKey: .cryptoIdentity)
        guard let cryptoIdentity = ObvCryptoIdentity(from: identity) else {
            throw OwnedIdentityBackupItem.makeError(message: "Could not get crypto identity")
        }
        self.cryptoIdentity = cryptoIdentity
        self.contactIdentities = try values.decode(Set<ContactIdentityBackupItem>.self, forKey: .contactIdentities)
        self.publishedIdentityDetails = try values.decode(OwnedIdentityDetailsPublishedBackupItem.self, forKey: .publishedIdentityDetails)
        self.ownedGroups = try values.decodeIfPresent(Set<ContactGroupOwnedBackupItem>.self, forKey: .ownedGroups)
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
    
    func restoreInstance(within obvContext: ObvContext, associations: inout BackupItemObjectAssociations, notificationDelegate: ObvNotificationDelegate) throws {
        let ownedIdentity = try OwnedIdentity(backupItem: self, notificationDelegate: notificationDelegate, within: obvContext)
        try associations.associate(ownedIdentity, to: self)
        _ = try contactIdentities.map { try $0.restoreInstance(within: obvContext, associations: &associations) }
        try publishedIdentityDetails.restoreInstance(within: obvContext, associations: &associations)
        _ = try ownedGroups?.map { try $0.restoreInstance(within: obvContext, associations: &associations) }
        try keycloakServer?.restoreInstance(within: obvContext, associations: &associations, rawOwnedIdentity: ownedIdentity.cryptoIdentity.getIdentity())
    }
    
    func restoreRelationships(associations: BackupItemObjectAssociations, prng: PRNGService, within obvContext: ObvContext) throws {
        let ownedIdentity: OwnedIdentity = try associations.getObject(associatedTo: self, within: obvContext)
        // Restore the relationships of this instance
        let contactGroups: Set<ContactGroup>
        do {
            let ownedGroups: Set<ContactGroupOwned> = Set(try self.ownedGroups?.map({ try associations.getObject(associatedTo: $0, within: obvContext) }) ?? [])
            var joinedGroups = Set<ContactGroupJoined>()
            for contact in self.contactIdentities {
                let contactGroupsOwnedByContact: Set<ContactGroupJoined> = Set(try contact.contactGroupsOwnedByContact.map({ try associations.getObject(associatedTo: $0, within: obvContext) }))
                joinedGroups.formUnion(contactGroupsOwnedByContact)
            }
            contactGroups = (ownedGroups as Set<ContactGroup>).union(joinedGroups)
        }
        let contactIdentities: Set<ContactIdentity> = Set(try self.contactIdentities.map({ try associations.getObject(associatedTo: $0, within: obvContext) }))
        let currentDevice = OwnedDeviceBackupItem.generateNewCurrentDevice(prng: prng, within: obvContext)
        let publishedIdentityDetails: OwnedIdentityDetailsPublished = try associations.getObject(associatedTo: self.publishedIdentityDetails, within: obvContext)
        let keycloakServer: KeycloakServer? = try associations.getObjectIfPresent(associatedTo: self.keycloakServer, within: obvContext)
        ownedIdentity.restoreRelationships(contactGroups: contactGroups,
                                           contactIdentities: contactIdentities,
                                           currentDevice: currentDevice,
                                           publishedIdentityDetails: publishedIdentityDetails,
                                           keycloakServer: keycloakServer)
        // Restore the relationships with this instance relationships
        _ = try self.contactIdentities.map({ try $0.restoreRelationships(associations: associations, within: obvContext) })
        try self.publishedIdentityDetails.restoreRelationships(associations: associations, within: obvContext)
        _ = try self.ownedGroups?.map({ try $0.restoreRelationships(associations: associations, within: obvContext) })
        try self.keycloakServer?.restoreRelationships(associations: associations, within: obvContext)
        // If there is a photoServerLabel within the published details, we create an instance of IdentityServerUserData
        if let photoServerLabel = publishedIdentityDetails.photoServerLabel {
            _ = IdentityServerUserData.createForOwnedIdentityDetails(ownedIdentity: ownedIdentity.cryptoIdentity,
                                                                     label: photoServerLabel,
                                                                     within: obvContext)
        }
        // We scan each owned group. For each, of there is a photoServerLabel within the published details, we create an instance of IdentityServerUserData
        for contactGroup in contactGroups {
            guard let ownedGroup = contactGroup as? ContactGroupOwned else { continue }
            guard let photoServerLabel = ownedGroup.publishedDetails.photoServerLabel else { continue }
            _ = GroupServerUserData.createForOwnedGroupDetails(ownedIdentity: ownedIdentity.cryptoIdentity,
                                                               label: photoServerLabel,
                                                               groupUid: ownedGroup.groupUid,
                                                               within: obvContext)
        }
    }

}
