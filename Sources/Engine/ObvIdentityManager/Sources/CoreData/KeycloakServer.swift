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
import ObvJWS


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
    @NSManaged private(set) var latestGroupUpdateTimestamp: Date? // Given by the server
    @NSManaged private(set) var latestRevocationListTimetamp: Date? // Given by the server
    @NSManaged private(set) var ownAPIKey: UUID?
    @NSManaged private(set) var rawAuthState: Data?
    @NSManaged private var rawJwks: Data
    @NSManaged private var rawOwnedIdentity: Data
    @NSManaged private var rawPushTopics: Data?
    @NSManaged private(set) var selfRevocationTestNonce: String? // A secret nonce given to the user when they upload their key, to check whether they were revoked
    @NSManaged private var rawServerSignatureKey: Data? // The key (serialized JsonWebKey) used to sign the user's details which should not change
    @NSManaged private(set) var serverURL: URL
    @NSManaged private(set) var isTransferRestricted: Bool // If true, the user will be unable to transfer their identity to a new device unless they can successfully authenticate with the Keycloak server

    // MARK: Relationships
    
    @NSManaged private(set) var managedOwnedIdentity: OwnedIdentity
    @NSManaged private(set) var revokedIdentities: [KeycloakRevokedIdentity]
    
    // MARK: Other variables
    
    weak var obvContext: ObvContext?

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
                latestLocalRevocationListTimestamp: latestRevocationListTimetamp,
                latestGroupUpdateTimestamp: latestGroupUpdateTimestamp,
                isTransferRestricted: isTransferRestricted)
        }
    }
    
    private var serverSignatureVerificationKey: ObvJWK? {
        get {
            guard let rawServerSignatureKey = rawServerSignatureKey else { return nil }
            guard !rawServerSignatureKey.isEmpty else { return nil }
            let value: ObvJWK
            do {
                value = try ObvJWK.jsonDecode(rawObvJWK: rawServerSignatureKey)
            } catch {
                assertionFailure(error.localizedDescription)
                return nil
            }
            return value
        }
        set {
            do {
                self.rawServerSignatureKey = try newValue?.jsonEncode()
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
    

    var pushTopicsForKeycloakServer: Set<String> {
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
        self.isTransferRestricted = keycloakState.isTransferRestricted
    }


    /// Used *exclusively* during a backup restore for creating an instance, relationships are recreated in a second step
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
        self.isTransferRestricted = false
    }

    
    /// Used *exclusively* during a snapshot restore for creating an instance, relationships are recreated in a second step
    fileprivate convenience init(snapshotNode: KeycloakServerSnapshotNode, rawOwnedIdentity: Data, within obvContext: ObvContext) throws {
        let entityDescription = NSEntityDescription.entity(forEntityName: KeycloakServer.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        guard let clientId = snapshotNode.clientId else {
            assertionFailure()
            throw KeycloakServerSnapshotNode.ObvError.tryingToRestoreIncompleteSnapshot
        }
        self.clientId = clientId
        self.clientSecret = snapshotNode.clientSecret
        self.rawPushTopics = nil
        self.keycloakUserId = snapshotNode.keycloakUserId
        self.latestRevocationListTimetamp = nil
        guard let rawJwks = snapshotNode.rawJwks else {
            assertionFailure()
            throw KeycloakServerSnapshotNode.ObvError.tryingToRestoreIncompleteSnapshot
        }
        self.rawJwks = rawJwks
        guard let serverURL = snapshotNode.serverURL else {
            assertionFailure()
            throw KeycloakServerSnapshotNode.ObvError.tryingToRestoreIncompleteSnapshot
        }
        self.serverURL = serverURL
        self.rawOwnedIdentity = rawOwnedIdentity
        self.selfRevocationTestNonce = snapshotNode.selfRevocationTestNonce
        self.rawServerSignatureKey = snapshotNode.rawServerSignatureKey
        self.isTransferRestricted = snapshotNode.isTransferRestricted ?? false
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

    func saveRegisteredKeycloakAPIKey(apiKey newAPIKey: UUID) {
        guard self.ownAPIKey != newAPIKey else { return }
        self.ownAPIKey = newAPIKey
    }
    
    
    func setIsTransferRestricted(to isTransferRestricted: Bool) {
        if self.isTransferRestricted != isTransferRestricted {
            self.isTransferRestricted = isTransferRestricted
        }
    }
    
    
    // MARK: - Verifying Keycloak signature on restricted transfer
    
    /// This method is called during a keycloak managed profile transfer, if the keycloak enforces a restriction on the transfer. It is called on the source device, when it receives a proof from the target device that it was able to authenticate against the keycloak server.
    /// This method verifies the signature and checks that the payload contained in the signature contains the elements that we expect.
    func verifyKeycloakSignature(keycloakTransferProof: ObvKeycloakTransferProof, keycloakTransferProofElements: ObvKeycloakTransferProofElements, delegateManager: ObvIdentityDelegateManager) throws(ObvIdentityManagerError) {
        
        let logger = Logger(subsystem: delegateManager.logSubsystem, category: KeycloakServer.entityName)
        
        guard let serverSignatureVerificationKey = serverSignatureVerificationKey else {
            throw .keycloakServerSignatureVerificationKeyIsNil
        }

        let payload: Data
        do {
            (payload, _) = try JWSUtil.verifySignature(signatureVerificationKey: serverSignatureVerificationKey, signature: keycloakTransferProof.signature)
        } catch {
            logger.fault("The keycloak transfer proof signature verification failed: \(error.localizedDescription)")
            throw .signatureVerificationFailed
        }

        // The signature is valid, we try to parse the revocation payload

        let keycloakTransferProofContent: ObvKeycloakTransferProofContent
        do {
            keycloakTransferProofContent = try ObvKeycloakTransferProofContent.jsonDecode(payload: payload)
        } catch {
            logger.fault("Parsing failed: \(error.localizedDescription)")
            throw .parsingFailed
        }
        
        // Check that the payload that was signed against the expected ObvKeycloakTransferProofElements
        
        guard let keycloakUserId = self.keycloakUserId else {
            assertionFailure()
            throw .keycloakUserIdIsNil
        }
        
        guard keycloakTransferProofContent.isValid(ownedCryptoId: self.managedOwnedIdentity.cryptoIdentity, keycloakId: keycloakUserId, keycloakTransferProofElements: keycloakTransferProofElements) else {
            assertionFailure()
            throw .signaturePayloadVerificationFailed
        }
                
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
                keycloakRevocation = try JsonKeycloakRevocation.jsonDecode(data: signedRevocationPayload)
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
                if !contact.isForcefullyTrustedByUser, let contactCryptoIdentity = contact.cryptoIdentity {
                    compromisedContacts.insert(contactCryptoIdentity)
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
        var storedPushTopics = self.pushTopicsForKeycloakServer
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
    
    
    // MARK: - Keycloak pushed groups
    
    /// Processes the group informations received from the keycloak server.
    func processSignedKeycloakGroups(signedGroupBlobs: Set<String>, signedGroupDeletions: Set<String>, signedGroupKicks: Set<String>, keycloakCurrentTimestamp: Date, delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) throws -> [KeycloakGroupV2UpdateOutput] {
        
        // Determine the appropriate key to validate the signatures.
        // If we have a serverSignatureVerificationKey, this is the one to use.
        // If not, we use the jwks.
        // At this point, since we should already have called to /me entry point, we expect the serverSignatureVerificationKey to be available.
        
        let jwks: ObvJWKSet
        if let serverSignatureVerificationKey {
            jwks = ObvJWKSet(fromSingleObvJWK: serverSignatureVerificationKey)
        } else {
            assertionFailure("We expect the serverSignatureVerificationKey to be available at this point. In production, continue anyway.")
            jwks = try self.jwks
        }
        
        // Process the signed group informations

        try processSignedGroupDeletions(signedGroupDeletions, validatingSignaturesWith: jwks, delegateManager: delegateManager)
        try processSignedGroupKicks(signedGroupKicks, validatingSignaturesWith: jwks, delegateManager: delegateManager)
        let keycloakGroupV2UpdateOutputs = try processSignedGroupBlobs(signedGroupBlobs, validatingSignaturesWith: jwks, keycloakCurrentTimestamp: keycloakCurrentTimestamp, delegateManager: delegateManager, within: obvContext)
        
        // Save the keycloak timestamp
        
        self.latestGroupUpdateTimestamp = keycloakCurrentTimestamp

        return keycloakGroupV2UpdateOutputs
        
    }

    
    private func processSignedGroupDeletions(_ signedGroupDeletions: Set<String>, validatingSignaturesWith jwks: ObvJWKSet, delegateManager: ObvIdentityDelegateManager) throws {
        
        // Verify the signatures on the signedGroupDeletions and key the payload of group deletions with valid signatures
        
        let payloadsWithValidSignature: [Data] = signedGroupDeletions.compactMap { signedGroupDeletion in
            do {
                return try JWSUtil.verifySignature(jwks: jwks, signature: signedGroupDeletion).payload
            } catch {
                assertionFailure("Invalid signature")
                return nil // In production, filter out this signature
            }
        }
        
        // Parse the payloads to obtain instances of KeycloakGroupDeletionData
        
        let keycloakGroupDeletionDatas: [KeycloakGroupDeletionData] = payloadsWithValidSignature.compactMap({ payload in
            do {
                return try KeycloakGroupDeletionData.jsonDecode(payload)
            } catch {
                assertionFailure("Could not decode data")
                return nil // In production, filter out this data
            }
        })
        
        // For each keycloakGroupDeletionData, delete the associated group (unless it is more recent than the signed deletion)
        
        for keycloakGroupDeletionData in keycloakGroupDeletionDatas {
            
            let groupId = GroupV2.Identifier(groupUID: keycloakGroupDeletionData.groupUid, serverURL: serverURL, category: .keycloak)
            guard let groupV2 = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupId, of: self.managedOwnedIdentity, delegateManager: delegateManager) else {
                // We could not find the group. This happens if we, e.g., updated our identity on the keycloak server.
                continue
            }
            let groupLastModificationTimestamp = groupV2.lastModificationTimestamp
            guard groupLastModificationTimestamp < keycloakGroupDeletionData.timestamp else {
                // If the group is more recent than the signed deletion, do not do anything
                continue
            }
            // group was disbanded, delete it locally
            try groupV2.delete()
            
        }
                
    }
    
    
    private func processSignedGroupKicks(_ signedGroupKicks: Set<String>, validatingSignaturesWith jwks: ObvJWKSet, delegateManager: ObvIdentityDelegateManager) throws {
        
        // Verify the signatures on the signedGroupKicks and key the payload of group deletions with valid signatures
        
        let payloadsWithValidSignature: [Data] = signedGroupKicks.compactMap { signedGroupKick in
            do {
                return try JWSUtil.verifySignature(jwks: jwks, signature: signedGroupKick).payload
            } catch {
                assertionFailure("Invalid signature")
                return nil // In production, filter out this signature
            }
        }

        // Parse the payloads to obtain instances of KeycloakGroupDeletionData
        
        let keycloakGroupMemberKickedDatas: [KeycloakGroupMemberKickedData] = payloadsWithValidSignature.compactMap({ payload in
            do {
                return try KeycloakGroupMemberKickedData.jsonDecode(payload)
            } catch {
                assertionFailure("Could not decode data")
                return nil // In production, filter out this data
            }
        })
        
        // For each keycloakGroupMemberKickedData, delete the associated group (unless it is more recent than the signed deletion, and provided we are the one being kicked)

        for keycloakGroupMemberKickedData in keycloakGroupMemberKickedDatas {
            
            // Verify we are the one being kicked
            guard self.managedOwnedIdentity.ownedCryptoIdentity.getObvCryptoIdentity() == keycloakGroupMemberKickedData.identity else {
                // We are not the one being kicked. This happens if we just updated our identity on a keycloak server.
                continue
            }
            
            let groupId = GroupV2.Identifier(groupUID: keycloakGroupMemberKickedData.groupUid, serverURL: serverURL, category: .keycloak)
            guard let groupV2 = try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupId, of: self.managedOwnedIdentity, delegateManager: delegateManager) else {
                // We could not find the group. It may be an "old kick".
                continue
            }
            let groupLastModificationTimestamp = groupV2.lastModificationTimestamp
            guard groupLastModificationTimestamp < keycloakGroupMemberKickedData.timestamp else {
                // If the group is more recent than the signed kick, do not do anything
                continue
            }
            // we were kicked from the group, delete it locally
            try groupV2.delete()

        }

    }
    
    
    /// Processes the signed group blobs received from the keycloak server. This method filters out blobs with invalid signatures, those that cannot be parsed, etc. It resturns a list of valid groups to be sent back to the protocol manager.
    private func processSignedGroupBlobs(_ signedGroupBlobs: Set<String>, validatingSignaturesWith jwks: ObvJWKSet, keycloakCurrentTimestamp: Date, delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) throws -> [KeycloakGroupV2UpdateOutput] {
        
        // Verify the signatures on the signedGroupBlobs and key the payload of group deletions with valid signatures
        
        let payloadsWithValidSignature: [Data] = signedGroupBlobs.compactMap { signedGroupBlob in
            do {
                return try JWSUtil.verifySignature(jwks: jwks, signature: signedGroupBlob).payload
            } catch {
                assertionFailure("Invalid signature")
                return nil // In production, filter out this signature
            }
        }

        // Parse the payloads to obtain instances of KeycloakGroupBlob
        
        let keycloakGroupBlobs: [KeycloakGroupBlob] = payloadsWithValidSignature.compactMap({ payload in
            do {
                return try KeycloakGroupBlob.jsonDecode(payload)
            } catch {
                assertionFailure("Could not decode data")
                return nil // In production, filter out this data
            }
        })
        
        // Filter out blobs with an outdated signature
        
        let validKeycloakGroupBlobs = keycloakGroupBlobs.filter { keycloakGroupBlob in
            keycloakGroupBlob.timestamp > keycloakCurrentTimestamp.addingTimeInterval(-ObvConstants.keycloakSignatureValidity)
        }
        
        // Create or update keycloak groups on the basis of the valid KeycloakGroupBlobs
                
        var keycloakGroupV2UpdateOutputs = [KeycloakGroupV2UpdateOutput]()
        
        for keycloakGroupBlob in validKeycloakGroupBlobs {
            
            do {
                let keycloakGroupV2UpdateOutput = try ContactGroupV2.createOrUpdateKeycloakContactGroupV2(
                    keycloakGroupBlob: keycloakGroupBlob,
                    serverURL: serverURL,
                    for: self.managedOwnedIdentity,
                    validatingSignaturesWith: jwks,
                    delegateManager: delegateManager,
                    within: obvContext)
                keycloakGroupV2UpdateOutputs += [keycloakGroupV2UpdateOutput]
            } catch {
                if (error as NSError).code == 1 {
                    // This happens when we are not part of the group. This can happen if the blob is not yet updated on keycloak. We will certainly be notified again soon
                } else {
                    throw error
                }
            }
            
        }

        return keycloakGroupV2UpdateOutputs
        
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
                .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
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
            if let obvJWKLegacy = try? ObvJWKLegacy.jsonDecode(rawObvJWKLegacy: rawServerSignatureKey) {
                let obvJWK = obvJWKLegacy.updateToObvJWK()
                self.rawServerSignatureKey = try obvJWK.jsonEncode()
            } else {
                _ = try ObvJWK.jsonDecode(rawObvJWK: rawServerSignatureKey)
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



// MARK: - KeycloakGroupDeletionData


struct KeycloakGroupDeletionData: Decodable, ObvErrorMaker {
    
    let groupUid: UID
    let timestamp: Date

    static let errorDomain = "KeycloakGroupDeletionData"

    enum CodingKeys: String, CodingKey {
        case groupUid = "groupUid"
        case timestamp = "timestamp"
    }

    private init(groupUid: UID, timestamp: Date) {
        self.groupUid = groupUid
        self.timestamp = timestamp
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let groupUid: UID
        do {
            groupUid = try values.decode(UID.self, forKey: .groupUid)
        } catch {
            let groupUidRaw = try values.decode(Data.self, forKey: .groupUid)
            guard let _groupUid = UID(uid: groupUidRaw) else {
                throw Self.makeError(message: "Could get group uid")
            }
            groupUid = _groupUid
        }
        let timestampInMs = try values.decode(Int.self, forKey: .timestamp)
        let timestamp = Date(epochInMs: Int64(timestampInMs))
        self.init(groupUid: groupUid, timestamp: timestamp)
    }

    fileprivate static func jsonDecode(_ data: Data) throws -> KeycloakGroupDeletionData {
        let decoder = JSONDecoder()
        return try decoder.decode(KeycloakGroupDeletionData.self, from: data)
    }

}


// MARK: - KeycloakGroupMemberKickedData


struct KeycloakGroupMemberKickedData: Decodable, ObvErrorMaker {
    
    let groupUid: UID
    let timestamp: Date
    let identity: ObvCryptoIdentity
    
    static let errorDomain = "KeycloakGroupMemberKickedData"

    enum CodingKeys: String, CodingKey {
        case groupUid = "groupUid"
        case timestamp = "timestamp"
        case identity = "identity"
    }

    private init(groupUid: UID, timestamp: Date, identity: ObvCryptoIdentity) {
        self.groupUid = groupUid
        self.timestamp = timestamp
        self.identity = identity
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let groupUidRaw = try values.decode(Data.self, forKey: .groupUid)
        guard let groupUid = UID(uid: groupUidRaw) else {
            throw Self.makeError(message: "Could get group uid")
        }
        let timestampInMs = try values.decode(Int.self, forKey: .timestamp)
        let timestamp = Date(epochInMs: Int64(timestampInMs))
        let rawIdentity = try values.decode(Data.self, forKey: .identity)
        guard let identity = ObvCryptoIdentity(from: rawIdentity) else { assertionFailure(); throw Self.makeError(message: "Could not decode identity") }
        self.init(groupUid: groupUid, timestamp: timestamp, identity: identity)
    }

    fileprivate static func jsonDecode(_ data: Data) throws -> KeycloakGroupMemberKickedData {
        let decoder = JSONDecoder()
        return try decoder.decode(KeycloakGroupMemberKickedData.self, from: data)
    }

}


// MARK: - For snapshot purposes


extension KeycloakServer {

    var snapshotNode: KeycloakServerSnapshotNode {
        return KeycloakServerSnapshotNode(
            serverURL: serverURL,
            clientId: clientId,
            clientSecret: clientSecret,
            keycloakUserId: keycloakUserId,
            selfRevocationTestNonce: selfRevocationTestNonce,
            rawJwks: rawJwks, 
            rawServerSignatureKey: rawServerSignatureKey,
            isTransferRestricted: isTransferRestricted)
    }

}


struct KeycloakServerSnapshotNode: ObvSyncSnapshotNode {
    
    fileprivate let serverURL: URL?
    fileprivate let clientId: String?
    fileprivate let clientSecret: String?
    fileprivate let keycloakUserId: String?
    fileprivate let selfRevocationTestNonce: String?
    fileprivate let rawJwks: Data?
    fileprivate let rawServerSignatureKey: Data?
    fileprivate let isTransferRestricted: Bool?

    let id = Self.generateIdentifier()

    private let domain: Set<CodingKeys>

    private static let defaultDomain = Set(CodingKeys.allCases.filter({ $0 != .domain }))

    
    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        case serverURL = "server_url"
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case keycloakUserId = "keycloak_user_id"
        case selfRevocationTestNonce = "self_revocation_test_nonce"
        case domain = "domain"
        case rawJwks = "jwks"
        case rawServerSignatureKey = "signature_key"
        case isTransferRestricted = "transfer_restricted"
    }

    
    fileprivate init(serverURL: URL, clientId: String, clientSecret: String?, keycloakUserId: String?, selfRevocationTestNonce: String?, rawJwks: Data, rawServerSignatureKey: Data?, isTransferRestricted: Bool?) {
        self.serverURL = serverURL
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.keycloakUserId = keycloakUserId
        self.selfRevocationTestNonce = selfRevocationTestNonce
        self.rawJwks = rawJwks
        self.rawServerSignatureKey = rawServerSignatureKey
        self.domain = Self.defaultDomain
        self.isTransferRestricted = isTransferRestricted
    }

    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(self.serverURL, forKey: .serverURL)
        try container.encodeIfPresent(self.clientId, forKey: .clientId)
        try container.encodeIfPresent(self.clientSecret, forKey: .clientSecret)
        try container.encodeIfPresent(self.keycloakUserId, forKey: .keycloakUserId)
        try container.encodeIfPresent(self.selfRevocationTestNonce, forKey: .selfRevocationTestNonce)
        try container.encodeIfPresent(self.isTransferRestricted, forKey: .isTransferRestricted)
        try container.encode(self.domain, forKey: .domain)
        if let rawJwks {
            let rawJwksAsString = String(data: rawJwks, encoding: .utf8)
            try container.encodeIfPresent(rawJwksAsString, forKey: .rawJwks)
        }
        if let rawServerSignatureKey {
            let rawServerSignatureKeyAsString = String(data: rawServerSignatureKey, encoding: .utf8)
            try container.encodeIfPresent(rawServerSignatureKeyAsString, forKey: .rawServerSignatureKey)
        }
    }
    

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rawKeys = try values.decode(Set<String>.self, forKey: .domain)
        self.domain = Set(rawKeys.compactMap({ CodingKeys(rawValue: $0) }))
        self.serverURL = try values.decodeIfPresent(URL.self, forKey: .serverURL)
        self.clientId = try values.decodeIfPresent(String.self, forKey: .clientId)
        self.keycloakUserId = try values.decodeIfPresent(String.self, forKey: .keycloakUserId)
        self.clientSecret = try values.decodeIfPresent(String.self, forKey: .clientSecret)
        self.selfRevocationTestNonce = try values.decodeIfPresent(String.self, forKey: .selfRevocationTestNonce)
        let rawJwksAsString = try values.decodeIfPresent(String.self, forKey: .rawJwks)
        self.rawJwks = rawJwksAsString?.data(using: .utf8)
        let rawServerSignatureKeyAsString = try values.decodeIfPresent(String.self, forKey: .rawServerSignatureKey)
        self.rawServerSignatureKey = rawServerSignatureKeyAsString?.data(using: .utf8)
        self.isTransferRestricted = try values.decodeIfPresent(Bool.self, forKey: .isTransferRestricted)
    }

    
    func restoreInstance(within obvContext: ObvContext, associations: inout SnapshotNodeManagedObjectAssociations, rawOwnedIdentity: Data) throws {
        
        let mandatoryDomain = Set<CodingKeys>([.serverURL, .clientId, .keycloakUserId, .clientSecret, .rawJwks])
        guard mandatoryDomain.isSubset(of: domain) else {
            assertionFailure()
            throw ObvError.tryingToRestoreIncompleteSnapshot
        }
        
        let keycloakServer = try KeycloakServer(snapshotNode: self, rawOwnedIdentity: rawOwnedIdentity, within: obvContext)
        try associations.associate(keycloakServer, to: self)
    }

    
    func restoreRelationships(associations: SnapshotNodeManagedObjectAssociations, within obvContext: ObvContext) throws {
        // Nothing do to here
    }

    
    enum ObvError: Error {
        case tryingToRestoreIncompleteSnapshot
    }

}
