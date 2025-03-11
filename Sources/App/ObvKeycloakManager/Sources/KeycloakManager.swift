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
import UIKit
import os.log
import ObvTypes
import AppAuth
import ObvJWS
import OlvidUtils
import ObvAppCoreConstants
import OlvidUtils
import ObvNetworkStatus


@MainActor
public final class KeycloakManagerSingleton {
    
    public static var shared = KeycloakManagerSingleton()

    private init() {
        observeNotifications()
    }
    
        
    private func observeNotifications() {
        Task { [weak self] in
            guard let self else { return }
            await ObvNetworkStatus.shared.addNetworkInterfaceChangeListeners(self)
        }
    }

    
    fileprivate weak var manager: KeycloakManager?
    
    fileprivate func setManager(manager: KeycloakManager?) {
        assert(manager != nil)
        self.manager = manager
    }
    
    
    public func synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ObvCryptoId) async {
        guard let manager = manager else { assertionFailure(); return }
        await manager.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId)
    }

    
    public func setKeycloakSceneDelegate(to newKeycloakSceneDelegate: KeycloakSceneDelegate) async {
        guard let manager = manager else { assertionFailure(); return }
        await manager.setKeycloakSceneDelegate(to: newKeycloakSceneDelegate)
    }
    
    
    /// Called when trying to transfer a profile on this target device in the case where the transfer is restricted:
    /// - the profile is keycloak-managed
    /// - the source device requires this target to prove it is able to authenticate on the keycloak server
    public func userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(keycloakConfiguration: ObvKeycloakConfiguration, transferProofElements: ObvKeycloakTransferProofElements) async throws -> ObvKeycloakTransferProofAndAuthState {
        let (_, configuration) = try await discoverKeycloakServer(for: keycloakConfiguration.keycloakServerURL)
        let authState = try await authenticate(
            configuration: configuration,
            clientId: keycloakConfiguration.clientId,
            clientSecret: keycloakConfiguration.clientSecret,
            ownedCryptoId: nil)
        let proof = try await KeycloakManagerSingleton.shared.getTransferProof(
            keycloakServer: keycloakConfiguration.keycloakServerURL,
            authState: authState,
            transferProofElements: transferProofElements)
        let rawAuthState = try authState.serialize()
        return ObvKeycloakTransferProofAndAuthState(proof: proof, rawAuthState: rawAuthState)
    }
    
    
    @MainActor
    public func resumeExternalUserAgentFlow(with url: URL) async throws -> Bool {
        guard let manager = manager else {
            assertionFailure()
            throw ObvError.theInternalManagerIsNotSet
        }
        return await manager.resumeExternalUserAgentFlow(with: url)
    }
    
    
    public func forceSyncManagedIdentitiesAssociatedWithPushTopics(_ receivedPushTopic: String, failedAttempts: Int = 0) async throws {
        guard let manager = manager else {
            assertionFailure()
            throw ObvError.theInternalManagerIsNotSet
        }
        try await manager.forceSyncManagedIdentitiesAssociatedWithPushTopics(receivedPushTopic)
    }
    
    
    /// Uploads an owned identity on the keycloak server. If `obvKeycloakState` is non-nil, it is used for all authentication purposes.
    /// If `nil`, we request an internal state to the delegate (i.e., the engine). Providing a non-nil state is used during the binding of an owned identity.
    /// It is nil during the onboarding process.
    /// Throws a UploadOwnedIdentityError
    public func uploadOwnIdentity(ownedCryptoId: ObvCryptoId, keycloakUserIdAndState: (keycloakUserId: String, obvKeycloakState: ObvKeycloakState)?) async throws {
        guard let manager = manager else {
            assertionFailure()
            throw ObvError.theInternalManagerIsNotSet
        }
        try await manager.uploadOwnIdentity(ownedCryptoId: ownedCryptoId, keycloakUserIdAndState: keycloakUserIdAndState)
    }


    public func unregisterKeycloakManagedOwnedIdentity(ownedCryptoId: ObvCryptoId) async throws(ObvUnbindOwnedIdentityFromKeycloakError) {
        guard let manager = manager else {
            assertionFailure()
            throw .otherError(ObvError.theInternalManagerIsNotSet)
        }
        try await manager.userRequestedUnregisterKeycloakManagedOwnedIdentity(ownedCryptoId: ownedCryptoId)
    }
    

    public func discoverKeycloakServer(for serverURL: URL) async throws -> (ObvJWKSet, OIDServiceConfiguration) {
        guard let manager = manager else {
            assertionFailure()
            throw ObvError.theInternalManagerIsNotSet
        }
        return try await manager.discoverKeycloakServer(for: serverURL)
    }

    
    public func authenticate(configuration: OIDServiceConfiguration, clientId: String, clientSecret: String?, ownedCryptoId: ObvCryptoId?) async throws -> OIDAuthState {
        guard let manager = manager else {
            assertionFailure()
            throw ObvError.theInternalManagerIsNotSet
        }
        return try await manager.authenticate(configuration: configuration, clientId: clientId, clientSecret: clientSecret, ownedCryptoId: ownedCryptoId)
    }
    
    
    private func getTransferProof(keycloakServer: URL, authState: OIDAuthState, transferProofElements: ObvKeycloakTransferProofElements) async throws -> ObvKeycloakTransferProof {
        guard let manager = manager else {
            assertionFailure()
            throw ObvError.theInternalManagerIsNotSet
        }
        return try await manager.getTransferProof(keycloakServer: keycloakServer, authState: authState, transferProofElements: transferProofElements)
    }
    
    
    /// If the manager is not set, this function throws an `Error`. If any other error occurs, it can be casted to a `GetOwnDetailsError`.
    public func getOwnDetails(keycloakServer: URL, authState: OIDAuthState, clientSecret: String?, jwks: ObvJWKSet, latestLocalRevocationListTimestamp: Date?) async throws -> (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff) {
        guard let manager = manager else {
            assertionFailure()
            throw ObvError.theInternalManagerIsNotSet
        }
        return try await manager.getOwnDetails(keycloakServer: keycloakServer, authState: authState, clientSecret: clientSecret, jwks: jwks, latestLocalRevocationListTimestamp: latestLocalRevocationListTimestamp)
    }
    
    
    /// If the manager is not set, this function throws an `Error`. If any other error occurs, it can be casted to a `KeycloakManager.AddContactError`.
    public func addContact(ownedCryptoId: ObvCryptoId, userIdOrSignedDetails: KeycloakAddContactInfo, userIdentity: Data) async throws {
        guard let manager = manager else {
            assertionFailure()
            throw ObvError.theInternalManagerIsNotSet
        }
        try await manager.addContact(ownedCryptoId: ownedCryptoId, userIdOrSignedDetails: userIdOrSignedDetails, userIdentity: userIdentity)
    }

    
    /// If the manager is not set, this function throws an `Error`. If any other error occurs, it can be casted to a `KeycloakManager.SearchError`.
    public func search(ownedCryptoId: ObvCryptoId, searchQuery: String?) async throws -> (userDetails: [ObvKeycloakUserDetails], numberOfMissingResults: Int) {
        assert(Thread.isMainThread)
        guard let manager else {
            assertionFailure()
            throw ObvError.theInternalManagerIsNotSet
        }
        return try await manager.search(ownedCryptoId: ownedCryptoId, searchQuery: searchQuery)
    }
    
    
    public func syncAllManagedIdentities() async throws {
        assert(Thread.isMainThread)
        guard let manager else {
            assertionFailure()
            throw ObvError.theInternalManagerIsNotSet
        }
        return try await manager.syncAllManagedIdentities(ignoreSynchronizationInterval: true)
    }
    
    
    private func processNetworkInterfaceTypeChangedNotification(isConnected: Bool) async {
        guard isConnected else { return }
        do {
            KeycloakManager.logger.info("🧥🛜 Call to syncAllManagedIdentities as network connexion is available")
            try await manager?.syncAllManagedIdentities(ignoreSynchronizationInterval: false)
            KeycloakManager.logger.info("🧥🛜 Call to syncAllManagedIdentities was successful")
        } catch {
            KeycloakManager.logger.error("🧥🛜 Call to syncAllManagedIdentities failed: %{public}@")
        }
    }
    
}


// MARK: Implementing ObvNetworkInterfaceChangeListener

extension KeycloakManagerSingleton: ObvNetworkInterfaceChangeListener {
    
    /// Called by the `ObvNetworkStatus` singleting when the network interface changes.
    public func networkInterfaceTypeChanged(isConnected: Bool) async {
        await processNetworkInterfaceTypeChangedNotification(isConnected: isConnected)
    }
    
}


// MARK: - Errors

extension KeycloakManagerSingleton {
    
    public enum ObvError: Error {
        case theInternalManagerIsNotSet
        case userCannotUnbindAsTransferIsRestricted
        case keycloakManagerError(error: KeycloakManager.ObvError)
    }
    
}

// MARK: - KeycloakManagerDelegate

public protocol KeycloakManagerDelegate: AnyObject {
    
    // Expected to be implemented by `ObvEngine`
    
    func bindOwnedIdentityToKeycloak(ownedCryptoId: ObvCryptoId, keycloakState: ObvKeycloakState, keycloakUserId: String) async throws
    func unbindOwnedIdentityFromKeycloak(ownedCryptoId: ObvCryptoId, isUnbindRequestByUser: Bool) async throws(ObvTypes.ObvUnbindOwnedIdentityFromKeycloakError)
    func getManagedOwnedIdentitiesAssociatedWithThePushTopic(_ pushTopic: String) async throws -> Set<ObvOwnedIdentity>
    func getOwnedIdentities(restrictToActive: Bool) async throws -> Set<ObvOwnedIdentity>
    func addKeycloakContact(with ownedCryptoId: ObvCryptoId, signedContactDetails: SignedObvKeycloakUserDetails) async throws
    func getOwnedIdentityKeycloakState(with ownedCryptoId: ObvCryptoId) async throws -> (obvKeycloakState: ObvKeycloakState?, signedOwnedDetails: SignedObvKeycloakUserDetails?)
    func setOwnedIdentityKeycloakSignatureKey(ownedCryptoId: ObvCryptoId, keycloakServersignatureVerificationKey: ObvJWK?) async throws
    func getOwnedIdentityKeycloakUserId(with ownedCryptoId: ObvCryptoId) async throws -> String?
    func setOwnedIdentityKeycloakUserId(with ownedCryptoId: ObvCryptoId, userId: String?) async throws
    func getKeycloakAPIKey(ownedCryptoId: ObvCryptoId) async throws -> UUID?
    func registerThenSaveKeycloakAPIKey(ownedCryptoId: ObvCryptoId, apiKey: UUID) async throws
    func setOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoId: ObvCryptoId, newSelfRevocationTestNonce: String?) async throws
    func updateKeycloakRevocationList(ownedCryptoId: ObvCryptoId, latestRevocationListTimestamp: Date, signedRevocations: [String]) async throws
    func updateKeycloakGroups(ownedCryptoId: ObvCryptoId, signedGroupBlobs: Set<String>, signedGroupDeletions: Set<String>, signedGroupKicks: Set<String>, keycloakCurrentTimestamp: Date) async throws
    func getOwnedIdentity(with cryptoId: ObvCryptoId) async throws -> ObvOwnedIdentity
    func updatePublishedIdentityDetailsOfOwnedIdentity(with ownedCryptoId: ObvCryptoId, with newIdentityDetails: ObvIdentityDetails) async throws
    func saveKeycloakJwks(with ownedCryptoId: ObvCryptoId, jwks: ObvJWKSet) async throws
    func saveKeycloakAuthState(with ownedCryptoId: ObvCryptoId, rawAuthState: Data) async throws
    func getOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoId: ObvCryptoId) async throws -> String?
    func setIsTransferRestricted(to isTransferRestricted: Bool, ownedCryptoId: ObvCryptoId) async throws
    func isOwnedIdentityKeycloakManaged(_ ownedCryptoId: ObvCryptoId) async throws -> Bool

    // Expected to be implemented by the app

    func userOwnedIdentityWasRevokedByKeycloak(_ ownedCryptoId: ObvCryptoId) async
    func installedOlvidAppIsOutdated(presentingViewController: UIViewController?) async
    func updateKeycloakPushTopicsIfNeeded(ownedCryptoId: ObvCryptoId, pushTopics: Set<String>) async throws
    func getOwnedIdentityDisplayName(_ ownedCryptoId: ObvCryptoId) async -> String?

}


// MARK: - KeycloakManager

public actor KeycloakManager: NSObject {

    private weak var delegate: KeycloakManagerDelegate?

    
    public func setDelegate(to delegate: KeycloakManagerDelegate) {
        self.delegate = delegate
    }
    
    
    public func performPostInitialization() async {
        await KeycloakManagerSingleton.shared.setManager(manager: self)
    }
    

    private var currentAuthorizationFlow: OIDExternalUserAgentSession?

    private func setCurrentAuthorizationFlow(to newCurrentAuthorizationFlow: OIDExternalUserAgentSession?) {
        self.currentAuthorizationFlow?.cancel()
        self.currentAuthorizationFlow = newCurrentAuthorizationFlow
    }
    
    private static var mePath = "olvid-rest/me"
    private static var putKeyPath = "olvid-rest/putKey"
    private static var getKeyPath = "olvid-rest/getKey"
    private static var searchPath = "olvid-rest/search"
    private static var revocationTestPath = "olvid-rest/revocationTest"
    private static var groupsPath = "olvid-rest/groups"
    private static var transferProofPath = "olvid-rest/transferProof"

    private static let errorDomain = "KeycloakManager"
    fileprivate static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "KeycloakManager")
    static func makeError(message: String) -> Error { NSError(domain: KeycloakManager.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { KeycloakManager.makeError(message: message) }

    private let synchronizationInterval = TimeInterval(hours: 6) // Synchronize with keycloak server every 6 hours
    private var _lastSynchronizationDateForOwnedIdentity = [ObvCryptoId: Date]()
    private let maxFailCount = 5

    // If the signed owned details stored locally are more than 7 days old, we will replace them (and re-publish them) using the signed owned details returned by the server
    private static let signedOwnedDetailsRenewalInterval = TimeInterval(days: 7)

    private func getLastSynchronizationDate(forOwnedIdentity ownedIdentity: ObvCryptoId) -> Date {
        return _lastSynchronizationDateForOwnedIdentity[ownedIdentity] ?? Date.distantPast
    }

    private func setLastSynchronizationDate(forOwnedIdentity ownedIdentity: ObvCryptoId, to date: Date?) {
        if let date = date {
            _lastSynchronizationDateForOwnedIdentity[ownedIdentity] = date
        } else {
            _ = _lastSynchronizationDateForOwnedIdentity.removeValue(forKey: ownedIdentity)
        }
    }

    private let revocationListLatestTimestampOverlap = TimeInterval(hours: 1)
    private let getGroupTimestampOverlap = TimeInterval(hours: 1)
    
    private var currentlySyncingOwnedIdentities = Set<ObvCryptoId>()

    private var ownedCryptoIdForOIDAuthState = [OIDAuthState: ObvCryptoId]()

    weak var keycloakSceneDelegate: KeycloakSceneDelegate?

    private lazy var internalUnderlyingQueue = DispatchQueue(label: "KeycloakManager internal queue", qos: .default)

    fileprivate func setKeycloakSceneDelegate(to newKeycloakSceneDelegate: KeycloakSceneDelegate) {
        self.keycloakSceneDelegate = newKeycloakSceneDelegate
    }

    // MARK: - Public Methods
    
    fileprivate func synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ObvCryptoId) async {
        Self.logger.info("🧥 Call to synchronizeOwnedIdentityWithKeycloakServer")
        await synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: false)
    }


    fileprivate func userRequestedUnregisterKeycloakManagedOwnedIdentity(ownedCryptoId: ObvCryptoId, failedAttempts: Int = 0) async throws(ObvTypes.ObvUnbindOwnedIdentityFromKeycloakError) {
        Self.logger.info("🧥 Call to userRequestedUnregisterKeycloakManagedOwnedIdentity")
        guard let delegate else {
            assertionFailure()
            throw .otherError(ObvError.delegateIsNil)
        }
        do {
            setLastSynchronizationDate(forOwnedIdentity: ownedCryptoId, to: nil)
            try await delegate.unbindOwnedIdentityFromKeycloak(ownedCryptoId: ownedCryptoId, isUnbindRequestByUser: true)
        } catch {
            switch error {
            case .userCannotUnbindAsTransferIsRestricted:
                throw error
            case .otherError(_):
                guard failedAttempts < maxFailCount else {
                    assertionFailure()
                    throw error
                }
                do {
                    try await Task.sleep(failedAttemps: failedAttempts)
                } catch {
                    assertionFailure() // Continue anyway
                }
                try await userRequestedUnregisterKeycloakManagedOwnedIdentity(ownedCryptoId: ownedCryptoId, failedAttempts: failedAttempts + 1)
            }
        }
    }
    

    /// When receiving a silent push notification originated in the keycloak server, we sync the managed owned identity associated with the push topic indicated whithin the infos of the push notification
    func forceSyncManagedIdentitiesAssociatedWithPushTopics(_ receivedPushTopic: String, failedAttempts: Int = 0) async throws {
        Self.logger.info("🧥 Call to syncManagedIdentitiesAssociatedWithPushTopics")
        guard let delegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }
        do {
            let associatedOwnedIdentities = try await delegate.getManagedOwnedIdentitiesAssociatedWithThePushTopic(receivedPushTopic)
            for ownedIdentity in associatedOwnedIdentities {
                await synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedIdentity.cryptoId, ignoreSynchronizationInterval: true)
            }
        } catch {
            guard failedAttempts < maxFailCount else {
                assertionFailure()
                throw error
            }
            try await Task.sleep(failedAttemps: failedAttempts)
            try await forceSyncManagedIdentitiesAssociatedWithPushTopics(receivedPushTopic, failedAttempts: failedAttempts+1)
        }
    }

    
    func syncAllManagedIdentities(failedAttempts: Int = 0, ignoreSynchronizationInterval: Bool) async throws {
        Self.logger.info("🧥 Call to syncAllManagedIdentities")
        guard let delegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }
        do {
            let ownedIdentities = (try await delegate.getOwnedIdentities(restrictToActive: true)).filter({ $0.isKeycloakManaged })
            for ownedIdentity in ownedIdentities {
                await synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedIdentity.cryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval)
            }
        } catch {
            guard failedAttempts < maxFailCount else {
                assertionFailure()
                throw error
            }
            try await Task.sleep(failedAttemps: failedAttempts)
            try await syncAllManagedIdentities(failedAttempts: failedAttempts + 1, ignoreSynchronizationInterval: ignoreSynchronizationInterval)
        }
    }


    /// Throws an UploadOwnedIdentityError. If `obvKeycloakState` is set, we use it. Otherwise we request the internat keycloak state from our delegate
    /// (typicially, returned by the engine).
    fileprivate func uploadOwnIdentity(ownedCryptoId: ObvCryptoId, keycloakUserIdAndState: (keycloakUserId: String, obvKeycloakState: ObvKeycloakState)?) async throws {
        Self.logger.info("🧥 Call to uploadOwnIdentity")
        
        guard let delegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }

        let keycloakServer: URL
        let authState: OIDAuthState
        let iks: InternalKeycloakState?
        
        if let obvKeycloakState = keycloakUserIdAndState?.obvKeycloakState {
            guard let rawAuthState = obvKeycloakState.rawAuthState, let _authState = OIDAuthState.deserialize(from: rawAuthState) else {
                assertionFailure()
                throw ObvError.OIDAuthStateDeserializationFailed
            }
            authState = _authState
            keycloakServer = obvKeycloakState.keycloakServer
            iks = nil
        } else {
            let _iks: InternalKeycloakState
            do {
                _iks = try await getInternalKeycloakState(for: ownedCryptoId)
            } catch {
                throw UploadOwnedIdentityError.unkownError(error)
            }
            authState = _iks.authState
            keycloakServer = _iks.keycloakServer
            iks = _iks
        }

        do {
            try await uploadOwnedIdentity(serverURL: keycloakServer, authState: authState, ownedIdentity: ownedCryptoId)
        } catch let error as UploadOwnedIdentityError {
            switch error {
            case .ownedIdentityWasRevoked:
                throw UploadOwnedIdentityError.ownedIdentityWasRevoked
            case .authenticationRequired:
                do {
                    //ObvDisplayableLogs.shared.log("🧥[OpenKeycloakAuthentication][2]")
                    if let obvKeycloakState = keycloakUserIdAndState?.obvKeycloakState {
                        try await openKeycloakAuthenticationRequiredTokenExpired(obvKeycloakState: obvKeycloakState, ownedCryptoId: ownedCryptoId)
                    } else if let iks {
                        try await openKeycloakAuthenticationRequiredTokenExpired(internalKeycloakState: iks, ownedCryptoId: ownedCryptoId)
                    } else {
                        assertionFailure()
                        throw ObvError.unexpectedError
                    }
                    return try await uploadOwnIdentity(ownedCryptoId: ownedCryptoId, keycloakUserIdAndState: keycloakUserIdAndState)
                } catch let error as KeycloakDialogError {
                    switch error {
                    case .userHasCancelled:
                        throw UploadOwnedIdentityError.userHasCancelled
                    case .keycloakManagerError(let error):
                        throw UploadOwnedIdentityError.unkownError(error)
                    }
                } catch {
                    assertionFailure("Unknown error")
                    throw UploadOwnedIdentityError.unkownError(error)
                }
            case .userHasCancelled:
                throw UploadOwnedIdentityError.userHasCancelled
            case .identityAlreadyUploaded:
                do {
                    try await openKeycloakRevocationForbidden()
                    return
                } catch {
                    assertionFailure("Unexpected error")
                    throw UploadOwnedIdentityError.unkownError(error)
                }
            case .badResponse, .serverError, .unkownError:
                Task {
                    await synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: false)
                }
                throw UploadOwnedIdentityError.unkownError(error)
            }
        }
        
        if let keycloakUserIdAndState {
            try await delegate.bindOwnedIdentityToKeycloak(ownedCryptoId: ownedCryptoId, keycloakState: keycloakUserIdAndState.obvKeycloakState, keycloakUserId: keycloakUserIdAndState.keycloakUserId)
        }
        
        await synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: true)

    }


    /// Throws a SearchError
    fileprivate func search(ownedCryptoId: ObvCryptoId, searchQuery: String?) async throws -> (userDetails: [ObvKeycloakUserDetails], numberOfMissingResults: Int) {
        Self.logger.info("🧥 Call to search")
        
        let iks: InternalKeycloakState
        do {
            iks = try await getInternalKeycloakState(for: ownedCryptoId)
        } catch {
            throw SearchError.unkownError(error)
        }
        
        let searchQueryJSON: SearchQueryJSON
        if let searchQuery = searchQuery {
            searchQueryJSON = SearchQueryJSON(filter: searchQuery.components(separatedBy: .whitespaces))
        } else {
            searchQueryJSON = SearchQueryJSON(filter: [""])
        }
        let encoder = JSONEncoder()
        let dataToSend: Data
        do {
            dataToSend = try encoder.encode(searchQueryJSON)
        } catch {
            throw SearchError.unkownError(error)
        }
        
        let result: KeycloakManager.ApiResultForSearchPath
        do {
            result = try await keycloakApiRequest(serverURL: iks.keycloakServer, path: KeycloakManager.searchPath, accessToken: iks.accessToken, dataToSend: dataToSend)
        } catch let error as KeycloakApiRequestError {
            throw SearchError.keycloakApiRequest(error)
        } catch {
            assertionFailure("Unexpected error")
            throw SearchError.unkownError(error)
        }
        
        if let userDetails = result.userDetails {
            let numberOfMissingResults: Int
            if let numberOfResultsOnServer = result.numberOfResultsOnServer {
                assert(userDetails.count <= numberOfResultsOnServer)
                numberOfMissingResults = max(0, numberOfResultsOnServer - userDetails.count)
            } else {
                numberOfMissingResults = 0
            }
            return (userDetails, numberOfMissingResults)
        } else if let errorCode = result.errorCode, let error = KeycloakApiRequestError(rawValue: errorCode) {
            throw SearchError.keycloakApiRequest(error)
        } else {
            assertionFailure("Unexpected error")
            throw SearchError.unkownError(Self.makeError(message: "Unexpected error"))
        }
    }


    /// Throws a AddContactError
    fileprivate func addContact(ownedCryptoId: ObvCryptoId, userIdOrSignedDetails: KeycloakAddContactInfo, userIdentity: Data) async throws {
        Self.logger.info("🧥 Call to addContact")
        
        guard let delegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }

        let signedUserDetails: SignedObvKeycloakUserDetails
        switch userIdOrSignedDetails {
        case .userId(let userId):
            
            let iks: InternalKeycloakState
            do {
                iks = try await getInternalKeycloakState(for: ownedCryptoId)
            } catch {
                throw AddContactError.unkownError(error)
            }
            
            let addContactJSON = AddContactJSON(userId: userId)
            let encoder = JSONEncoder()
            let dataToSend: Data
            do {
                dataToSend = try encoder.encode(addContactJSON)
            } catch {
                throw AddContactError.unkownError(error)
            }

            let result: KeycloakManager.ApiResultForGetKeyPath
            do {
                result = try await keycloakApiRequest(serverURL: iks.keycloakServer, path: KeycloakManager.getKeyPath, accessToken: iks.accessToken, dataToSend: dataToSend)
            } catch let error as KeycloakApiRequestError {
                switch error {
                case .permissionDenied:
                    throw AddContactError.authenticationRequired
                case .internalError, .invalidRequest, .identityAlreadyUploaded, .badResponse, .decodingFailed:
                    throw AddContactError.badResponse
                case .ownedIdentityWasRevoked:
                    throw AddContactError.ownedIdentityWasRevoked
                }
            } catch {
                assertionFailure("Unexpected error")
                throw AddContactError.unkownError(error)
            }
                    
            do {
                guard let signatureVerificationKey = iks.signatureVerificationKey else {
                    // We did not save the signature key used to sign our own details, se we cannot make sure the details of our future contact are signed with the appropriate key.
                    // We fail and force a resync that will eventually store this server signature verification key
                    Task {
                        setLastSynchronizationDate(forOwnedIdentity: ownedCryptoId, to: nil)
                        currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                        await synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: false, failedAttempts: 0)
                    }
                    throw AddContactError.willSyncKeycloakServerSignatureKey
                }
                // The signature key used to sign our own details is available, we use it to check the details of our future contact
                do {
                    signedUserDetails = try SignedObvKeycloakUserDetails.verifySignedUserDetails(result.signature, with: signatureVerificationKey)
                } catch {
                    // The signature verification failed when using the key used to signed our own details. We check if the signature is valid using the key sent by the server
                    do {
                        _ = try JWSUtil.verifySignature(jwks: iks.jwks, signature: result.signature)
                    } catch {
                        // The signature is definitively invalid, we fail
                        throw AddContactError.invalidSignature(error)
                    }
                    // If we reach this point, the signature is valid but with the wrong signature key --> we force a resync to detect key change and prompt user with a dialog
                    Task {
                        setLastSynchronizationDate(forOwnedIdentity: ownedCryptoId, to: nil)
                        currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                        await synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: false, failedAttempts: 0)
                    }
                    throw AddContactError.willSyncKeycloakServerSignatureKey
                }
            }

            
        case .signedDetails(let signedDetails):
            
            signedUserDetails = signedDetails
            
        }
        
        guard signedUserDetails.identity == userIdentity else {
            throw AddContactError.badResponse
        }
        
        do {
            try await delegate.addKeycloakContact(with: ownedCryptoId, signedContactDetails: signedUserDetails)
        } catch(let error) {
            throw AddContactError.unkownError(error)
        }
        
    }
    

    fileprivate func authenticate(configuration: OIDServiceConfiguration, clientId: String, clientSecret: String?, ownedCryptoId: ObvCryptoId?) async throws -> OIDAuthState {

        Self.logger.info("🧥 Call to authenticate")

        guard let delegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }

        let kRedirectURI = "https://\(ObvAppCoreConstants.Host.forOpenIdRedirect)/"

        guard let redirectURI = URL(string: kRedirectURI) else {
            assertionFailure()
            throw KeycloakManager.makeError(message: "Error creating URL for : \(kRedirectURI)")
        }

        var additionalParameters: [String: String] = [:]
        additionalParameters["prompt"] = "login consent"

        // Builds authentication request
        let request = OIDAuthorizationRequest(configuration: configuration,
                                              clientId: clientId,
                                              clientSecret: clientSecret,
                                              scopes: [OIDScopeOpenID],
                                              redirectURL: redirectURI,
                                              responseType: OIDResponseTypeCode,
                                              additionalParameters: additionalParameters)

        // Performs authentication request
        Self.logger.info("🧥 Initiating authorization request with scope: \(request.scope ?? "DEFAULT_SCOPE")")

        guard let keycloakSceneDelegate = keycloakSceneDelegate else {
            assertionFailure()
            throw KeycloakManager.makeError(message: "The keycloak scene delegate is not set")
        }
        let viewController = try await keycloakSceneDelegate.requestViewControllerForPresenting()

        let storeSession: (OIDExternalUserAgentSession) -> Void = { currentAuthorizationFlow in
            Task { [weak self] in
                await self?.setCurrentAuthorizationFlow(to: currentAuthorizationFlow)
            }
        }
        let authorizationResponse = try await OIDAuthorizationService.present(request, presenting: viewController, storeSession: storeSession)

        Self.logger.info("🧥 OIDAuthorizationService did return")

        let authState: OIDAuthState
        if let ownedCryptoId = ownedCryptoId,
           let keycloakState = try? await delegate.getOwnedIdentityKeycloakState(with: ownedCryptoId).obvKeycloakState,
           let rawAuthState = keycloakState.rawAuthState,
           let _authState = OIDAuthState.deserialize(from: rawAuthState) {
            authState = _authState
            authState.update(with: authorizationResponse, error: nil)
        } else {
            authState = OIDAuthState(authorizationResponse: authorizationResponse)
        }
        self.ownedCryptoIdForOIDAuthState[authState] = ownedCryptoId // It's nil during onboarding
        authState.stateChangeDelegate = self
        
        let tokenRequest = OIDTokenRequest(configuration: request.configuration,
                                           grantType: OIDGrantTypeAuthorizationCode,
                                           authorizationCode: authorizationResponse.authorizationCode,
                                           redirectURL: request.redirectURL,
                                           clientID: request.clientID,
                                           clientSecret: request.clientSecret,
                                           scope: nil,
                                           refreshToken: nil,
                                           codeVerifier: request.codeVerifier,
                                           additionalParameters: nil)
        
        do {
            let tokenResponse = try await OIDAuthorizationService.perform(tokenRequest)
            authState.update(with: tokenResponse, error: nil)
        } catch {
            authState.update(withAuthorizationError: error)
            throw error
        }
        
        return authState
        
    }

    
    fileprivate func discoverKeycloakServer(for serverURL: URL) async throws -> (ObvJWKSet, OIDServiceConfiguration) {

        Self.logger.info("🧥 Call to discoverKeycloakServer")

        let configuration = try await OIDAuthorizationService.discoverConfiguration(forIssuer: serverURL)
        
        guard let discoveryDocument = configuration.discoveryDocument else {
            throw KeycloakManager.makeError(message: "No discovery document available")
        }

        let jwksData = try await getJkws(url: discoveryDocument.jwksURL)
        
        let jwks = try ObvJWKSet(data: jwksData)
        
        return (jwks, configuration)

    }
    
    
    fileprivate func getTransferProof(keycloakServer: URL, authState: OIDAuthState, transferProofElements: ObvKeycloakTransferProofElements) async throws(GetTransferProofError) -> ObvKeycloakTransferProof {
        
        Self.logger.info("🧥 Call to getTransferProof")

        guard let (accessToken, _) = try? await authState.performAction(), let accessToken = accessToken else {
            Self.logger.info("🧥 Authentication required in getTransferProof")
            throw .authenticationRequired
        }

        let dataToSend: Data
        let query = ApiQueryForTransferProof(transferProofElements: transferProofElements)
        do {
            dataToSend = try query.jsonEncode()
        } catch {
            Self.logger.fault("Encoding failed: \(error.localizedDescription)")
            assertionFailure()
            throw .encodingFailed
        }

        let apiResult: KeycloakManager.ApiResultForTransferProofPath
        do {
            apiResult = try await keycloakApiRequest(serverURL: keycloakServer, path: KeycloakManager.transferProofPath, accessToken: accessToken, dataToSend: dataToSend)
        } catch let error as KeycloakApiRequestError {
            switch error {
            case .permissionDenied:
                Self.logger.error("🧥 The keycloak server returned a permission denied error")
                assertionFailure()
                throw .authenticationRequired
            case .internalError:
                Self.logger.error("🧥 The keycloak server returned an internal error")
                assertionFailure()
                throw .serverError
            case .invalidRequest:
                Self.logger.error("🧥 The keycloak server returned an invalidRequest error")
                assertionFailure()
                throw .serverError
            case .identityAlreadyUploaded:
                Self.logger.error("🧥 The keycloak server returned an identityAlreadyUploaded error")
                assertionFailure()
                throw .serverError
            case .ownedIdentityWasRevoked:
                Self.logger.error("🧥 The keycloak server returned an ownedIdentityWasRevoked error")
                assertionFailure()
                throw .ownedIdentityWasRevoked
            case .badResponse:
                Self.logger.error("🧥 The keycloak server returned a badResponse error")
                assertionFailure()
                throw .serverError
            case .decodingFailed:
                Self.logger.error("🧥 The keycloak server returned a decodingFailed error")
                assertionFailure()
                throw .serverError
            }
        } catch {
            assertionFailure("Unexpected error")
            throw .unkownError(error)
        }

        Self.logger.info("🧥 The call to the /transferProof entry point succeeded")

        return ObvKeycloakTransferProof(signature: apiResult.signature)
        
    }

    
    enum GetTransferProofError: Error {
        case authenticationRequired
        case encodingFailed
        case serverError
        case ownedIdentityWasRevoked
        case unkownError(Error)
    }

    /// Throws a GetOwnDetailsError
    fileprivate func getOwnDetails(keycloakServer: URL, authState: OIDAuthState, clientSecret: String?, jwks: ObvJWKSet, latestLocalRevocationListTimestamp: Date?) async throws(GetOwnDetailsError) -> (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff) {
        
        Self.logger.info("🧥 Call to getOwnDetails")
        
        guard let (accessToken, _) = try? await authState.performAction(), let accessToken = accessToken else {
            Self.logger.info("🧥 Authentication required in getOwnDetails")
            throw GetOwnDetailsError.authenticationRequired
        }
        
        let dataToSend: Data?
        if let latestLocalRevocationListTimestamp = latestLocalRevocationListTimestamp {
            let query = ApiQueryForMePath(latestLocalRevocationListTimestamp: latestLocalRevocationListTimestamp)
            do {
                dataToSend = try query.jsonEncode()
            } catch {
                Self.logger.fault("Could not encode latestRevocationListTimestamp: \(error.localizedDescription)")
                assertionFailure()
                dataToSend = nil
            }
        } else {
            dataToSend = nil
        }

        let apiResult: KeycloakManager.ApiResultForMePath
        do {
            apiResult = try await keycloakApiRequest(serverURL: keycloakServer, path: KeycloakManager.mePath, accessToken: accessToken, dataToSend: dataToSend)
        } catch let error as KeycloakApiRequestError {
            switch error {
            case .permissionDenied:
                Self.logger.error("🧥 The keycloak server returned a permission denied error")
                throw GetOwnDetailsError.authenticationRequired
            case .internalError, .invalidRequest, .identityAlreadyUploaded, .badResponse, .decodingFailed:
                Self.logger.error("🧥 The keycloak server returned an error")
                throw GetOwnDetailsError.serverError
            case .ownedIdentityWasRevoked:
                Self.logger.error("🧥 The keycloak server indicates that the owned identity was revoked")
                throw GetOwnDetailsError.ownedIdentityWasRevoked
            }
        } catch {
            assertionFailure("Unexpected error")
            throw GetOwnDetailsError.unkownError(error)
        }
        
        Self.logger.info("🧥 The call to the /me entry point succeeded")

        let keycloakServerSignatureVerificationKey: ObvJWK
        let signedUserDetails: SignedObvKeycloakUserDetails
        do {
            (signedUserDetails, keycloakServerSignatureVerificationKey) = try SignedObvKeycloakUserDetails.verifySignedUserDetails(apiResult.signature, with: jwks)
        } catch {
            Self.logger.error("🧥 The server signature is invalid")
            throw GetOwnDetailsError.invalidSignature(error)
        }

        Self.logger.info("🧥 The server signature is valid")

        let keycloakUserDetailsAndStuff = KeycloakUserDetailsAndStuff(signedUserDetails: signedUserDetails,
                                                                      serverSignatureVerificationKey: keycloakServerSignatureVerificationKey,
                                                                      server: apiResult.server,
                                                                      apiKey: apiResult.apiKey,
                                                                      pushTopics: apiResult.pushTopics,
                                                                      selfRevocationTestNonce: apiResult.selfRevocationTestNonce,
                                                                      isTransferRestricted: apiResult.isTransferRestricted)
        let keycloakServerRevocationsAndStuff = KeycloakServerRevocationsAndStuff(revocationAllowed: apiResult.revocationAllowed,
                                                                                  currentServerTimestamp: apiResult.currentServerTimestamp,
                                                                                  signedRevocations: apiResult.signedRevocations,
                                                                                  minimumIOSBuildVersion: apiResult.minimumIOSBuildVersion)

        Self.logger.info("🧥 Calling the completion of the getOwnDetails method")
        
        return (keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff)
                
    }
    
    
    /// When an error is thrown, it is a GetGroupsError.
    private func getGroups(keycloakServer: URL, authState: OIDAuthState, clientSecret: String?, latestGetGroupsTimestamp: Date?) async throws -> KeycloakManager.ApiResultForGroupsPath {
     
        Self.logger.info("🧥 Call to getGroups")

        guard let (accessToken, _) = try? await authState.performAction(), let accessToken = accessToken else {
            Self.logger.info("🧥 Authentication required in getGroups")
            throw GetGroupsError.authenticationRequired
        }

        let dataToSend: Data?
        if let latestGetGroupsTimestamp = latestGetGroupsTimestamp {
            let query = APIQueryForGroupsPath(latestGetGroupsTimestamp: latestGetGroupsTimestamp)
            do {
                dataToSend = try query.jsonEncode()
            } catch {
                Self.logger.fault("Could not encode APIQueryForGroupsPath: \(error.localizedDescription)")
                assertionFailure()
                dataToSend = nil
            }
        } else {
            dataToSend = nil
        }
        
        let apiResult: KeycloakManager.ApiResultForGroupsPath
        do {
            apiResult = try await keycloakApiRequest(serverURL: keycloakServer, path: KeycloakManager.groupsPath, accessToken: accessToken, dataToSend: dataToSend)
        } catch let error as KeycloakApiRequestError {
            switch error {
            case .permissionDenied:
                Self.logger.error("🧥 The keycloak server returned a permission denied error")
                throw GetGroupsError.authenticationRequired
            case .internalError, .invalidRequest, .identityAlreadyUploaded, .badResponse, .decodingFailed:
                Self.logger.error("🧥 The keycloak server returned an error")
                throw GetGroupsError.serverError
            case .ownedIdentityWasRevoked:
                Self.logger.error("🧥 The keycloak server indicates that the owned identity was revoked")
                throw GetGroupsError.ownedIdentityWasRevoked
            }
        } catch {
            assertionFailure("Unexpected error")
            throw GetGroupsError.unkownError(error)
        }

        return apiResult
        
    }


    /// Called when the user resumes an OpendId connect authentication
    @MainActor
    fileprivate func resumeExternalUserAgentFlow(with url: URL) async -> Bool {
        Self.logger.info("🧥 Resume External Agent flow...")
        assert(Thread.isMainThread)
        if let authorizationFlow = await self.currentAuthorizationFlow, authorizationFlow.resumeExternalUserAgentFlow(with: url) {
            Self.logger.info("🧥 Resume External Agent succeed")
            await setCurrentAuthorizationFlow(to: nil)
            return true
        } else {
            Self.logger.error("🧥 Resume External Agent flow failed")
            return false
        }
    }


    // MARK: - Private Methods and helpers


    private func synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ObvCryptoId, ignoreSynchronizationInterval: Bool, failedAttempts: Int = 0) async {
        
        assert(!Thread.isMainThread)
        
        Self.logger.info("🧥 Call to synchronizeOwnedIdentityWithKeycloakServer")
        
        guard let delegate else {
            assertionFailure()
            return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(
                error: ObvError.delegateIsNil,
                ownedCryptoId: ownedCryptoId,
                ignoreSynchronizationInterval: ignoreSynchronizationInterval,
                currentFailedAttempts: failedAttempts)
        }
        
        guard !currentlySyncingOwnedIdentities.contains(ownedCryptoId) else {
            Self.logger.error("🧥 Trying to sync an owned identity that is already syncing")
            return
        }
        
        // Mark the identity as currently syncing --> un-mark it as soon as success or failure
        
        currentlySyncingOwnedIdentities.insert(ownedCryptoId)
        defer {
            currentlySyncingOwnedIdentities.remove(ownedCryptoId)
        }

        // Make sure the owned identity is still bound to a keycloak server
        
        let ownedIdentityIsKeycloakManaged: Bool
        do {
            ownedIdentityIsKeycloakManaged = try await delegate.isOwnedIdentityKeycloakManaged(ownedCryptoId)
        } catch {
            assertionFailure()
            ownedIdentityIsKeycloakManaged = true
        }
        
        guard ownedIdentityIsKeycloakManaged else {
            Self.logger.info("🧥 The owned identity is not bound to a keycloak server anymore. We cancel the sync process with the server")
            return
        }
            
        let iks: InternalKeycloakState
        do {
            iks = try await getInternalKeycloakState(for: ownedCryptoId)
        } catch let error as GetObvKeycloakStateError {
            switch error {
            case .userHasCancelled:
                return
            case .unkownError(let error):
                return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
            }
        } catch {
            assertionFailure("Unknown error")
            return
        }
        
        let lastSynchronizationDate = getLastSynchronizationDate(forOwnedIdentity: ownedCryptoId)
        
        assert(Date().timeIntervalSince(lastSynchronizationDate) > 0)
        
        let timeIntervalSinceLastSynchronizationDate = Date().timeIntervalSince(lastSynchronizationDate)
        guard timeIntervalSinceLastSynchronizationDate > self.synchronizationInterval || ignoreSynchronizationInterval else {
            Self.logger.info("🧥 No need to sync as the last sync occured \(Int(timeIntervalSinceLastSynchronizationDate)) seconds ago")
            return
        }
        
        // If we reach this point, we should synchronize the owned identity with the keycloak server
        
        let latestLocalRevocationListTimestamp: Date
        if let timestamp = iks.latestRevocationListTimestamp {
            latestLocalRevocationListTimestamp = max(Date.distantPast, timestamp.addingTimeInterval(-revocationListLatestTimestampOverlap))
        } else {
            latestLocalRevocationListTimestamp = Date.distantPast
        }
        
        let (keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff): (KeycloakUserDetailsAndStuff, KeycloakServerRevocationsAndStuff)
        do {
            (keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff) = try await getOwnDetails(keycloakServer: iks.keycloakServer,
                                                                                                       authState: iks.authState,
                                                                                                       clientSecret: iks.clientSecret,
                                                                                                       jwks: iks.jwks,
                                                                                                       latestLocalRevocationListTimestamp: latestLocalRevocationListTimestamp)
        } catch {
            switch error {
            case .authenticationRequired:
                do {
                    //ObvDisplayableLogs.shared.log("🧥[OpenKeycloakAuthentication][3]")
                    try await openKeycloakAuthenticationRequiredTokenExpired(internalKeycloakState: iks, ownedCryptoId: ownedCryptoId)
                    return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                } catch let error as KeycloakDialogError {
                    switch error {
                    case .userHasCancelled:
                        return // Do nothing
                    case .keycloakManagerError(let error):
                        assertionFailure(error.localizedDescription)
                        return
                    }
                } catch {
                    assertionFailure("Unknown error")
                    return
                }
            case .badResponse, .invalidSignature, .serverError, .unkownError:
                return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
            case .ownedIdentityWasRevoked:
                Task { await delegate.userOwnedIdentityWasRevokedByKeycloak(ownedCryptoId) }
                return
            }
        }
        
        Self.logger.info("🧥 Successfully downloaded own details from keycloak server")
        
        // Check that our Olvid version is not outdated
        
        if let minimumBuildVersion = keycloakServerRevocationsAndStuff.minimumIOSBuildVersion {
            if ObvAppCoreConstants.bundleVersionAsInt < minimumBuildVersion {
                await delegate.installedOlvidAppIsOutdated(presentingViewController: nil)
                return
            }
        }

        let userDetailsOnServer = keycloakUserDetailsAndStuff.signedUserDetails.userDetails
        
        // Verify that the signature key matches what is stored, ask for user confirmation otherwise

        do {
            if let signatureVerificationKeyKnownByEngine = iks.signatureVerificationKey {
                
                guard signatureVerificationKeyKnownByEngine == keycloakUserDetailsAndStuff.serverSignatureVerificationKey else {
                    
                    // The server signature key stored within the engine is distinct from one returned by the server.
                    // This is unexpected as the server is not supposed to change signature key as often as he changes his shirt. We ask the user what she want's to do.
                    
                    do {
                        let userAcceptedToUpdateSignatureVerificationKeyKnownByEngine = try await openAppDialogKeycloakSignatureKeyChanged()
                        if userAcceptedToUpdateSignatureVerificationKeyKnownByEngine {
                            do {
                                try await delegate.setOwnedIdentityKeycloakSignatureKey(ownedCryptoId: ownedCryptoId, keycloakServersignatureVerificationKey: keycloakUserDetailsAndStuff.serverSignatureVerificationKey)
                                return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: nil, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                            } catch {
                                Self.logger.fault("🧥 Could not store the keycloak server signature key within the engine (2): \(error.localizedDescription)")
                                return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                            }
                        } else {
                            // The user refused to update the signature key stored within the engine. There is not much we can do...
                            return
                        }
                    } catch {
                        assertionFailure("Unexpected error")
                        return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                    }
                    
                }
                
            } else {
                
                // The engine is not aware of the server signature key, we store it now
                do {
                    try await delegate.setOwnedIdentityKeycloakSignatureKey(ownedCryptoId: ownedCryptoId, keycloakServersignatureVerificationKey: keycloakUserDetailsAndStuff.serverSignatureVerificationKey)
                } catch {
                    Self.logger.fault("🧥 Could not store the keycloak server signature key within the engine: \(error.localizedDescription)")
                    return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                }
                
                // If we reach this point, the signature key has been stored within the engine, we can continue
                
            }
        }
        
        // If we reach this point, the engine is aware of the server signature key, and stores exactly the same value as the one just returned
        Self.logger.info("🧥 The server signature verification key matches the one stored locally")
        
        // We synchronise the UserId
        
        let previousUserId: String?
        do {
            previousUserId = try await delegate.getOwnedIdentityKeycloakUserId(with: ownedCryptoId)
        } catch {
            Self.logger.fault("🧥 Could not get Keycloak UserId of owned identity: \(error.localizedDescription)")
            return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
        }
        
        if let previousUserId = previousUserId {
            // There was a previous UserId. If it is identical to the one returned by the keycloak server, no problem. Otherwise, we have work to do before retrying to synchronize
            guard previousUserId == userDetailsOnServer.id else {
                // The userId changed on keycloak --> probably an authentication with the wrong login check the identity and only update id locally if the identity is the same
                if ownedCryptoId.getIdentity() == userDetailsOnServer.identity {
                    do {
                        try await delegate.setOwnedIdentityKeycloakUserId(with: ownedCryptoId, userId: userDetailsOnServer.id)
                        return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: nil, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                    } catch {
                        Self.logger.fault("🧥 Coult not set the new user id within the engine: \(error.localizedDescription)")
                        return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                    }
                } else {
                    do {
                        try await openKeycloakAuthenticationRequiredUserIdChanged(internalKeycloakState: iks, ownedCryptoId: ownedCryptoId)
                        return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: nil, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                    } catch let error as KeycloakDialogError {
                        switch error {
                        case .userHasCancelled:
                            return // Do nothing
                        case .keycloakManagerError(let error):
                            assertionFailure(error.localizedDescription)
                            return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                        }
                    } catch {
                        assertionFailure("Unknown error")
                        return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                    }
                }
            }
        } else {
            // No previous user Id. We can save the one just returned by the keycloak server
            do {
                try await delegate.setOwnedIdentityKeycloakUserId(with: ownedCryptoId, userId: userDetailsOnServer.id)
            } catch {
                Self.logger.fault("🧥 Coult not set the new user id within the engine: \(error.localizedDescription)")
                return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
            }
        }
        
        // If we reach this point, the clientId are identical on the server and on this device
        // If the owned olvid identity was never uploaded, we do it now.
        
        guard let identityOnServer = userDetailsOnServer.identity, let cryptoIdOnServer = try? ObvCryptoId(identity: identityOnServer) else {

            // Upload the owned olvid identity
            
            do {
                try await uploadOwnedIdentity(serverURL: iks.keycloakServer, authState: iks.authState, ownedIdentity: ownedCryptoId)
            } catch let error as UploadOwnedIdentityError {
                switch error {
                case .ownedIdentityWasRevoked:
                    await delegate.userOwnedIdentityWasRevokedByKeycloak(ownedCryptoId)
                    return
                case .userHasCancelled:
                    break // Do nothing
                case .authenticationRequired:
                    do {
                        //ObvDisplayableLogs.shared.log("🧥[OpenKeycloakAuthentication][4]")
                        try await openKeycloakAuthenticationRequiredTokenExpired(internalKeycloakState: iks, ownedCryptoId: ownedCryptoId)
                        return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                    } catch let error as KeycloakDialogError {
                        switch error {
                        case .userHasCancelled:
                            return // Do nothing
                        case .keycloakManagerError(let error):
                            return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                        }
                    } catch {
                        assertionFailure("Unknown error")
                        return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                    }
                case .serverError, .badResponse, .identityAlreadyUploaded, .unkownError:
                    return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                }
            } catch {
                assertionFailure("Unknown error")
                return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
            }
            
            // We uploaded our own key --> re-sync
            
            return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: nil, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: 0)

        }
        
        // If we reach this point, there is an identity on the server. We make sure it is the correct one.
        
        guard cryptoIdOnServer == ownedCryptoId else {
            // The olvid identity on the server does not match the one on this device. The old one should be revoked.
            if !keycloakServerRevocationsAndStuff.revocationAllowed {
                do {
                    try await openKeycloakRevocationForbidden()
                    return
                } catch {
                    assertionFailure("Unexpected error")
                    return
                }
            } else {

                do {
                    try await openKeycloakRevocation(serverURL: iks.keycloakServer, authState: iks.authState, ownedCryptoId: ownedCryptoId)
                    return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: nil, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: 0)
                } catch let error as KeycloakDialogError {
                    switch error {
                    case .userHasCancelled:
                        return // Do nothing
                    case .keycloakManagerError(let error):
                        return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                    }
                } catch {
                    assertionFailure("Unknown error")
                    return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                }
            }
        }
        
        // If we reach this point, the owned identity on the server matches the one stored locally.
        
        // We make sure the engine knows about the signed details returned by the keycloak server. If not, we update our local details
        
        guard let localSignedOwnedDetails = iks.signedOwnedDetails else {
            Self.logger.info("🧥 We do not have signed owned details locally, we store the ones returned by the keycloak server now.")
            // The engine is not aware of the signed details from the keycloak server, so we store them now
            do {
                try await updatePublishedIdentityDetailsOfOwnedIdentityUsingKeycloakInformations(ownedCryptoId: ownedCryptoId, keycloakUserDetailsAndStuff: keycloakUserDetailsAndStuff)
                return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: nil, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: 0)
            } catch {
                return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
            }
        }

        // If we reach this point, the server returned signed owned details, and the engine knows about signed owned details as well.
        // We must compare them to make sure they match. If the signature was have on our owned details is too old, we store/publish the one we just received.
        guard localSignedOwnedDetails.identical(to: keycloakUserDetailsAndStuff.signedUserDetails, acceptableTimestampsDifference: KeycloakManager.signedOwnedDetailsRenewalInterval) else {
            Self.logger.info("🧥 The owned identity core details returned by the server differ from the ones stored locally. We update the local details.")
            // The details on the server differ from the one stored on device. We should update them locally.
            do {
                try await updatePublishedIdentityDetailsOfOwnedIdentityUsingKeycloakInformations(ownedCryptoId: ownedCryptoId, keycloakUserDetailsAndStuff: keycloakUserDetailsAndStuff)
                return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: nil, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: 0)
            } catch {
                return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
            }
        }

        // If we reach this point, the details on the server are identical to the ones stored locally.
        // We update the current API key if needed
        
        let apiKey: UUID?
        do {
            apiKey = try await delegate.getKeycloakAPIKey(ownedCryptoId: ownedCryptoId)
        } catch {
            Self.logger.fault("🧥 Could not retrieve the current API key from the owned identity: \(error.localizedDescription)")
            return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
        }

        if let apiKeyOnServer = keycloakUserDetailsAndStuff.apiKey {
            guard apiKey == apiKeyOnServer else {
                // The api key returned by the server differs from the one store locally. We update the local key
                do {
                    _ = try await delegate.registerThenSaveKeycloakAPIKey(ownedCryptoId: ownedCryptoId, apiKey: apiKeyOnServer)
                    return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: nil, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: 0)
                } catch {
                    Self.logger.fault("🧥 Could not update the local API key with the new one returned by the server.")
                    return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                }
            }
        }

        // If we reach this point, the API key stored locally is ok.
        
        // We update the Keycloak push topics stored within the engine
        
        do {
            try await delegate.updateKeycloakPushTopicsIfNeeded(ownedCryptoId: ownedCryptoId, pushTopics: keycloakUserDetailsAndStuff.pushTopics)
        } catch {
            Self.logger.fault("🧥 Could not update the engine using the push topics returned by the server.")
            return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
        }

        // If we reach this point, we managed to pass the push topics to the engine
        
        // We reset the self revocation test nonce stored within the engine
        
        do {
            try await delegate.setOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoId: ownedCryptoId, newSelfRevocationTestNonce: keycloakUserDetailsAndStuff.selfRevocationTestNonce)
        } catch {
            Self.logger.fault("🧥 Could not update the self revocation test nonce using the nonce returned by the server.")
            return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
        }

        // If we reach this point, we successfully reset the self revocation test nonce stored within the engine
        
        // Update revocation list and latest revocation list timestamp iff the server returned signed revocations (an empty list is ok) and a current server timestamp
        
        if let signedRevocations = keycloakServerRevocationsAndStuff.signedRevocations, let currentServerTimestamp = keycloakServerRevocationsAndStuff.currentServerTimestamp {
            Self.logger.info("🧥 The server returned \(signedRevocations.count) signed revocations, we update the engine now")
            do {
                try await delegate.updateKeycloakRevocationList(ownedCryptoId: ownedCryptoId,
                                                                latestRevocationListTimestamp: currentServerTimestamp,
                                                                signedRevocations: signedRevocations)
            } catch {
                Self.logger.fault("🧥 Could not update the keycloak revocation list: \(error.localizedDescription)")
                return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
            }
            Self.logger.info("🧥 The engine was updated using the the revocations returned by the server")
        }
        
        // Update the isTransferRestricted Boolean within the engine
        
        do {
            try await delegate.setIsTransferRestricted(to: keycloakUserDetailsAndStuff.isTransferRestricted, ownedCryptoId: ownedCryptoId)
        } catch {
            KeycloakManager.logger.fault("Could not update the isTransferRestricted value within the engine: \(error.localizedDescription)")
            assertionFailure()
            // Continue anyway
        }
        
        // Request keycloak groups
        
        Self.logger.info("🧥 About to synchronize keycloak groups")
        
        let apiResultForGroupsPath: KeycloakManager.ApiResultForGroupsPath
        do {
            let latestGetGroupsTimestamp: Date
            if let timestamp = iks.latestGroupUpdateTimestamp {
                latestGetGroupsTimestamp = max(Date.distantPast, timestamp.addingTimeInterval(-getGroupTimestampOverlap))
            } else {
                latestGetGroupsTimestamp = Date.distantPast
            }
            apiResultForGroupsPath = try await getGroups(keycloakServer: iks.keycloakServer, authState: iks.authState, clientSecret: iks.clientSecret, latestGetGroupsTimestamp: latestGetGroupsTimestamp)
        } catch let error as GetGroupsError {
            switch error {
            case .authenticationRequired:
                do {
                    //ObvDisplayableLogs.shared.log("🧥[OpenKeycloakAuthentication][5]")
                    try await openKeycloakAuthenticationRequiredTokenExpired(internalKeycloakState: iks, ownedCryptoId: ownedCryptoId)
                    return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                } catch let error as KeycloakDialogError {
                    switch error {
                    case .userHasCancelled:
                        return // Do nothing
                    case .keycloakManagerError(let error):
                        assertionFailure(error.localizedDescription)
                        return
                    }
                } catch {
                    assertionFailure("Unknown error")
                    return
                }
            case .serverError, .unkownError:
                return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
            case .ownedIdentityWasRevoked:
                Task { await delegate.userOwnedIdentityWasRevokedByKeycloak(ownedCryptoId) }
                return
            }
        } catch {
            assertionFailure("Unknown error")
            return
        }
                
        // Transfer keycloak groups to the engine
        
        do {
            try await delegate.updateKeycloakGroups(ownedCryptoId: ownedCryptoId,
                                                    signedGroupBlobs: apiResultForGroupsPath.signedGroupBlobs,
                                                    signedGroupDeletions: apiResultForGroupsPath.signedGroupDeletions,
                                                    signedGroupKicks: apiResultForGroupsPath.signedGroupKicks,
                                                    keycloakCurrentTimestamp: apiResultForGroupsPath.currentServerTimestamp)
        } catch {
            Self.logger.fault("🧥 Could not update keycloak groups: \(error.localizedDescription)")
            assertionFailure()
            return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
        }
                
        // We are done with the sync !!! We can update the sync timestamp
        
        Self.logger.info("🧥 Keycloak server synchronization succeeded!")
        setLastSynchronizationDate(forOwnedIdentity: ownedCryptoId, to: Date())
        
        Task { [weak self] in
            guard let _self = self else { return }
            do {
                try await Task.sleep(seconds: _self.synchronizationInterval + 10)
            } catch {
                assertionFailure("Unexpected error")
                return
            }
            // Although it is very unlikely that the view controller still exist, we try to resync anyway
            await self?.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval)
        }

    }


    /// Exclusively called from `synchronizeOwnedIdentityWithKeycloakServer` when an error occurs in that method.
    private func retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: Error?, ownedCryptoId: ObvCryptoId, ignoreSynchronizationInterval: Bool, currentFailedAttempts: Int) async {

        guard currentFailedAttempts < self.maxFailCount else {
            currentlySyncingOwnedIdentities.remove(ownedCryptoId)
            //assertionFailure("Unexpected error. This also happens when the keycloak cannot be reached. When testing this scenario, this line can be commented out.")
            return
        }

        do {
            try await Task.sleep(failedAttemps: currentFailedAttempts)
        } catch {
            assertionFailure("Unexpected error")
            return
        }

        currentlySyncingOwnedIdentities.remove(ownedCryptoId)
        await synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, failedAttempts: currentFailedAttempts + 1)

    }


    /// Exclusively called from `synchronizeOwnedIdentityWithKeycloakServer` when we need to update the local owned details using information returned by the keycloak server
    private func updatePublishedIdentityDetailsOfOwnedIdentityUsingKeycloakInformations(ownedCryptoId: ObvCryptoId, keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff) async throws {
        
        guard let delegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }
        
        let obvOwnedIdentity: ObvOwnedIdentity
        do {
            obvOwnedIdentity = try await delegate.getOwnedIdentity(with: ownedCryptoId)
        } catch {
            Self.logger.fault("🧥 Could not get the ObvOwnedIdentity from the engine: \(error.localizedDescription)")
            assertionFailure()
            throw error
        }
        let coreDetailsOnServer: ObvIdentityCoreDetails
        do {
            coreDetailsOnServer = try keycloakUserDetailsAndStuff.getObvIdentityCoreDetails()
        } catch {
            Self.logger.fault("🧥 Could not get owned core details returned by server: \(error.localizedDescription)")
            assertionFailure()
            throw error
        }
        // We use the core details from the server, but keep the local photo URL
        let updatedIdentityDetails = ObvIdentityDetails(coreDetails: coreDetailsOnServer, photoURL: obvOwnedIdentity.currentIdentityDetails.photoURL)
        do {
            try await delegate.updatePublishedIdentityDetailsOfOwnedIdentity(with: ownedCryptoId, with: updatedIdentityDetails)
        } catch {
            Self.logger.fault("🧥 Could not updated published identity details of owned identity: \(error.localizedDescription)")
            assertionFailure()
            throw error
        }
    }


    /// Throws a GetObvKeycloakStateError
    private func getInternalKeycloakState(for ownedCryptoId: ObvCryptoId, failedAttempts: Int = 0) async throws -> InternalKeycloakState {

        guard let delegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }
        
        let obvKeycloakState: ObvKeycloakState
        let signedOwnedDetails: SignedObvKeycloakUserDetails?
        do {
            let (_obvKeycloakState, _signedOwnedDetails) = try await delegate.getOwnedIdentityKeycloakState(with: ownedCryptoId)
            guard let _obvKeycloakState = _obvKeycloakState else {
                Self.logger.fault("🧥 Could not find keycloak state for owned identity. This happens if the user was unbound from a keycloak server.")
                throw Self.makeError(message: "🧥 Could not find keycloak state for owned identity. This happens if the user was unbound from a keycloak server.")
            }
            obvKeycloakState = _obvKeycloakState
            signedOwnedDetails = _signedOwnedDetails
        } catch {
            Self.logger.fault("🧥 Could not recover keycloak state for owned identity: \(error.localizedDescription)")
            guard failedAttempts < maxFailCount else {
                throw GetObvKeycloakStateError.unkownError(error)
            }
            try await Task.sleep(failedAttemps: failedAttempts)
            return try await getInternalKeycloakState(for: ownedCryptoId, failedAttempts: failedAttempts + 1)
        }

        do {
            
            guard let rawAuthState = obvKeycloakState.rawAuthState,
                  let authState = OIDAuthState.deserialize(from: rawAuthState),
                  let accessToken = try await authState.performAction().accessToken else {
                
                do {
                    //ObvDisplayableLogs.shared.log("🧥[OpenKeycloakAuthentication][1] \(String(describing: obvKeycloakState.rawAuthState))")
                    try await openKeycloakAuthenticationRequiredTokenExpired(obvKeycloakState: obvKeycloakState, ownedCryptoId: ownedCryptoId)
                } catch let error as KeycloakDialogError {
                    switch error {
                    case .userHasCancelled:
                        throw GetObvKeycloakStateError.userHasCancelled
                    case .keycloakManagerError(let error):
                        throw GetObvKeycloakStateError.unkownError(error)
                    }
                    
                } catch {
                    
                    //assertionFailure("Unexpected error. This also happens when the keycloak cannot be reached. When testing this scenario, this line can be commented out.")
                    throw GetObvKeycloakStateError.unkownError(error)
                    
                }
                
                guard failedAttempts < maxFailCount else {
                    assertionFailure()
                    throw GetObvKeycloakStateError.unkownError(Self.makeError(message: "Too many requests"))
                }
                try await Task.sleep(failedAttemps: failedAttempts)
                
                return try await getInternalKeycloakState(for: ownedCryptoId, failedAttempts: failedAttempts + 1)
            }
            
            let internalKeycloakState = InternalKeycloakState(keycloakServer: obvKeycloakState.keycloakServer,
                                                              clientId: obvKeycloakState.clientId,
                                                              clientSecret: obvKeycloakState.clientSecret,
                                                              jwks: obvKeycloakState.jwks,
                                                              authState: authState,
                                                              signatureVerificationKey: obvKeycloakState.signatureVerificationKey,
                                                              accessToken: accessToken,
                                                              latestGroupUpdateTimestamp: obvKeycloakState.latestGroupUpdateTimestamp,
                                                              latestRevocationListTimestamp: obvKeycloakState.latestLocalRevocationListTimestamp,
                                                              signedOwnedDetails: signedOwnedDetails)
            
            return internalKeycloakState
            
        } catch {
            
            if error is GetObvKeycloakStateError {
                throw error
            } else {
                throw GetObvKeycloakStateError.unkownError(error)
            }
            
        }
        
    }


    private func getJkws(url: URL) async throws -> Data {
        Self.logger.info("🧥 Call to getJkws")
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }


    private func discoverKeycloakServerAndSaveJWKSet(for serverURL: URL, ownedCryptoId: ObvCryptoId) async throws -> (ObvJWKSet, OIDServiceConfiguration) {
        Self.logger.info("🧥 Call to discoverKeycloakServerAndSaveJWKSet")
        
        guard let delegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }
        
        let (jwks, configuration) = try await discoverKeycloakServer(for: serverURL)
        // Save the jwks in DB
        do {
            try await delegate.saveKeycloakJwks(with: ownedCryptoId, jwks: jwks)
        } catch {
            throw Self.makeError(message: "Cannot save JWKSet")
        }
        return (jwks, configuration)
    }


    /// Throws an UploadOwnedIdentityError
    private func uploadOwnedIdentity(serverURL: URL, authState: OIDAuthState, ownedIdentity: ObvCryptoId) async throws {
        Self.logger.info("🧥 Call to uploadOwnedIdentity")
        
        let (accessToken, _) = try await authState.performAction()
        
        guard let accessToken = accessToken else {
            throw UploadOwnedIdentityError.authenticationRequired
        }

        let uploadOwnedIdentityJSON = UploadOwnedIdentityJSON(identity: ownedIdentity.getIdentity())
        let encoder = JSONEncoder()
        let dataToSend: Data
        do {
            dataToSend = try encoder.encode(uploadOwnedIdentityJSON)
        } catch(let error) {
            throw UploadOwnedIdentityError.unkownError(error)
        }
        
        do {
            let _: ApiResultForPutKeyPath = try await keycloakApiRequest(serverURL: serverURL, path: KeycloakManager.putKeyPath, accessToken: accessToken, dataToSend: dataToSend)
        } catch let error as KeycloakApiRequestError {
            switch error {
            case .internalError, .permissionDenied, .invalidRequest, .badResponse, .decodingFailed:
                throw UploadOwnedIdentityError.serverError
            case .identityAlreadyUploaded:
                throw UploadOwnedIdentityError.identityAlreadyUploaded
            case .ownedIdentityWasRevoked:
                throw UploadOwnedIdentityError.ownedIdentityWasRevoked
            }
        } catch {
            assertionFailure("Unknown error")
            throw UploadOwnedIdentityError.unkownError(error)
        }
    }


    // MARK: - Special types and Errors definitions

    enum GetOwnDetailsError: Error {
        case authenticationRequired
        case serverError
        case badResponse
        case ownedIdentityWasRevoked
        case invalidSignature(_: Error)
        case unkownError(_: Error)
    }
    
    
    enum GetGroupsError: Error {
        case authenticationRequired
        case serverError
        case ownedIdentityWasRevoked
        case unkownError(_: Error)
    }


    public enum UploadOwnedIdentityError: Error {
        case authenticationRequired
        case serverError
        case badResponse
        case identityAlreadyUploaded
        case ownedIdentityWasRevoked
        case userHasCancelled
        case unkownError(Error)
    }


    public enum SearchError: Error {
        case authenticationRequired
        case ownedIdentityNotManaged
        case userHasCancelled
        case keycloakApiRequest(_: Error)
        case unkownError(_: Error)
    }


    public enum AddContactError: Error {
        case authenticationRequired
        case ownedIdentityNotManaged
        case badResponse
        case ownedIdentityWasRevoked
        case userHasCancelled
        case keycloakApiRequest(_: Error)
        case invalidSignature(_: Error)
        case unkownError(_: Error? = nil)
        case willSyncKeycloakServerSignatureKey // Should not display an alert in that case
    }

    enum GetObvKeycloakStateError: Error {
        case userHasCancelled
        case unkownError(_: Error)
    }

    private struct UploadOwnedIdentityJSON: Encodable {
        let identity: Data
    }


    private struct SearchQueryJSON: Encodable {
        let filter: [String]?
    }


    private struct AddContactJSON: Encodable {
        let userId: String
        enum CodingKeys: String, CodingKey {
            case userId = "user-id"
        }
    }

    private struct SelfRevocationTestJSON: Encodable {
        let selfRevocationTestNonce: String
        enum CodingKeys: String, CodingKey {
            case selfRevocationTestNonce = "nonce"
        }
    }

    // MARK: - Keycloak Api Request

    private enum KeycloakApiRequestError: Int, Error {
        case internalError = 1           // Can be sent by the keycloak server
        case permissionDenied = 2        // Can be sent by the keycloak server
        case invalidRequest = 3          // Can be sent by the keycloak server
        case identityAlreadyUploaded = 4 // Can be sent by the keycloak server
        case ownedIdentityWasRevoked = 6 // Can be sent by the keycloak server (the 5th code should never be received by the app)
        case badResponse = -1
        case decodingFailed = -2
    }

    
    // MARK: - Errors
    
    public enum ObvError: Error {
        case delegateIsNil
        case userCannotUnbindAsTransferIsRestricted
        case OIDAuthStateDeserializationFailed
        case unexpectedError
        case maxFailedAttempsReached(error: Error)
    }
    

    // Throws a KeycloakApiRequestError
    private func keycloakApiRequest<T: KeycloakManagerApiResult>(serverURL: URL, path: String, accessToken: String?, dataToSend: Data?) async throws -> T {

        Self.logger.info("🧥 Call to keycloakApiRequest for path: \(path)")

        let url = serverURL.appendingPathComponent(path)

        let sessionConfig = URLSessionConfiguration.ephemeral
        if let accessToken = accessToken {
            sessionConfig.httpAdditionalHeaders = ["Authorization": "Bearer " + accessToken]
        }
        let urlSession = URLSession(configuration: sessionConfig)

        var urlRequest = URLRequest(url: url, timeoutInterval: 10.5)
        if dataToSend != nil {
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let task = urlSession.uploadTask(with: urlRequest, from: dataToSend ?? Data()) { (data, response, error) in
                guard error == nil else {
                    Self.logger.error("🧥 Call to keycloakApiRequest for path %{public}@ failed: \(error!.localizedDescription)")
                    continuation.resume(throwing: KeycloakApiRequestError.invalidRequest)
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    Self.logger.error("🧥 Call to keycloakApiRequest for path \(path) failed (status code is not 200)")
                    continuation.resume(throwing: KeycloakApiRequestError.invalidRequest)
                    return
                }
                guard let data = data else {
                    Self.logger.error("🧥 Call to keycloakApiRequest for path \(path) failed: the keycloak server returned no data")
                    continuation.resume(throwing: KeycloakApiRequestError.invalidRequest)
                    return
                }
                if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any], let error = json[OIDOAuthErrorFieldError] as? Int {
                    if let ktError = KeycloakApiRequestError(rawValue: error) {
                        Self.logger.error("🧥 Call to keycloakApiRequest for path \(path) failed: ktError is \(ktError.localizedDescription)")
                        continuation.resume(throwing: ktError)
                        return
                    } else {
                        Self.logger.error("🧥 Call to keycloakApiRequest for path \(path) failed: decoding failed (1)")
                        continuation.resume(throwing: KeycloakApiRequestError.decodingFailed)
                        return
                    }
                }
                let decodedData: T
                do {
                    decodedData = try T.decode(data)
                } catch {
                    Self.logger.error("🧥 Call to keycloakApiRequest for path \(path) failed: decoding failed (2)")
                    continuation.resume(throwing: KeycloakApiRequestError.decodingFailed)
                    return
                }
                Self.logger.info("🧥 Call to keycloakApiRequest for path \(path) succeeded")
                continuation.resume(returning: decodedData)
                return
            }
            task.resume()
        }
    }
    
}


// MARK: - OIDAuthStateChangeDelegate

extension KeycloakManager: OIDAuthStateChangeDelegate {

    nonisolated public func didChange(_ state: OIDAuthState) {
        Task {
            guard let delegate = await delegate else {
                assertionFailure()
                return
            }
            guard let ownedCryptoId = await ownedCryptoIdForOIDAuthState[state] else {
                // This happens during onboarding, when the owned identity is not created yet
                return
            }
            do {
                let rawAuthState = try state.serialize()
                try await delegate.saveKeycloakAuthState(with: ownedCryptoId, rawAuthState: rawAuthState)
            } catch {
                Self.logger.fault("🧥 Could not save authState: \(error.localizedDescription)")
                assertionFailure()
                return
            }
            Self.logger.info("🧥 OIDAuthState saved")
        }
    }

}


// MARK: - A few extensions

extension OIDAuthState {

    public func serialize() throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: true)
    }

    static func deserialize(from data: Data) -> OIDAuthState? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = false
        return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? OIDAuthState
    }

}

extension ObvKeycloakUserDetails {

    public var firstNameAndLastName: String {
        guard let coreDetails = try? ObvIdentityCoreDetails(firstName: firstName, lastName: lastName, company: company, position: position, signedUserDetails: nil) else { return "" }
        return coreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
    }
    
}


// MARK: - User dialog

extension KeycloakManager {

    enum KeycloakDialogError: Error {
        case userHasCancelled
        case keycloakManagerError(_: Error)
    }

    /// This method is shared by the two methods called when the user needs to authenticate. This happens when the token expires and when the user id changes.
    /// Throws a KeycloakDialogError.
    private func selfTestAndOpenKeycloakAuthenticationRequired(serverURL: URL, clientId: String, clientSecret: String?, ownedCryptoId: ObvCryptoId, title: String, message: String) async throws {
        Self.logger.info("🧥 Call to selfTestAndOpenKeycloakAuthenticationRequired")

        guard let delegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }
        
        // Before authenticating, we test whether we have been revoked by the keycloak server

        guard let selfRevocationTestNonceFromEngine = try await delegate.getOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoId: ownedCryptoId) else {
            
            // If reach this point, we make sure we can reach the keycloak server. To so, we perform a selfRevocationTest with a empty nonce.
            // If this test throws, the user is not prompted to authenticate.
            _ = try await selfRevocationTest(serverURL: serverURL, selfRevocationTestNonce: "")
            
            // If we reach this point, we have no selfRevocationTestNonceFromEngine, we can immediately prompt for authentication
            try await openKeycloakAuthenticationRequired(serverURL: serverURL, clientId: clientId, clientSecret: clientSecret, ownedCryptoId: ownedCryptoId, title: title, message: message)
            return
        }
        
        let isRevoked = try await selfRevocationTest(serverURL: serverURL, selfRevocationTestNonce: selfRevocationTestNonceFromEngine)
        
        if isRevoked {
            // The server returned `true`, the identity is no longer managed
            // We unbind it at the engine level and display an alert to the user
            setLastSynchronizationDate(forOwnedIdentity: ownedCryptoId, to: nil)
            do {
                try await delegate.unbindOwnedIdentityFromKeycloak(ownedCryptoId: ownedCryptoId, isUnbindRequestByUser: false)
                try await openAppDialogKeycloakIdentityRevoked()
            } catch {
                Self.logger.fault("Could not unbind revoked owned identity: \(error.localizedDescription)")
                assertionFailure()
                throw KeycloakDialogError.keycloakManagerError(error)
            }
        } else {
            try await openKeycloakAuthenticationRequired(serverURL: serverURL, clientId: clientId, clientSecret: clientSecret, ownedCryptoId: ownedCryptoId, title: title, message: message)
        }
        
    }


    /// Shall only be called from `selfTestAndOpenKeycloakAuthenticationRequired`
    @MainActor
    private func openAppDialogKeycloakIdentityRevoked() async throws {
        Self.logger.info("🧥 Call to openAppDialogKeycloakIdentityRevoked")
        assert(Thread.isMainThread)
        let menu = UIAlertController(
            title: Strings.KeycloakIdentityWasRevokedAlert.title,
            message: Strings.KeycloakIdentityWasRevokedAlert.message,
            preferredStyle: .alert)
        let okAction = UIAlertAction(title: String.init(localized: "OK"), style: .default)
        menu.addAction(okAction)
        
        guard let keycloakSceneDelegate = await keycloakSceneDelegate else {
            assertionFailure()
            throw KeycloakManager.makeError(message: "The keycloak scene delegate is not set")
        }
        let viewController = try await keycloakSceneDelegate.requestViewControllerForPresenting()
        
        viewController.present(menu, animated: true)
    }

    
    /// Shall only be called from selfTestAndOpenKeycloakAuthenticationRequired.
    /// Throws a KeycloakDialogError
    @MainActor
    private func openKeycloakAuthenticationRequired(serverURL: URL, clientId: String, clientSecret: String?, ownedCryptoId: ObvCryptoId, title: String, message: String) async throws {

        Self.logger.info("🧥 Call to openKeycloakAuthenticationRequired")
        assert(Thread.isMainThread)
        
        Self.logger.debug("🧥 In openKeycloakAuthenticationRequired: Will request keycloakSceneDelegate")
        guard let keycloakSceneDelegate = await keycloakSceneDelegate else {
            Self.logger.error("🧥 In openKeycloakAuthenticationRequired: could not get keycloakSceneDelegate")
            assertionFailure()
            throw Self.makeError(message: "The keycloakSceneDelegate is not set")
        }
        Self.logger.debug("🧥 In openKeycloakAuthenticationRequired: Did obtain keycloakSceneDelegate")

        Self.logger.debug("🧥 In openKeycloakAuthenticationRequired: Will request view controller for presenting")
        let viewController = try await keycloakSceneDelegate.requestViewControllerForPresenting()
        Self.logger.debug("🧥 In openKeycloakAuthenticationRequired: Did obtain view controller for presenting")

        let displayName = await delegate?.getOwnedIdentityDisplayName(ownedCryptoId)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
         
            assert(Thread.isMainThread)

            let menu = UIAlertController(title: title, message: message, preferredStyle: UIDevice.current.actionSheetIfPhoneAndAlertOtherwise)
                        
            let authenticateActionTitle = Strings.authenticateActionTitle(displayName: displayName)
            let authenticateAction = UIAlertAction(title: authenticateActionTitle, style: .default) { _ in
                Task { [weak self] in
                    guard let _self = self else { return }
                    do {
                        let (jwks, configuration) = try await _self.discoverKeycloakServerAndSaveJWKSet(for: serverURL, ownedCryptoId: ownedCryptoId)
                        let authState = try await _self.authenticate(configuration: configuration, clientId: clientId, clientSecret: clientSecret, ownedCryptoId: ownedCryptoId)
                        await _self.reAuthenticationSuccessful(ownedCryptoId: ownedCryptoId, jwks: jwks, authState: authState)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: KeycloakDialogError.keycloakManagerError(error))
                        return
                    }
                }
            }
            
            let cancelAction = UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in
                continuation.resume(throwing: KeycloakDialogError.userHasCancelled)
                return
            }
            
            menu.addAction(authenticateAction)
            menu.addAction(cancelAction)
            
            Self.logger.debug("🧥 In openKeycloakAuthenticationRequired: Will present alert")
            viewController.present(menu, animated: true, completion: nil)

        }

    }


    @MainActor
    private func openAppDialogKeycloakSignatureKeyChanged() async throws -> Bool {
        Self.logger.info("🧥 Call to openAppDialogKeycloakSignatureKeyChanged")
        assert(Thread.isMainThread)
        guard let keycloakSceneDelegate = await keycloakSceneDelegate else {
            assertionFailure()
            throw Self.makeError(message: "The keycloakSceneDelegate is not set")
        }
        let viewController = try await keycloakSceneDelegate.requestViewControllerForPresenting()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            assert(Thread.isMainThread)
            let menu = UIAlertController(title: Strings.KeycloakSignatureKeyChangedAlert.title, message: Strings.KeycloakSignatureKeyChangedAlert.message, preferredStyle: UIDevice.current.actionSheetIfPhoneAndAlertOtherwise)
            let updateAction = UIAlertAction(title: Strings.KeycloakSignatureKeyChangedAlert.positiveButtonTitle, style: .destructive) { _ in
                continuation.resume(returning: true)
            }
            let cancelAction = UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in
                continuation.resume(returning: false)
            }
            menu.addAction(updateAction)
            menu.addAction(cancelAction)
            viewController.present(menu, animated: true)
        }
    }

    
    /// Throws a KeycloakDialogError
    private func openKeycloakAuthenticationRequiredTokenExpired(internalKeycloakState iks: InternalKeycloakState, ownedCryptoId: ObvCryptoId) async throws {
        Self.logger.info("🧥 Call to openKeycloakAuthenticationRequiredTokenExpired")
        let displayName = await delegate?.getOwnedIdentityDisplayName(ownedCryptoId)
        try await selfTestAndOpenKeycloakAuthenticationRequired(serverURL: iks.keycloakServer,
                                                                clientId: iks.clientId,
                                                                clientSecret: iks.clientSecret,
                                                                ownedCryptoId: ownedCryptoId,
                                                                title: Strings.authenticationRequiredTokenExpired(displayName: displayName),
                                                                message: Strings.AuthenticationRequiredTokenExpiredMessage)
    }


    /// Only called from `getInternalKeycloakState`. Throws a KeycloakDialogError
    private func openKeycloakAuthenticationRequiredTokenExpired(obvKeycloakState oks: ObvKeycloakState, ownedCryptoId: ObvCryptoId) async throws {
        Self.logger.info("🧥 Call to openKeycloakAuthenticationRequiredTokenExpired")
        let displayName = await delegate?.getOwnedIdentityDisplayName(ownedCryptoId)
        try await selfTestAndOpenKeycloakAuthenticationRequired(serverURL: oks.keycloakServer,
                                                                clientId: oks.clientId,
                                                                clientSecret: oks.clientSecret,
                                                                ownedCryptoId: ownedCryptoId,
                                                                title: Strings.authenticationRequiredTokenExpired(displayName: displayName),
                                                                message: Strings.AuthenticationRequiredTokenExpiredMessage)
    }


    /// Throws a KeycloakDialogError
    private func openKeycloakAuthenticationRequiredUserIdChanged(internalKeycloakState iks: InternalKeycloakState, ownedCryptoId: ObvCryptoId) async throws {
        Self.logger.info("🧥 Call to openKeycloakAuthenticationRequiredUserIdChanged")
        try await selfTestAndOpenKeycloakAuthenticationRequired(serverURL: iks.keycloakServer,
                                                                clientId: iks.clientId,
                                                                clientSecret: iks.clientSecret,
                                                                ownedCryptoId: ownedCryptoId,
                                                                title: Strings.AuthenticationRequiredUserIdChanged,
                                                                message: Strings.AuthenticationRequiredUserIdChangedMessage)
    }


    /// Shall only be called from selfTestAndOpenKeycloakAuthenticationRequired
    private func selfRevocationTest(serverURL: URL, selfRevocationTestNonce: String) async throws -> Bool {
        Self.logger.info("🧥 Call to selfRevocationTest")

        let selfRevocationTestJSON = SelfRevocationTestJSON(selfRevocationTestNonce: selfRevocationTestNonce)
        let encoder = JSONEncoder()
        let dataToSend = try encoder.encode(selfRevocationTestJSON)

        let apiResultForRevocationTestPath: KeycloakManager.ApiResultForRevocationTestPath = try await keycloakApiRequest(serverURL: serverURL, path: KeycloakManager.revocationTestPath, accessToken: nil, dataToSend: dataToSend)
        return apiResultForRevocationTestPath.isRevoked
    }


    /// Throws a KeycloakDialogError
    @MainActor
    private func openKeycloakRevocation(serverURL: URL, authState: OIDAuthState, ownedCryptoId: ObvCryptoId) async throws {
        Self.logger.info("🧥 Call to openKeycloakRevocation")
        assert(Thread.isMainThread)

        guard let keycloakSceneDelegate = await keycloakSceneDelegate else {
            assertionFailure()
            throw Self.makeError(message: "The keycloakSceneDelegate is not set")
        }
        
        let viewController = try await keycloakSceneDelegate.requestViewControllerForPresenting()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in

            assert(Thread.isMainThread)

            let menu = UIAlertController(title: Strings.KeycloakRevocation, message: Strings.KeycloakRevocationMessage, preferredStyle: UIDevice.current.actionSheetIfPhoneAndAlertOtherwise)
            
            let revokeAction = UIAlertAction(title: Strings.KeycloakRevocationButton, style: .default) { _ in
                Task { [weak self] in
                    guard let _self = self else { return }
                    assert(Thread.isMainThread)
                    do {
                        try await _self.uploadOwnedIdentity(serverURL: serverURL, authState: authState, ownedIdentity: ownedCryptoId)
                        continuation.resume()
                        return
                    } catch {
                        continuation.resume(throwing: KeycloakDialogError.keycloakManagerError(error))
                        return
                    }
                }
            }
            
            let cancelAction = UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in
                continuation.resume(throwing: KeycloakDialogError.userHasCancelled)
            }
            
            menu.addAction(revokeAction)
            menu.addAction(cancelAction)
            
            if let presentedViewController = viewController.presentedViewController {
                presentedViewController.present(menu, animated: true)
            } else {
                viewController.present(menu, animated: true, completion: nil)
            }

        }
            
    }


    @MainActor
    func openKeycloakRevocationForbidden() async throws {
        Self.logger.info("🧥 Call to openKeycloakRevocationForbidden")
        assert(Thread.isMainThread)

        guard let keycloakSceneDelegate = await keycloakSceneDelegate else {
            assertionFailure()
            throw Self.makeError(message: "The keycloakSceneDelegate is not set")
        }
        
        let viewController = try await keycloakSceneDelegate.requestViewControllerForPresenting()

        let alert = UIAlertController(title: Strings.KeycloakRevocationForbidden.title, message: Strings.KeycloakRevocationForbidden.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction.init(title: String(localized: "OK"), style: .cancel))
        viewController.present(alert, animated: true)
    }


    /// This method is called each time the user re-authenticates succesfully. It saves the fresh jwks and auth state both in cache and within the engine.
    /// It also forces a new sychronization with the keycloak server.
    private func reAuthenticationSuccessful(ownedCryptoId: ObvCryptoId, jwks: ObvJWKSet, authState: OIDAuthState) async {
        
        Self.logger.info("🧥 Call to reAuthenticationSuccessful")

        guard let delegate else {
            assertionFailure()
            return
        }
        
        // Save the jwks within the engine

        do {
            try await delegate.saveKeycloakJwks(with: ownedCryptoId, jwks: jwks)
        } catch {
            Self.logger.fault("🧥 Could not save the new jwks within the engine")
            assertionFailure()
            return
        }

        do {
            let rawAuthState = try authState.serialize()
            try await delegate.saveKeycloakAuthState(with: ownedCryptoId, rawAuthState: rawAuthState)
        } catch {
            Self.logger.fault("🧥 Could not save the new auth state within the engine")
            assertionFailure()
            return
        }

        // Sync with the server

        Task {
            await synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: true)
        }

    }


    // MARK: - Localized strings

    struct Strings {

        static func authenticationRequiredTokenExpired(displayName: String?) -> String {
            if let displayName {
                String(localized: "AUTHENTICATION_REQUIRED_\(displayName.trimmingWhitespacesAndNewlines())")
            } else {
                String(localized: "AUTHENTICATION_REQUIRED")
            }
        }
        static let AuthenticationRequiredTokenExpiredMessage = String(localized: "AUTHENTICATION_REQUIRED_TOKEN_EXPIRED_MESSAGE")

        static let AuthenticationRequiredUserIdChanged = String(localized: "USER_CHANGE_DETECTED")
        static let AuthenticationRequiredUserIdChangedMessage = String(localized: "AUTHENTICATION_REQUIRED_USER_ID_CHANGED_MESSAGE")

        static let KeycloakRevocation = String(localized: "KEYCLOAK_REVOCATION")
        static let KeycloakRevocationButton = String(localized: "KEYCLOAK_REVOCATION_BUTTON")
        static let KeycloakRevocationMessage = String(localized: "KEYCLOAK_REVOCATION_MESSAGE")

        struct KeycloakRevocationForbidden {
            static let title = String(localized: "KEYCLOAK_REVOCATION_FORBIDDEN_TITLE")
            static let message = String(localized: "KEYCLOAK_REVOCATION_FORBIDDEN_MESSAGE")
        }

        struct KeycloakIdentityWasRevokedAlert {
            static let title = String(localized: "DIALOG_TITLE_KEYCLOAK_IDENTITY_WAS_REVOKED")
            static let message = String(localized: "DIALOG_MESSAGE_KEYCLOAK_IDENTITY_WAS_REVOKED")
        }

        struct KeycloakSignatureKeyChangedAlert {
            static let title = String(localized: "DIALOG_TITLE_KEYCLOAK_SIGNATURE_KEY_CHANGED")
            static let message = String(localized: "DIALOG_MESSAGE_KEYCLOAK_SIGNATURE_KEY_CHANGED")
            static let positiveButtonTitle = String(localized: "BUTTON_LABEL_UPDATE_KEY")
        }

        static func authenticateActionTitle(displayName: String?) -> String {
            if let displayName {
                String(localized: "AUTHENTICATE_AS_\(displayName.trimmingWhitespacesAndNewlines())")
            } else {
                String(localized: "AUTHENTICATE")
            }
        }
        
    }

}


// MARK: - KeycloakManagerState


fileprivate struct InternalKeycloakState {
    let keycloakServer: URL
    let clientId: String
    let clientSecret: String?
    let jwks: ObvJWKSet
    let authState: OIDAuthState
    let signatureVerificationKey: ObvJWK?
    let accessToken: String
    let latestGroupUpdateTimestamp: Date?
    let latestRevocationListTimestamp: Date?
    let signedOwnedDetails: SignedObvKeycloakUserDetails? // Our owned details, signed by the keycloak server, as we know them locally in the identity manager
}


fileprivate extension Task where Success == Never, Failure == Never {
    
    static func sleep(failedAttemps: Int) async throws {
        let halfASecond: Double = 0.5 * Double((Int(1)<<failedAttemps))
        try await Self.sleep(seconds: halfASecond)
    }
    
}


public protocol KeycloakSceneDelegate: AnyObject {
   @MainActor func requestViewControllerForPresenting() async throws -> UIViewController
}


// MARK: Extending OIDAuthorizationService to perform async requests

extension OIDAuthorizationService {
    
    @MainActor
    class func present(_ request: OIDAuthorizationRequest, presenting presentingViewController: UIViewController, storeSession: (OIDExternalUserAgentSession) -> Void) async throws -> OIDAuthorizationResponse {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OIDAuthorizationResponse, Error>) in
            assert(Thread.isMainThread)
            let session = self.present(request, presenting: presentingViewController) { response, error in
                if let response = response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: error ?? ObvError.couldNotPresentAuthorizationRequest)
                }
            }
            storeSession(session)
        }
    }

    
    class func perform(_ request: OIDTokenRequest) async throws -> OIDTokenResponse {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OIDTokenResponse, Error>) in
            perform(request) { tokenResponse, error in
                if let tokenResponse = tokenResponse {
                    continuation.resume(returning: tokenResponse)
                } else {
                    continuation.resume(throwing: error ?? ObvError.failedToPerformRequest)
                }
            }
        }
    }

    
    class func discoverConfiguration(forIssuer issuerURL: URL) async throws -> OIDServiceConfiguration {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OIDServiceConfiguration, Error>) in
            discoverConfiguration(forIssuer: issuerURL) { configuration, error in
                if let configuration = configuration {
                    continuation.resume(returning: configuration)
                } else {
                    continuation.resume(throwing: error ?? ObvError.failedToPerformRequest)
                }
            }
        }
    }
    
    
    enum ObvError: Error {
        case couldNotPresentAuthorizationRequest
        case failedToPerformRequest
    }

}


// MARK: Extending OIDAuthState to perform async requests
 
extension OIDAuthState {
    
    func performAction() async throws -> (accessToken: String?, idToken: String?) {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(accessToken: String?, idToken: String?), Error>) in
            self.performAction { (accessToken, idToken, error) in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == OIDGeneralErrorDomain {   //, nsError.code == OIDErrorCode.networkError.rawValue {
                        // If the error is a network error, we throw, so as to make sure we don't prompt the user to authenticate
                        return continuation.resume(throwing: error)
                    } else {
                        return continuation.resume(returning: (nil, nil))
                    }
                } else {
                    return continuation.resume(returning: (accessToken, idToken))
                }
            }
        }
    }
        
}


public enum KeycloakAddContactInfo {
    case userId(userId: String)
    case signedDetails(signedDetails: SignedObvKeycloakUserDetails)
}


// MARK: - Private helpers

extension String {
    
    init(localized keyAndValue: String.LocalizationValue) {
        self.init(localized: keyAndValue, table: "Localizable", bundle: Bundle(for: ObvKeycloakManagerResources.self))
    }
    
}
