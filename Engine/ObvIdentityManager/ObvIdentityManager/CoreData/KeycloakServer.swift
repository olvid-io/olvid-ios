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
import ObvCrypto
import ObvTypes
import OlvidUtils
import os.log
import ObvMetaManager
import JWS


@objc(KeycloakServer)
final class KeycloakServer: NSManagedObject, ObvManagedObject {

    // MARK: Internal constants

    private static let entityName = "KeycloakServer"
    private static let serverURLKey = "serverURL"
    private static let rawOwnedIdentityKey = "rawOwnedIdentity"
    private static let rawJwksKey = "rawJwks"
    private static let clientIdKey = "clientId"
    private static let clientSecretKey = "clientSecret"
    private static let keycloakUserIdKey = "keycloakUserId"
    private static let rawAuthStateKey = "rawAuthState"
    private static let signedOwnedDetailsKey = "signedOwnedDetails"
    private static let selfRevocationTestNonceKey = "selfRevocationTestNonce"
    private static let rawServerSignatureKeyKey = "rawServerSignatureKey"

    private static let errorDomain = "KeycloakServer"
    private static func makeError(message: String) -> Error { NSError(domain: KeycloakServer.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { KeycloakServer.makeError(message: message) }

    // MARK: Attributes

    @NSManaged private(set) var clientId: String // *Not* the user Id
    @NSManaged private(set) var clientSecret: String? // Parameter contained in the configuration QR code. Not available through the keycloak sync process, it is only contained in the configuration QR code.
    @NSManaged private(set) var keycloakUserId: String?
    @NSManaged private(set) var latestRevocationListTimetamp: Date? // Given by the server
    @NSManaged private(set) var rawAuthState: Data?
    @NSManaged private var rawJwks: Data
    @NSManaged private var rawOwnedIdentity: Data
    @NSManaged private var rawPushTopics: Data?
    @NSManaged private(set) var selfRevocationTestNonce: String? // A secret nonce given to the user when they upload their key, to check whether they were revoked
    @NSManaged private var rawServerSignatureKey: Data? // The key (serialized JsonWebKey) used to sign the user's details which should not change
    @NSManaged private(set) var serverURL: URL

    // MARK: Relationships
    
    @NSManaged private(set) var managedOwnedIdentity: OwnedIdentity
    @NSManaged private(set) var revokedIdentities: [KeycloakRevokedIdentity]
    
    // MARK: Other variables
    
    public var obvContext: ObvContext?

    var toObvKeycloakState: ObvKeycloakState {
        get throws {
            let jwks = try self.jwks
            return ObvKeycloakState(
                keycloakServer: serverURL,
                clientId: clientId,
                clientSecret: clientSecret,
                jwks: jwks,
                rawAuthState: rawAuthState,
                signatureVerificationKey: serverSignatureVerificationKey,
                latestLocalRevocationListTimestamp: latestRevocationListTimetamp)
        }
    }
    
    private var serverSignatureVerificationKey: ObvJWK? {
        get {
            guard let rawServerSignatureKey = rawServerSignatureKey else { return nil }
            guard !rawServerSignatureKey.isEmpty else { return nil }
            let value: ObvJWK
            do {
                value = try ObvJWK.decode(rawObvJWK: rawServerSignatureKey)
            } catch {
                assertionFailure(error.localizedDescription)
                return nil
            }
            return value
        }
        set {
            do {
                self.rawServerSignatureKey = try newValue?.encode()
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
    var jwks: ObvJWKSet {
        get throws {
            try ObvJWKSet(data: rawJwks)
        }
    }
    
    func setJwks(_ jwks: ObvJWKSet) throws {
        guard let rawJwks = jwks.jsonData() else { throw makeError(message: "Could not serialize ObvJWKSet") }
        self.rawJwks = rawJwks
    }
    
    var pushTopics: Set<String> {
        guard let rawPushTopics = rawPushTopics else { return Set<String>() }
        return Set(rawPushTopics.split(separator: 0).compactMap { String(data: $0, encoding: .utf8) })
        
    }
        
    private var changedKeys = Set<String>()
    weak var delegateManager: ObvIdentityDelegateManager?

    // MARK: Init
    
    convenience init(keycloakState: ObvKeycloakState, managedOwnedIdentity: OwnedIdentity) throws {
        guard let obvContext = managedOwnedIdentity.obvContext else { throw KeycloakServer.makeError(message: "KeycloakServer initialization failed, cannot find appropriate ObvContext") }
        let entityDescription = NSEntityDescription.entity(forEntityName: KeycloakServer.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.serverURL = keycloakState.keycloakServer
        self.rawOwnedIdentity = managedOwnedIdentity.cryptoIdentity.getIdentity()
        self.selfRevocationTestNonce = nil
        try self.setJwks(keycloakState.jwks)
        self.clientId = keycloakState.clientId
        self.clientSecret = keycloakState.clientSecret
        self.rawPushTopics = nil
        self.keycloakUserId = nil
        self.latestRevocationListTimetamp = nil
        self.rawAuthState = keycloakState.rawAuthState
        self.serverSignatureVerificationKey = keycloakState.signatureVerificationKey
        self.managedOwnedIdentity = managedOwnedIdentity
        self.delegateManager = managedOwnedIdentity.delegateManager
    }

    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreated in a second step
    fileprivate convenience init(backupItem: KeycloakServerBackupItem, rawOwnedIdentity: Data, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: KeycloakServer.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.clientId = backupItem.clientId
        self.clientSecret = backupItem.clientSecret
        self.rawPushTopics = nil
        self.keycloakUserId = backupItem.keycloakUserId
        self.latestRevocationListTimetamp = nil
        self.rawJwks = backupItem.rawJwks
        self.serverURL = backupItem.serverURL
        self.rawOwnedIdentity = rawOwnedIdentity
        self.selfRevocationTestNonce = backupItem.selfRevocationTestNonce
        self.rawServerSignatureKey = backupItem.rawServerSignatureKey
    }

    func setAuthState(authState: Data?) {
        self.rawAuthState = authState
    }

    func setKeycloakUserId(keycloakUserId: String?) {
        self.keycloakUserId = keycloakUserId
    }

    @nonobjc public class func fetchRequest() -> NSFetchRequest<KeycloakServer> {
        return NSFetchRequest<KeycloakServer>(entityName: "KeycloakServer")
    }
    
    func setSelfRevocationTestNonce(_ newSelfRevocationTestNonce: String?) {
        self.selfRevocationTestNonce = newSelfRevocationTestNonce
    }
    
    func delete() throws {
        guard let obvContext = self.obvContext else { assertionFailure(); throw makeError(message: "Could not delete KeycloakServer instance since no context could be found.") }
        obvContext.delete(self)
    }
    
    func setServerSignatureVerificationKey(_ key: ObvJWK?) {
        self.serverSignatureVerificationKey = key
    }

    // MARK: - Identity revocation

    /// Called from `OwnedIdentity`. Returns a set of compromised contacts that are not forcefully trusted by the user.
    func verifyAndAddRevocationList(signedRevocations: [String], revocationListTimetamp: Date, delegateManager: ObvIdentityDelegateManager) throws -> Set<ObvCryptoIdentity> {

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: KeycloakServer.entityName)

        guard let serverSignatureVerificationKey = serverSignatureVerificationKey else {
            throw makeError(message: "Could not verify nor add signed revocations since we did not store the server signature verification key")
        }
        
        guard let obvContext = obvContext else {
            os_log("The ObvContext is nil, we cannot process the revocation list", log: log, type: .fault)
            throw makeError(message: "The ObvContext is nil, we cannot process the revocation list")
        }
        
        var compromisedContacts = Set<ObvCryptoIdentity>()
        
        signedRevocations.forEach { signedRevocation in

            let signedRevocationPayload: Data
            do {
                (signedRevocationPayload, _) = try JWSUtil.verifySignature(signatureVerificationKey: serverSignatureVerificationKey, signature: signedRevocation)
            } catch {
                os_log("The signature verification of one of the signed revocation failed. We ignore this revocation: %{public}@", log: log, type: .error, error.localizedDescription)
                return
            }
            
            // The signature is valid, we try to parse the revocation payload
            
            let keycloakRevocation: JsonKeycloakRevocation
            do {
                keycloakRevocation = try JsonKeycloakRevocation.decode(data: signedRevocationPayload)
            } catch {
                os_log("The raw revocation could not be parsed. We ignore this revocation: %{public}@", log: log, type: .error, error.localizedDescription)
                return
            }
            
            // The signature of this identity revocation is valid, we create a new entry in the KeycloakRevokedIdentity table
            
            do {
                // This call makes sure there is no duplicate in the database
                _ = try KeycloakRevokedIdentity(keycloakServer: self, keycloakRevocation: keycloakRevocation, delegateManager: delegateManager)
            } catch {
                os_log("Could not creat an entry in the KeycloakRevokedIdentity table. We ignore this revocation: %{public}@", log: log, type: .error, error.localizedDescription)
                return
            }
            
            // We now check whether the revoked identity is part of our contacts
            
            let contact: ContactIdentity
            do {
                guard let _contact = try ContactIdentity.get(contactIdentity: keycloakRevocation.cryptoIdentity, ownedIdentity: managedOwnedIdentity.ownedCryptoIdentity.getObvCryptoIdentity(), delegateManager: delegateManager, within: obvContext) else {
                    // The revoked identity is not part of our contacts, we can continue with the next signed revocation
                    return
                }
                contact = _contact
            } catch {
                os_log("Could not check whether the revoked identity is part of our contacts. We continue.", log: log, type: .fault, error.localizedDescription)
                return
            }
            
            // If we reach this point, the revoked identity is part of our contacts. We act depending on the revocation type.
            switch keycloakRevocation.revocationType {
            case .leftCompany:
                // We might have to update the `isCertifiedByOwnKeycloak` of the contact
                guard contact.isCertifiedByOwnKeycloak else { break }
            case .compromised:
                // User key is compromised: mark the contact as revoked and delete all devices/channels from this contact
                if !contact.isForcefullyTrustedByUser {
                    compromisedContacts.insert(contact.cryptoIdentity)
                }
                contact.revokeAsCompromised(delegateManager: delegateManager) // This deletes the devices of the contact
            }

            do {
                try contact.refreshCertifiedByOwnKeycloakAndTrustedDetails(delegateManager: delegateManager)
            } catch {
                os_log("Could not refresh the certified by keycloak status of a contact. We continue.", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }

        }
        
        // We processed the signed revocations. We can now set the latest revocation timestamp.
        // Note that we do *not* compare the received timestamp with the one stored. This is intentional.
        
        self.latestRevocationListTimetamp = revocationListTimetamp
                
        return compromisedContacts
    }
    
    
    /// Called from `OwnedIdentity`
    func pruneOldKeycloakRevokedIdentities() throws {
        guard let latestRevocationListTimetamp = self.latestRevocationListTimetamp else { return }
        let revocationPruneTime = latestRevocationListTimetamp.addingTimeInterval(-ObvConstants.keycloakSignatureValidity)
        try KeycloakRevokedIdentity.batchDeleteEntriesWithRevocationTimestampBeforeDate(revocationPruneTime, for: self)
    }
    
    
    /// Called from `OwnedIdentity`
    func updateKeycloakPushTopicsIfNeeded(newPushTopics: Set<String>) -> Bool {
        var storedPushTopics = self.pushTopics
        var storedPushTopicsUpdated = false
        let toAdd = newPushTopics.subtracting(storedPushTopics)
        if !toAdd.isEmpty {
            storedPushTopics.formUnion(toAdd)
            storedPushTopicsUpdated = true
        }
        let toRemove = storedPushTopics.subtracting(newPushTopics)
        if !toRemove.isEmpty {
            _ = storedPushTopics.subtracting(toRemove)
            storedPushTopicsUpdated = true
        }
        if storedPushTopicsUpdated {
            self.rawPushTopics = Data(storedPushTopics.compactMap({ $0.data(using: .utf8) }).joined(separator: Data(repeating: 0, count: 1)))
        }
        return storedPushTopicsUpdated
    }

    // MARK: - Searching
    
    private struct Predicate {
        static func withRawOwnedIdentity(_ identity: Data) -> NSPredicate {
            NSPredicate(format: "%K == %@", KeycloakServer.rawOwnedIdentityKey, identity as NSData)
        }
        static func withServerURL(_ server: URL) -> NSPredicate {
            NSPredicate(format: "%K == %@", KeycloakServer.serverURLKey, server as NSURL)
        }
    }
    
    static func get(serverURL: URL, identity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> KeycloakServer? {
        let request: NSFetchRequest<KeycloakServer> = KeycloakServer.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withRawOwnedIdentity(identity.getIdentity()),
            Predicate.withServerURL(serverURL),
        ])
        request.fetchLimit = 1
        let item = (try obvContext.fetch(request)).first
        return item
    }

    // MARK: - Sending notifications

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
            let log = OSLog(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: KeycloakServer.entityName)
            os_log("The delegate manager is not set (can happen during backup restore)", log: log, type: .fault)
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            let log = OSLog(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: KeycloakServer.entityName)
            os_log("The notification delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: KeycloakServer.entityName)

        // Send a backupableManagerDatabaseContentChanged notification
        if isInserted || isDeleted || isUpdated ||
            changedKeys.contains(KeycloakServer.serverURLKey) ||
            changedKeys.contains(KeycloakServer.rawJwksKey) ||
            changedKeys.contains(KeycloakServer.clientIdKey) ||
            changedKeys.contains(KeycloakServer.clientSecretKey) ||
            changedKeys.contains(KeycloakServer.keycloakUserIdKey) ||
            changedKeys.contains(KeycloakServer.selfRevocationTestNonceKey) ||
            changedKeys.contains(KeycloakServer.rawServerSignatureKeyKey) {
            guard let flowId = obvContext?.flowId else {
                os_log("Could not notify that this backupable manager database content changed", log: log, type: .fault)
                assertionFailure()
                return
            }
            ObvBackupNotification.backupableManagerDatabaseContentChanged(flowId: flowId)
                .postOnBackgroundQueue(within: notificationDelegate)
        }

    }

}

// MARK: - For Backup purposes

extension KeycloakServer {

    var backupItem: KeycloakServerBackupItem {
        return KeycloakServerBackupItem(
            serverURL: serverURL,
            rawJwks: rawJwks,
            clientId: clientId,
            clientSecret: clientSecret,
            keycloakUserId: keycloakUserId,
            selfRevocationTestNonce: selfRevocationTestNonce,
            rawServerSignatureKey: rawServerSignatureKey)
    }

}

struct KeycloakServerBackupItem: Codable, Hashable {

    fileprivate let serverURL: URL
    fileprivate let rawJwks: Data
    fileprivate let clientId: String
    fileprivate let clientSecret: String?
    fileprivate let keycloakUserId: String?
    fileprivate let selfRevocationTestNonce: String?
    fileprivate let rawServerSignatureKey: Data?

    private static let errorDomain = String(describing: KeycloakServerBackupItem.self)

    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    fileprivate init(serverURL: URL, rawJwks: Data, clientId: String, clientSecret: String?, keycloakUserId: String?, selfRevocationTestNonce: String?, rawServerSignatureKey: Data?) {
        self.serverURL = serverURL
        self.rawJwks = rawJwks
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.keycloakUserId = keycloakUserId
        self.selfRevocationTestNonce = selfRevocationTestNonce
        self.rawServerSignatureKey = rawServerSignatureKey
    }

    enum CodingKeys: String, CodingKey {
        case serverURL = "server_url"
        case jwks = "jwks"
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case keycloakUserId = "keycloak_user_id"
        case selfRevocationTestNonce = "self_revocation_test_nonce"
        case rawServerSignatureKey = "serialized_signature_key"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(serverURL, forKey: .serverURL)
        guard let jwksAsString = String(data: rawJwks, encoding: .utf8) else {
            throw KeycloakServerBackupItem.makeError(message: "Could not parse jkws")
        }
        try container.encode(jwksAsString, forKey: .jwks)
        try container.encode(clientId, forKey: .clientId)
        try container.encodeIfPresent(clientSecret, forKey: .clientSecret)
        try container.encodeIfPresent(keycloakUserId, forKey: .keycloakUserId)
        try container.encodeIfPresent(selfRevocationTestNonce, forKey: .selfRevocationTestNonce)
        if let rawServerSignatureKey = self.rawServerSignatureKey, let rawServerSignatureKeyAsString = String(data: rawServerSignatureKey, encoding: .utf8) {
            try container.encodeIfPresent(rawServerSignatureKeyAsString, forKey: .rawServerSignatureKey)
        }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.serverURL = try values.decode(URL.self, forKey: .serverURL)
        let jwksAsString = try values.decode(String.self, forKey: .jwks)
        guard let rawJwks = jwksAsString.data(using: .utf8) else {
            throw KeycloakServerBackupItem.makeError(message: "Could not encode jkws")
        }
        assert((try? ObvJWKSet(data: rawJwks)) != nil)
        self.rawJwks = rawJwks
        self.clientId = try values.decode(String.self, forKey: .clientId)
        self.clientSecret = try values.decodeIfPresent(String.self, forKey: .clientSecret)
        self.keycloakUserId = try values.decodeIfPresent(String.self, forKey: .keycloakUserId)
        self.selfRevocationTestNonce = try values.decodeIfPresent(String.self, forKey: .selfRevocationTestNonce)
        if let rawServerSignatureKeyAsString = try values.decodeIfPresent(String.self, forKey: .rawServerSignatureKey), let rawServerSignatureKey = rawServerSignatureKeyAsString.data(using: .utf8) {
            // With make sure the serialized data can be deserialized
            if let obvJWKLegacy = try? ObvJWKLegacy.decode(rawObvJWKLegacy: rawServerSignatureKey) {
                let obvJWK = obvJWKLegacy.updateToObvJWK()
                self.rawServerSignatureKey = try obvJWK.encode()
            } else {
                _ = try ObvJWK.decode(rawObvJWK: rawServerSignatureKey)
                self.rawServerSignatureKey = rawServerSignatureKey
            }
        } else {
            self.rawServerSignatureKey = nil
        }
    }

    func restoreInstance(within obvContext: ObvContext, associations: inout BackupItemObjectAssociations, rawOwnedIdentity: Data) throws {
        let keycloakServer = KeycloakServer(backupItem: self, rawOwnedIdentity: rawOwnedIdentity, within: obvContext)
        try associations.associate(keycloakServer, to: self)
    }

    func restoreRelationships(associations: BackupItemObjectAssociations, within obvContext: ObvContext) throws {
        // Nothing do to here
    }

}
