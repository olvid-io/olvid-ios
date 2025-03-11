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
import ObvTypes
import ObvKeycloakManager
import ObvJWS
import ObvUICoreData


/// Implementations of the `KeycloakManagerDelegate` protocol. Certain method are simply forwarded to the engine, while a few others are handled at the app level.
extension AppManagersHolder: KeycloakManagerDelegate {
    
    // MARK: - KeycloakManagerDelegate forwarded to the engine
    
    func setIsTransferRestricted(to isTransferRestricted: Bool, ownedCryptoId: ObvCryptoId) async throws {
        try await self.obvEngine.setIsTransferRestricted(to: isTransferRestricted, ownedCryptoId: ownedCryptoId)
    }
    
    func bindOwnedIdentityToKeycloak(ownedCryptoId: ObvTypes.ObvCryptoId, keycloakState: ObvTypes.ObvKeycloakState, keycloakUserId: String) async throws {
        try await self.obvEngine.bindOwnedIdentityToKeycloak(ownedCryptoId: ownedCryptoId, keycloakState: keycloakState, keycloakUserId: keycloakUserId)
    }

    func unbindOwnedIdentityFromKeycloak(ownedCryptoId: ObvCryptoId, isUnbindRequestByUser: Bool) async throws(ObvUnbindOwnedIdentityFromKeycloakError) {
        try await self.obvEngine.unbindOwnedIdentityFromKeycloak(ownedCryptoId: ownedCryptoId, isUnbindRequestByUser: isUnbindRequestByUser)
    }
    
    func getManagedOwnedIdentitiesAssociatedWithThePushTopic(_ pushTopic: String) throws -> Set<ObvOwnedIdentity> {
        return try self.obvEngine.getManagedOwnedIdentitiesAssociatedWithThePushTopic(pushTopic)
    }
    
    func getOwnedIdentities(restrictToActive: Bool) throws -> Set<ObvOwnedIdentity> {
        return try self.obvEngine.getOwnedIdentities(restrictToActive: restrictToActive)
    }
    
    func addKeycloakContact(with ownedCryptoId: ObvCryptoId, signedContactDetails: SignedObvKeycloakUserDetails) throws {
        try self.obvEngine.addKeycloakContact(with: ownedCryptoId, signedContactDetails: signedContactDetails)
    }
    
    func getOwnedIdentityKeycloakState(with ownedCryptoId: ObvCryptoId) throws -> (obvKeycloakState: ObvKeycloakState?, signedOwnedDetails: SignedObvKeycloakUserDetails?) {
        return try self.obvEngine.getOwnedIdentityKeycloakState(with: ownedCryptoId)
    }
    
    func setOwnedIdentityKeycloakSignatureKey(ownedCryptoId: ObvCryptoId, keycloakServersignatureVerificationKey: ObvJWK?) throws {
        try self.obvEngine.setOwnedIdentityKeycloakSignatureKey(ownedCryptoId: ownedCryptoId, keycloakServersignatureVerificationKey: keycloakServersignatureVerificationKey)
    }
    
    func getOwnedIdentityKeycloakUserId(with ownedCryptoId: ObvCryptoId) throws -> String? {
        try self.obvEngine.getOwnedIdentityKeycloakUserId(with: ownedCryptoId)
    }
    
    func setOwnedIdentityKeycloakUserId(with ownedCryptoId: ObvCryptoId, userId: String?) throws {
        try self.obvEngine.setOwnedIdentityKeycloakUserId(with: ownedCryptoId, userId: userId)
    }
    
    func getKeycloakAPIKey(ownedCryptoId: ObvCryptoId) async throws -> UUID? {
        try await self.obvEngine.getKeycloakAPIKey(ownedCryptoId: ownedCryptoId)
    }
    
    func registerThenSaveKeycloakAPIKey(ownedCryptoId: ObvCryptoId, apiKey: UUID) async throws {
        try await self.obvEngine.registerThenSaveKeycloakAPIKey(ownedCryptoId: ownedCryptoId, apiKey: apiKey)
    }
    
    func setOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoId: ObvCryptoId, newSelfRevocationTestNonce: String?) throws {
        try self.obvEngine.setOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoId: ownedCryptoId, newSelfRevocationTestNonce: newSelfRevocationTestNonce)
    }
    
    func updateKeycloakRevocationList(ownedCryptoId: ObvCryptoId, latestRevocationListTimestamp: Date, signedRevocations: [String]) throws {
        try self.obvEngine.updateKeycloakRevocationList(ownedCryptoId: ownedCryptoId, latestRevocationListTimestamp: latestRevocationListTimestamp, signedRevocations: signedRevocations)
    }
    
    func updateKeycloakGroups(ownedCryptoId: ObvCryptoId, signedGroupBlobs: Set<String>, signedGroupDeletions: Set<String>, signedGroupKicks: Set<String>, keycloakCurrentTimestamp: Date) throws {
        return try self.obvEngine.updateKeycloakGroups(ownedCryptoId: ownedCryptoId,
                                                       signedGroupBlobs: signedGroupBlobs,
                                                       signedGroupDeletions: signedGroupDeletions,
                                                       signedGroupKicks: signedGroupKicks,
                                                       keycloakCurrentTimestamp: keycloakCurrentTimestamp)
    }
    
    func getOwnedIdentity(with cryptoId: ObvCryptoId) throws -> ObvOwnedIdentity {
        return try self.obvEngine.getOwnedIdentity(with: cryptoId)
    }
    
    func updatePublishedIdentityDetailsOfOwnedIdentity(with ownedCryptoId: ObvCryptoId, with newIdentityDetails: ObvIdentityDetails) async throws {
        try await self.obvEngine.updatePublishedIdentityDetailsOfOwnedIdentity(with: ownedCryptoId, with: newIdentityDetails)
    }
    
    func saveKeycloakJwks(with ownedCryptoId: ObvCryptoId, jwks: ObvJWKSet) throws {
        try self.obvEngine.saveKeycloakJwks(with: ownedCryptoId, jwks: jwks)
    }
    
    func saveKeycloakAuthState(with ownedCryptoId: ObvCryptoId, rawAuthState: Data) async throws {
        try await self.obvEngine.saveKeycloakAuthState(with: ownedCryptoId, rawAuthState: rawAuthState)
    }
    
    func getOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoId: ObvCryptoId) throws -> String? {
        try self.obvEngine.getOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoId: ownedCryptoId)
    }
    
    func isOwnedIdentityKeycloakManaged(_ ownedCryptoId: ObvCryptoId) async throws -> Bool {
        return try await self.obvEngine.isOwnedIdentityKeycloakManaged(ownedCryptoId)
    }

    // MARK: - Not directly implemented by the engine
    
    func userOwnedIdentityWasRevokedByKeycloak(_ ownedCryptoId: ObvCryptoId) async {
        do {
            try await obvEngine.unbindOwnedIdentityFromKeycloak(ownedCryptoId: ownedCryptoId, isUnbindRequestByUser: false)
        } catch {
            assertionFailure()
        }
        ObvMessengerInternalNotification.userOwnedIdentityWasRevokedByKeycloak(ownedCryptoId: ownedCryptoId)
            .postOnDispatchQueue()
    }
    

    func installedOlvidAppIsOutdated(presentingViewController: UIViewController?) {
        ObvMessengerInternalNotification.installedOlvidAppIsOutdated(presentingViewController: nil)
            .postOnDispatchQueue()
    }
    

    func updateKeycloakPushTopicsIfNeeded(ownedCryptoId: ObvCryptoId, pushTopics: Set<String>) async throws {
        try await ObvPushNotificationManager.shared.updateKeycloakPushTopicsIfNeeded(ownedCryptoId: ownedCryptoId, pushTopics: pushTopics)
    }
    
    
    func getOwnedIdentityDisplayName(_ ownedCryptoId: ObvCryptoId) async -> String? {
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else {
                        assertionFailure()
                        return continuation.resume(returning: nil)
                    }
                    return continuation.resume(returning: ownedIdentity.customOrFullDisplayName)
                } catch {
                    assertionFailure()
                    return continuation.resume(returning: nil)
                }
            }
        }
    }
    
}
