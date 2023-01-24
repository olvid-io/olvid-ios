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
import UIKit
import os.log
import ObvTypes
import ObvEngine
import ObvCrypto
import AppAuth
import JWS
import OlvidUtils

@MainActor
final class KeycloakManagerSingleton: ObvErrorMaker {
    
    static var shared = KeycloakManagerSingleton()
    private init() {}
    
    static let errorDomain = "KeycloakManagerSingleton"
    
    fileprivate weak var manager: KeycloakManager?
    
    fileprivate func setManager(manager: KeycloakManager?) {
        assert(manager != nil)
        self.manager = manager
    }
    
    
    func registerKeycloakManagedOwnedIdentity(ownedCryptoId: ObvCryptoId, firstKeycloakBinding: Bool) async {
        guard let manager = manager else { assertionFailure(); return }
        await manager.registerKeycloakManagedOwnedIdentity(ownedCryptoId: ownedCryptoId, firstKeycloakBinding: firstKeycloakBinding)
    }

    
    func setKeycloakSceneDelegate(to newKeycloakSceneDelegate: KeycloakSceneDelegate) async {
        guard let manager = manager else { assertionFailure(); return }
        await manager.setKeycloakSceneDelegate(to: newKeycloakSceneDelegate)
    }
    
    
    @MainActor
    func resumeExternalUserAgentFlow(with url: URL) async throws -> Bool {
        guard let manager = manager else {
            assertionFailure()
            throw Self.makeError(message: "The internal manager is not set")
        }
        return await manager.resumeExternalUserAgentFlow(with: url)
    }
    
    
    func forceSyncManagedIdentitiesAssociatedWithPushTopics(_ receivedPushTopic: String, failedAttempts: Int = 0) async throws {
        guard let manager = manager else {
            assertionFailure()
            throw Self.makeError(message: "The internal manager is not set")
        }
        try await manager.forceSyncManagedIdentitiesAssociatedWithPushTopics(receivedPushTopic)
    }
    
    
    /// Throws a UploadOwnedIdentityError
    func uploadOwnIdentity(ownedCryptoId: ObvCryptoId) async throws {
        guard let manager = manager else {
            assertionFailure()
            throw Self.makeError(message: "The internal manager is not set")
        }
        try await manager.uploadOwnIdentity(ownedCryptoId: ownedCryptoId)
    }


    func unregisterKeycloakManagedOwnedIdentity(ownedCryptoId: ObvCryptoId) async throws {
        guard let manager = manager else {
            assertionFailure()
            throw Self.makeError(message: "The internal manager is not set")
        }
        try await manager.unregisterKeycloakManagedOwnedIdentity(ownedCryptoId: ownedCryptoId)
    }
    

    func discoverKeycloakServer(for serverURL: URL) async throws -> (ObvJWKSet, OIDServiceConfiguration) {
        guard let manager = manager else {
            assertionFailure()
            throw Self.makeError(message: "The internal manager is not set")
        }
        return try await manager.discoverKeycloakServer(for: serverURL)
    }

    
    func authenticate(configuration: OIDServiceConfiguration, clientId: String, clientSecret: String?, ownedCryptoId: ObvCryptoId?) async throws -> OIDAuthState {
        guard let manager = manager else {
            assertionFailure()
            throw Self.makeError(message: "The internal manager is not set")
        }
        return try await manager.authenticate(configuration: configuration, clientId: clientId, clientSecret: clientSecret, ownedCryptoId: ownedCryptoId)
    }
    
    
    /// If the manager is not set, this function throws an `Error`. If any other error occurs, it can be casted to a `GetOwnDetailsError`.
    func getOwnDetails(keycloakServer: URL, authState: OIDAuthState, clientSecret: String?, jwks: ObvJWKSet, latestLocalRevocationListTimestamp: Date?) async throws -> (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff) {
        guard let manager = manager else {
            assertionFailure()
            throw Self.makeError(message: "The internal manager is not set")
        }
        return try await manager.getOwnDetails(keycloakServer: keycloakServer, authState: authState, clientSecret: clientSecret, jwks: jwks, latestLocalRevocationListTimestamp: latestLocalRevocationListTimestamp)
    }
    
    
    /// If the manager is not set, this function throws an `Error`. If any other error occurs, it can be casted to a `KeycloakManager.AddContactError`.
    func addContact(ownedCryptoId: ObvCryptoId, userId: String, userIdentity: Data) async throws {
        guard let manager = manager else {
            assertionFailure()
            throw Self.makeError(message: "The internal manager is not set")
        }
        try await manager.addContact(ownedCryptoId: ownedCryptoId, userId: userId, userIdentity: userIdentity)
    }

    
    /// If the manager is not set, this function throws an `Error`. If any other error occurs, it can be casted to a `KeycloakManager.SearchError`.
    func search(ownedCryptoId: ObvCryptoId, searchQuery: String?) async throws -> (userDetails: [UserDetails], numberOfMissingResults: Int) {
        assert(Thread.isMainThread)
        guard let manager else {
            assertionFailure()
            throw Self.makeError(message: "The internal manager is not set")
        }
        return try await manager.search(ownedCryptoId: ownedCryptoId, searchQuery: searchQuery)
    }
    
}


actor KeycloakManager: NSObject {

    let obvEngine: ObvEngine
    
    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        super.init()
    }
    
    
    func performPostInitialization() async {
        await KeycloakManagerSingleton.shared.setManager(manager: self)
    }
    

    private var currentAuthorizationFlow: OIDExternalUserAgentSession?

    private func setCurrentAuthorizationFlow(to newCurrentAuthorizationFlow: OIDExternalUserAgentSession?) {
        self.currentAuthorizationFlow = newCurrentAuthorizationFlow
    }
    
    private static var mePath = "olvid-rest/me"
    private static var putKeyPath = "olvid-rest/putKey"
    private static var getKeyPath = "olvid-rest/getKey"
    private static var searchPath = "olvid-rest/search"
    private static var revocationTestPath = "olvid-rest/revocationTest"

    private static let errorDomain = "KeycloakManager"
    private static var log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "KeycloakManager")
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

    private var currentlySyncingOwnedIdentities = Set<ObvCryptoId>()

    private var ownedCryptoIdForOIDAuthState = [OIDAuthState: ObvCryptoId]()

    weak var keycloakSceneDelegate: KeycloakSceneDelegate?

    private lazy var internalUnderlyingQueue = DispatchQueue(label: "KeycloakManager internal queue", qos: .default)

    fileprivate func setKeycloakSceneDelegate(to newKeycloakSceneDelegate: KeycloakSceneDelegate) {
        self.keycloakSceneDelegate = newKeycloakSceneDelegate
    }

    // MARK: - Public Methods

    fileprivate func registerKeycloakManagedOwnedIdentity(ownedCryptoId: ObvCryptoId, firstKeycloakBinding: Bool) async {
        os_log("🧥 Call to registerKeycloakManagedOwnedIdentity", log: KeycloakManager.log, type: .info)
        // Unless this is the first keycloak binding, we synchronize the owned identity with the keycloak server
        if !firstKeycloakBinding {
            await synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: false)
        }
    }


    fileprivate func unregisterKeycloakManagedOwnedIdentity(ownedCryptoId: ObvCryptoId, failedAttempts: Int = 0) async throws {
        os_log("🧥 Call to unregisterKeycloakManagedOwnedIdentity", log: KeycloakManager.log, type: .info)
        do {
            setLastSynchronizationDate(forOwnedIdentity: ownedCryptoId, to: nil)
            try await obvEngine.unbindOwnedIdentityFromKeycloakServer(ownedCryptoId: ownedCryptoId)
        } catch {
            guard failedAttempts < maxFailCount else {
                assertionFailure()
                throw error
            }
            try await Task.sleep(failedAttemps: failedAttempts)
            try await unregisterKeycloakManagedOwnedIdentity(ownedCryptoId: ownedCryptoId, failedAttempts: failedAttempts + 1)
        }
    }
    

    /// When receiving a silent push notification originated in the keycloak server, we sync the managed owned identity associated with the push topic indicated whithin the infos of the push notification
    func forceSyncManagedIdentitiesAssociatedWithPushTopics(_ receivedPushTopic: String, failedAttempts: Int = 0) async throws {
        os_log("🧥 Call to syncManagedIdentitiesAssociatedWithPushTopics", log: KeycloakManager.log, type: .info)
        do {
            let associatedOwnedIdentities = try obvEngine.getManagedOwnedIdentitiesAssociatedWithThePushTopic(receivedPushTopic)
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

    
    private func syncAllManagedIdentities(failedAttempts: Int = 0, ignoreSynchronizationInterval: Bool) async throws {
        os_log("🧥 Call to syncAllManagedIdentities", log: KeycloakManager.log, type: .info)
        do {
            let ownedIdentities = (try obvEngine.getOwnedIdentities()).filter({ $0.isKeycloakManaged })
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


    /// Throws an UploadOwnedIdentityError
    fileprivate func uploadOwnIdentity(ownedCryptoId: ObvCryptoId) async throws {
        os_log("🧥 Call to uploadOwnIdentity", log: KeycloakManager.log, type: .info)
        
        let iks: InternalKeycloakState
        do {
            iks = try await getInternalKeycloakState(for: ownedCryptoId)
        } catch {
            throw UploadOwnedIdentityError.unkownError(error)
        }

        do {
            try await uploadOwnedIdentity(serverURL: iks.keycloakServer, authState: iks.authState, ownedIdentity: ownedCryptoId)
        } catch let error as UploadOwnedIdentityError {
            switch error {
            case .ownedIdentityWasRevoked:
                throw UploadOwnedIdentityError.ownedIdentityWasRevoked
            case .authenticationRequired:
                do {
                    try await openKeycloakAuthenticationRequiredTokenExpired(internalKeycloakState: iks, ownedCryptoId: ownedCryptoId)
                    return try await uploadOwnIdentity(ownedCryptoId: ownedCryptoId)
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
        
        Task {
            await synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: false)
        }

    }


    /// Throws a SearchError
    fileprivate func search(ownedCryptoId: ObvCryptoId, searchQuery: String?) async throws -> (userDetails: [UserDetails], numberOfMissingResults: Int) {
        os_log("🧥 Call to search", log: KeycloakManager.log, type: .info)
        
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
    fileprivate func addContact(ownedCryptoId: ObvCryptoId, userId: String, userIdentity: Data) async throws {
        os_log("🧥 Call to addContact", log: KeycloakManager.log, type: .info)
        
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
                
        let signedUserDetails: SignedUserDetails
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
                signedUserDetails = try SignedUserDetails.verifySignedUserDetails(result.signature, with: signatureVerificationKey)
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
        guard signedUserDetails.identity == userIdentity else {
            throw AddContactError.badResponse
        }
        do {
            try obvEngine.addKeycloakContact(with: ownedCryptoId, signedContactDetails: signedUserDetails)
        } catch(let error) {
            throw AddContactError.unkownError(error)
        }
        
    }
    

    fileprivate func authenticate(configuration: OIDServiceConfiguration, clientId: String, clientSecret: String?, ownedCryptoId: ObvCryptoId?) async throws -> OIDAuthState {

        os_log("🧥 Call to authenticate", log: KeycloakManager.log, type: .info)

        let kRedirectURI = "https://\(ObvMessengerConstants.Host.forOpenIdRedirect)/"

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
        os_log("🧥 Initiating authorization request with scope: %{public}@", log: KeycloakManager.log, type: .info, request.scope ?? "DEFAULT_SCOPE")

        guard let keycloakSceneDelegate = keycloakSceneDelegate else {
            assertionFailure()
            throw KeycloakManager.makeError(message: "The keycloak scene delegate is not set")
        }
        let viewController = try await keycloakSceneDelegate.requestViewControllerForPresenting()
        // AppStateManager.shared.ignoreNextResignActiveTransition = true

        let storeSession: (OIDExternalUserAgentSession) -> Void = { currentAuthorizationFlow in
            Task { [weak self] in
                await self?.setCurrentAuthorizationFlow(to: currentAuthorizationFlow)
            }
        }
        let authorizationResponse = try await OIDAuthorizationService.present(request, presenting: viewController, storeSession: storeSession)

        os_log("🧥 OIDAuthorizationService did return", log: KeycloakManager.log, type: .info)

        let authState: OIDAuthState
        if let ownedCryptoId = ownedCryptoId,
           let keycloakState = try? obvEngine.getOwnedIdentityKeycloakState(with: ownedCryptoId).obvKeycloakState,
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

        os_log("🧥 Call to discoverKeycloakServer", log: KeycloakManager.log, type: .info)

        let configuration = try await OIDAuthorizationService.discoverConfiguration(forIssuer: serverURL)
        
        guard let discoveryDocument = configuration.discoveryDocument else {
            throw KeycloakManager.makeError(message: "No discovery document available")
        }

        let jwksData = try await getJkws(url: discoveryDocument.jwksURL)
        
        let jwks = try ObvJWKSet(data: jwksData)
        
        return (jwks, configuration)

    }


    /// Throws a GetOwnDetailsError
    fileprivate func getOwnDetails(keycloakServer: URL, authState: OIDAuthState, clientSecret: String?, jwks: ObvJWKSet, latestLocalRevocationListTimestamp: Date?) async throws -> (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff) {
        
        os_log("🧥 Call to getOwnDetails", log: KeycloakManager.log, type: .info)
        
        guard let (accessToken, _) = try? await authState.performAction(), let accessToken = accessToken else {
            os_log("🧥 Authentication required in getOwnDetails", log: KeycloakManager.log, type: .info)
            throw GetOwnDetailsError.authenticationRequired
        }
        
        let dataToSend: Data?
        if let latestLocalRevocationListTimestamp = latestLocalRevocationListTimestamp {
            let query = ApiQueryForMePath(latestLocalRevocationListTimestamp: latestLocalRevocationListTimestamp)
            do {
                dataToSend = try query.jsonEncode()
            } catch {
                os_log("Could not encode latestRevocationListTimestamp: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
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
                os_log("🧥 The keycloak server returned a permission denied error", log: KeycloakManager.log, type: .error)
                throw GetOwnDetailsError.authenticationRequired
            case .internalError, .invalidRequest, .identityAlreadyUploaded, .badResponse, .decodingFailed:
                os_log("🧥 The keycloak server returned an error", log: KeycloakManager.log, type: .error)
                throw GetOwnDetailsError.serverError
            case .ownedIdentityWasRevoked:
                os_log("🧥 The keycloak server indicates that the owned identity was revoked", log: KeycloakManager.log, type: .error)
                throw GetOwnDetailsError.ownedIdentityWasRevoked
            }
        } catch {
            assertionFailure("Unexpected error")
            throw GetOwnDetailsError.unkownError(error)
        }
        
        os_log("🧥 The call to the /me entry point succeeded", log: KeycloakManager.log, type: .info)

        let keycloakServerSignatureVerificationKey: ObvJWK
        let signedUserDetails: SignedUserDetails
        do {
            (signedUserDetails, keycloakServerSignatureVerificationKey) = try SignedUserDetails.verifySignedUserDetails(apiResult.signature, with: jwks)
        } catch {
            os_log("🧥 The server signature is invalid", log: KeycloakManager.log, type: .error)
            throw GetOwnDetailsError.invalidSignature(error)
        }

        os_log("🧥 The server signature is valid", log: KeycloakManager.log, type: .info)

        let keycloakUserDetailsAndStuff = KeycloakUserDetailsAndStuff(signedUserDetails: signedUserDetails,
                                                                      serverSignatureVerificationKey: keycloakServerSignatureVerificationKey,
                                                                      server: apiResult.server,
                                                                      apiKey: apiResult.apiKey,
                                                                      pushTopics: apiResult.pushTopics,
                                                                      selfRevocationTestNonce: apiResult.selfRevocationTestNonce)
        let keycloakServerRevocationsAndStuff = KeycloakServerRevocationsAndStuff(revocationAllowed: apiResult.revocationAllowed,
                                                                                  currentServerTimestamp: apiResult.currentServerTimestamp,
                                                                                  signedRevocations: apiResult.signedRevocations,
                                                                                  minimumIOSBuildVersion: apiResult.minimumIOSBuildVersion)

        os_log("🧥 Calling the completion of the getOwnDetails method", log: KeycloakManager.log, type: .info)
        
        return (keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff)
                
    }


    /// Called when the user resumes an OpendId connect authentication
    @MainActor
    fileprivate func resumeExternalUserAgentFlow(with url: URL) async -> Bool {
        os_log("🧥 Resume External Agent flow...", log: KeycloakManager.log, type: .info)
        assert(Thread.isMainThread)
        if let authorizationFlow = await self.currentAuthorizationFlow, authorizationFlow.resumeExternalUserAgentFlow(with: url) {
            os_log("🧥 Resume External Agent succeed", log: KeycloakManager.log, type: .info)
            await setCurrentAuthorizationFlow(to: nil)
            return true
        } else {
            os_log("🧥 Resume External Agent flow failed", log: KeycloakManager.log, type: .error)
            return false
        }
    }


    // MARK: - Private Methods and helpers


    private func synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ObvCryptoId, ignoreSynchronizationInterval: Bool, failedAttempts: Int = 0) async {
        
        assert(!Thread.isMainThread)
        
        os_log("🧥 Call to synchronizeOwnedIdentityWithKeycloakServer", log: KeycloakManager.log, type: .info)
        
        guard !currentlySyncingOwnedIdentities.contains(ownedCryptoId) else {
            os_log("🧥 Trying to sync an owned identity that is already syncing", log: KeycloakManager.log, type: .error)
            return
        }
        
        // Mark the identity as currently syncing --> un-mark it as soon as success or failure
        
        currentlySyncingOwnedIdentities.insert(ownedCryptoId)
        defer {
            currentlySyncingOwnedIdentities.remove(ownedCryptoId)
        }

        // Make sure the owned identity is still bound to a keycloak server
        
        var ownedIdentityIsKeycloakManaged = true
        ObvStack.shared.performBackgroundTaskAndWait { context in
            let persistedOwnedIdentity: PersistedObvOwnedIdentity
            do {
                guard let _persistedOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else {
                    os_log("🧥 Could not find owned identity. Unexpected", log: KeycloakManager.log, type: .error)
                    assertionFailure()
                    return
                }
                persistedOwnedIdentity = _persistedOwnedIdentity
            } catch {
                os_log("🧥 Could not get owned identity: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            ownedIdentityIsKeycloakManaged = persistedOwnedIdentity.isKeycloakManaged
        }
        
        guard ownedIdentityIsKeycloakManaged else {
            os_log("🧥 The owned identity is not bound to a keycloak server anymore. We cancel the sync process with the server", log: KeycloakManager.log, type: .info)
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
        
        guard Date().timeIntervalSince(lastSynchronizationDate) > self.synchronizationInterval || ignoreSynchronizationInterval else {
            return
        }
        
        // If we reach this point, we should synchronize the owned identity with the keycloak server
        
        let latestLocalRevocationListTimestamp = iks.latestRevocationListTimestamp ?? Date.distantPast
        
        let (keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff): (KeycloakUserDetailsAndStuff, KeycloakServerRevocationsAndStuff)
        do {
            (keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff) = try await getOwnDetails(keycloakServer: iks.keycloakServer,
                                                                                                       authState: iks.authState,
                                                                                                       clientSecret: iks.clientSecret,
                                                                                                       jwks: iks.jwks,
                                                                                                       latestLocalRevocationListTimestamp: latestLocalRevocationListTimestamp)
        } catch let error as GetOwnDetailsError {
            switch error {
            case .authenticationRequired:
                do {
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
                ObvMessengerInternalNotification.userOwnedIdentityWasRevokedByKeycloak(ownedCryptoId: ownedCryptoId)
                    .postOnDispatchQueue()
                return
            }
        } catch {
            assertionFailure("Unknown error")
            return
        }
        
        os_log("🧥 Successfully downloaded own details from keycloak server", log: KeycloakManager.log, type: .info)
        
        // Check that our Olvid version is not outdated
        
        if let minimumBuildVersion = keycloakServerRevocationsAndStuff.minimumIOSBuildVersion {
            if ObvMessengerConstants.bundleVersionAsInt < minimumBuildVersion {
                ObvMessengerInternalNotification.installedOlvidAppIsOutdated(presentingViewController: nil)
                    .postOnDispatchQueue()
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
                                try obvEngine.setOwnedIdentityKeycloakSignatureKey(ownedCryptoId: ownedCryptoId, keycloakServersignatureVerificationKey: keycloakUserDetailsAndStuff.serverSignatureVerificationKey)
                                return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: nil, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                            } catch {
                                os_log("🧥 Could not store the keycloak server signature key within the engine (2): %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
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
                    try obvEngine.setOwnedIdentityKeycloakSignatureKey(ownedCryptoId: ownedCryptoId, keycloakServersignatureVerificationKey: keycloakUserDetailsAndStuff.serverSignatureVerificationKey)
                } catch {
                    os_log("🧥 Could not store the keycloak server signature key within the engine: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
                    return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                }
                
                // If we reach this point, the signature key has been stored within the engine, we can continue
                
            }
        }
        
        // If we reach this point, the engine is aware of the server signature key, and stores exactly the same value as the one just returned
        os_log("🧥 The server signature verification key matches the one stored locally", log: KeycloakManager.log, type: .info)
        
        // We synchronise the UserId
        
        let previousUserId: String?
        do {
            previousUserId = try obvEngine.getOwnedIdentityKeycloakUserId(with: ownedCryptoId)
        } catch {
            os_log("🧥 Could not get Keycloak UserId of owned identity: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
            return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
        }
        
        if let previousUserId = previousUserId {
            // There was a previous UserId. If it is identical to the one returned by the keycloak server, no problem. Otherwise, we have work to do before retrying to synchronize
            guard previousUserId == userDetailsOnServer.id else {
                // The userId changed on keycloak --> probably an authentication with the wrong login check the identity and only update id locally if the identity is the same
                if ownedCryptoId.getIdentity() == userDetailsOnServer.identity {
                    do {
                        try obvEngine.setOwnedIdentityKeycloakUserId(with: ownedCryptoId, userId: userDetailsOnServer.id)
                        return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: nil, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                    } catch {
                        os_log("🧥 Coult not set the new user id within the engine: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
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
                try obvEngine.setOwnedIdentityKeycloakUserId(with: ownedCryptoId, userId: userDetailsOnServer.id)
            } catch {
                os_log("🧥 Coult not set the new user id within the engine: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
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
                    ObvMessengerInternalNotification.userOwnedIdentityWasRevokedByKeycloak(ownedCryptoId: ownedCryptoId)
                        .postOnDispatchQueue()
                    return
                case .userHasCancelled:
                    break // Do nothing
                case .authenticationRequired:
                    do {
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
            os_log("🧥 We do not have signed owned details locally, we store the ones returned by the keycloak server now.", log: KeycloakManager.log, type: .info)
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
            os_log("🧥 The owned identity core details returned by the server differ from the ones stored locally. We update the local details.", log: KeycloakManager.log, type: .info)
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
        
        let apiKey: UUID
        do {
            apiKey = try obvEngine.getApiKeyForOwnedIdentity(with: ownedCryptoId)
        } catch {
            os_log("🧥 Could not retrieve the current API key from the owned identity.", log: KeycloakManager.log, type: .fault)
            return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
        }

        if let apiKeyOnServer = keycloakUserDetailsAndStuff.apiKey {
            guard apiKey == apiKeyOnServer else {
                // The api key returned by the server differs from the one store locally. We update the local key
                do {
                    try obvEngine.setAPIKey(for: ownedCryptoId, apiKey: apiKeyOnServer, keycloakServerURL: iks.keycloakServer)
                    return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: nil, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: 0)
                } catch {
                    os_log("🧥 Could not update the local API key with the new one returned by the server.", log: KeycloakManager.log, type: .fault)
                    return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                }
            }
        }

        // If we reach this point, the API key stored locally is ok.
        
        // We update the Keycloak push topics stored within the engine
        
        do {
            try obvEngine.updateKeycloakPushTopicsIfNeeded(ownedCryptoId: ownedCryptoId, pushTopics: keycloakUserDetailsAndStuff.pushTopics)
        } catch {
            os_log("🧥 Could not update the engine using the push topics returned by the server.", log: KeycloakManager.log, type: .fault)
            return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
        }

        // If we reach this point, we managed to pass the push topics to the engine
        
        // We reset the self revocation test nonce stored within the engine
        
        do {
            try obvEngine.setOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoId: ownedCryptoId, newSelfRevocationTestNonce: keycloakUserDetailsAndStuff.selfRevocationTestNonce)
        } catch {
            os_log("🧥 Could not update the self revocation test nonce using the nonce returned by the server.", log: KeycloakManager.log, type: .fault)
            return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
        }

        // If we reach this point, we successfully reset the self revocation test nonce stored within the engine
        
        // Update revocation list and latest revocation list timestamp iff the server returned signed revocations (an empty list is ok) and a current server timestamp
        
        if let signedRevocations = keycloakServerRevocationsAndStuff.signedRevocations, let currentServerTimestamp = keycloakServerRevocationsAndStuff.currentServerTimestamp {
            os_log("🧥 The server returned %d signed revocations, we update the engine now", log: KeycloakManager.log, type: .fault, signedRevocations.count)
            do {
                try obvEngine.updateKeycloakRevocationList(ownedCryptoId: ownedCryptoId,
                                                           latestRevocationListTimestamp: currentServerTimestamp,
                                                           signedRevocations: signedRevocations)
            } catch {
                os_log("🧥 Could not update the keycloak revocation list: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
                return await retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
            }
            os_log("🧥 The engine was updated using the the revocations returned by the server", log: KeycloakManager.log, type: .fault)
        }

        // We are done with the sync !!! We can update the sync timestamp
        
        os_log("🧥 Keycloak server synchronization succeeded!", log: KeycloakManager.log, type: .info)
        setLastSynchronizationDate(forOwnedIdentity: ownedCryptoId, to: Date())
        
        Task { [weak self] in
            do {
                try await Task.sleep(seconds: synchronizationInterval + 10)
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
            assertionFailure("Unexpected error")
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
        let obvOwnedIdentity: ObvOwnedIdentity
        do {
            obvOwnedIdentity = try obvEngine.getOwnedIdentity(with: ownedCryptoId)
        } catch {
            os_log("🧥 Could not get the ObvOwnedIdentity from the engine: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
            assertionFailure()
            throw error
        }
        let coreDetailsOnServer: ObvIdentityCoreDetails
        do {
            coreDetailsOnServer = try keycloakUserDetailsAndStuff.getObvIdentityCoreDetails()
        } catch {
            os_log("🧥 Could not get owned core details returned by server: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
            assertionFailure()
            throw error
        }
        // We use the core details from the server, but keep the local photo URL
        let updatedIdentityDetails = ObvIdentityDetails(coreDetails: coreDetailsOnServer, photoURL: obvOwnedIdentity.currentIdentityDetails.photoURL)
        do {
            try obvEngine.updatePublishedIdentityDetailsOfOwnedIdentity(with: ownedCryptoId, with: updatedIdentityDetails)
        } catch {
            os_log("🧥 Could not updated published identity details of owned identity: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
            assertionFailure()
            throw error
        }
    }


    /// Throws a GetObvKeycloakStateError
    private func getInternalKeycloakState(for ownedCryptoId: ObvCryptoId, failedAttempts: Int = 0) async throws -> InternalKeycloakState {

        let obvKeycloakState: ObvKeycloakState
        let signedOwnedDetails: SignedUserDetails?
        do {
            let (_obvKeycloakState, _signedOwnedDetails) = try obvEngine.getOwnedIdentityKeycloakState(with: ownedCryptoId)
            guard let _obvKeycloakState = _obvKeycloakState else {
                os_log("🧥 Could not find keycloak state for owned identity. This happens if the user was unbound from a keycloak server.", log: KeycloakManager.log, type: .fault)
                throw Self.makeError(message: "🧥 Could not find keycloak state for owned identity. This happens if the user was unbound from a keycloak server.")
            }
            obvKeycloakState = _obvKeycloakState
            signedOwnedDetails = _signedOwnedDetails
        } catch {
            os_log("🧥 Could not recover keycloak state for owned identity: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
            guard failedAttempts < maxFailCount else {
                throw GetObvKeycloakStateError.unkownError(error)
            }
            try await Task.sleep(failedAttemps: failedAttempts)
            return try await getInternalKeycloakState(for: ownedCryptoId, failedAttempts: failedAttempts + 1)
        }

        guard let rawAuthState = obvKeycloakState.rawAuthState,
              let authState = OIDAuthState.deserialize(from: rawAuthState),
              authState.isAuthorized,
              let (accessToken, _) = try? await authState.performAction(),
              let accessToken = accessToken else {
            do {
                try await openKeycloakAuthenticationRequiredTokenExpired(obvKeycloakState: obvKeycloakState, ownedCryptoId: ownedCryptoId)
            } catch let error as KeycloakDialogError {
                switch error {
                case .userHasCancelled:
                    throw GetObvKeycloakStateError.userHasCancelled
                case .keycloakManagerError(let error):
                    throw GetObvKeycloakStateError.unkownError(error)
                }
            } catch {
                assertionFailure("Unexpected error")
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
                                                          latestRevocationListTimestamp: obvKeycloakState.latestLocalRevocationListTimestamp,
                                                          signedOwnedDetails: signedOwnedDetails)

        return internalKeycloakState
        
    }


    private func getJkws(url: URL) async throws -> Data {
        os_log("🧥 Call to getJkws", log: KeycloakManager.log, type: .info)
        if #available(iOS 15, *) {
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        } else {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
                    if let data = data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: error ?? KeycloakManager.makeError(message: "No data received"))
                    }
                }
                task.resume()
            }
        }
    }


    private func discoverKeycloakServerAndSaveJWKSet(for serverURL: URL, ownedCryptoId: ObvCryptoId) async throws -> (ObvJWKSet, OIDServiceConfiguration) {
        os_log("🧥 Call to discoverKeycloakServerAndSaveJWKSet", log: KeycloakManager.log, type: .info)
        let (jwks, configuration) = try await discoverKeycloakServer(for: serverURL)
        // Save the jwks in DB
        do {
            try obvEngine.saveKeycloakJwks(with: ownedCryptoId, jwks: jwks)
        } catch {
            throw Self.makeError(message: "Cannot save JWKSet")
        }
        return (jwks, configuration)
    }


    /// Throws an UploadOwnedIdentityError
    private func uploadOwnedIdentity(serverURL: URL, authState: OIDAuthState, ownedIdentity: ObvCryptoId) async throws {
        os_log("🧥 Call to uploadOwnedIdentity", log: KeycloakManager.log, type: .info)
        
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


    enum UploadOwnedIdentityError: Error {
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


    // Throws a KeycloakApiRequestError
    private func keycloakApiRequest<T: KeycloakManagerApiResult>(serverURL: URL, path: String, accessToken: String?, dataToSend: Data?) async throws -> T {

        os_log("🧥 Call to keycloakApiRequest for path: %{public}@", log: KeycloakManager.log, type: .info, path)

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
                    os_log("🧥 Call to keycloakApiRequest for path %{public}@ failed: %{public}@", log: KeycloakManager.log, type: .error, path, error!.localizedDescription)
                    continuation.resume(throwing: KeycloakApiRequestError.invalidRequest)
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    os_log("🧥 Call to keycloakApiRequest for path %{public}@ failed (status code is not 200)", log: KeycloakManager.log, type: .error, path)
                    continuation.resume(throwing: KeycloakApiRequestError.invalidRequest)
                    return
                }
                guard let data = data else {
                    os_log("🧥 Call to keycloakApiRequest for path %{public}@ failed: the keycloak server returned no data", log: KeycloakManager.log, type: .error, path)
                    continuation.resume(throwing: KeycloakApiRequestError.invalidRequest)
                    return
                }
                if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any], let error = json[OIDOAuthErrorFieldError] as? Int {
                    if let ktError = KeycloakApiRequestError(rawValue: error) {
                        os_log("🧥 Call to keycloakApiRequest for path %{public}@ failed: ktError is %{public}@", log: KeycloakManager.log, type: .error, path, ktError.localizedDescription)
                        continuation.resume(throwing: ktError)
                        return
                    } else {
                        os_log("🧥 Call to keycloakApiRequest for path %{public}@ failed: decoding failed (1)", log: KeycloakManager.log, type: .error, path)
                        continuation.resume(throwing: KeycloakApiRequestError.decodingFailed)
                        return
                    }
                }
                let decodedData: T
                do {
                    decodedData = try T.decode(data)
                } catch {
                    os_log("🧥 Call to keycloakApiRequest for path %{public}@ failed: decoding failed (2)", log: KeycloakManager.log, type: .error, path)
                    continuation.resume(throwing: KeycloakApiRequestError.decodingFailed)
                    return
                }
                os_log("🧥 Call to keycloakApiRequest for path %{public}@ succeeded", log: KeycloakManager.log, type: .info, path)
                continuation.resume(returning: decodedData)
                return
            }
            task.resume()
        }
    }
    
}


// MARK: - OIDAuthStateChangeDelegate

extension KeycloakManager: OIDAuthStateChangeDelegate {

    nonisolated func didChange(_ state: OIDAuthState) {
        Task {
            guard let ownedCryptoId = await ownedCryptoIdForOIDAuthState[state] else {
                // This happens during onboarding, when the owned identity is not created yet
                return
            }
            do {
                let rawAuthState = try state.serialize()
                try obvEngine.saveKeycloakAuthState(with: ownedCryptoId, rawAuthState: rawAuthState)
            } catch {
                os_log("🧥 Could not save authState: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            os_log("🧥 OIDAuthState saved", log: KeycloakManager.log, type: .info)
        }
    }

}


// MARK: - A few extensions

extension OIDAuthState {

    func serialize() throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: true)
    }

    static func deserialize(from data: Data) -> OIDAuthState? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = false
        return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? OIDAuthState
    }

}

extension UserDetails {

    var firstNameAndLastName: String {
        guard let coreDetails = try? ObvIdentityCoreDetails(firstName: firstName, lastName: lastName, company: company, position: position, signedUserDetails: nil) else { return "" }
        return coreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
    }
}

extension SingleIdentity {

    convenience init(userDetails: UserDetails) {
        self.init(firstName: userDetails.firstName,
                  lastName: userDetails.lastName,
                  position: userDetails.position,
                  company: userDetails.company,
                  isKeycloakManaged: false,
                  showGreenShield: false,
                  showRedShield: false,
                  identityColors: nil,
                  photoURL: nil)
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
        os_log("🧥 Call to selfTestAndOpenKeycloakAuthenticationRequired", log: KeycloakManager.log, type: .info)

        // Before authenticating, we test whether we have been revoked by the keycloak server

        guard let selfRevocationTestNonceFromEngine = try obvEngine.getOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoId: ownedCryptoId) else {
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
                try await obvEngine.unbindOwnedIdentityFromKeycloakServer(ownedCryptoId: ownedCryptoId)
                try await openAppDialogKeycloakIdentityRevoked()
            } catch {
                os_log("Could not unbind revoked owned identity: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
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
        os_log("🧥 Call to openAppDialogKeycloakIdentityRevoked", log: KeycloakManager.log, type: .info)
        assert(Thread.isMainThread)
        let menu = UIAlertController(
            title: Strings.KeycloakIdentityWasRevokedAlert.title,
            message: Strings.KeycloakIdentityWasRevokedAlert.message,
            preferredStyle: .alert)
        let okAction = UIAlertAction(title: CommonString.Word.Ok, style: .default)
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

        os_log("🧥 Call to openKeycloakAuthenticationRequired", log: KeycloakManager.log, type: .info)
        assert(Thread.isMainThread)
        
        guard let keycloakSceneDelegate = await keycloakSceneDelegate else {
            assertionFailure()
            throw Self.makeError(message: "The keycloakSceneDelegate is not set")
        }
        
        let viewController = try await keycloakSceneDelegate.requestViewControllerForPresenting()
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
         
            assert(Thread.isMainThread)

            let menu = UIAlertController(title: title, message: message, preferredStyle: UIDevice.current.actionSheetIfPhoneAndAlertOtherwise)
                        
            let authenticateAction = UIAlertAction(title: CommonString.Word.Authenticate, style: .default) { _ in
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
            
            let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: .cancel) { _ in
                continuation.resume(throwing: KeycloakDialogError.userHasCancelled)
                return
            }
            
            menu.addAction(authenticateAction)
            menu.addAction(cancelAction)
            
            viewController.present(menu, animated: true, completion: nil)

        }

    }


    @MainActor
    private func openAppDialogKeycloakSignatureKeyChanged() async throws -> Bool {
        os_log("🧥 Call to openAppDialogKeycloakSignatureKeyChanged", log: KeycloakManager.log, type: .info)
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
            let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: .cancel) { _ in
                continuation.resume(returning: false)
            }
            menu.addAction(updateAction)
            menu.addAction(cancelAction)
            viewController.present(menu, animated: true)
        }
    }

    
    /// Throws a KeycloakDialogError
    private func openKeycloakAuthenticationRequiredTokenExpired(internalKeycloakState iks: InternalKeycloakState, ownedCryptoId: ObvCryptoId) async throws {
        os_log("🧥 Call to openKeycloakAuthenticationRequiredTokenExpired", log: KeycloakManager.log, type: .info)
        try await selfTestAndOpenKeycloakAuthenticationRequired(serverURL: iks.keycloakServer,
                                                                clientId: iks.clientId,
                                                                clientSecret: iks.clientSecret,
                                                                ownedCryptoId: ownedCryptoId,
                                                                title: Strings.AuthenticationRequiredTokenExpired,
                                                                message: Strings.AuthenticationRequiredTokenExpiredMessage)
    }


    /// Only called from `getInternalKeycloakState`. Throws a KeycloakDialogError
    private func openKeycloakAuthenticationRequiredTokenExpired(obvKeycloakState oks: ObvKeycloakState, ownedCryptoId: ObvCryptoId) async throws {
        os_log("🧥 Call to openKeycloakAuthenticationRequiredTokenExpired", log: KeycloakManager.log, type: .info)
        try await selfTestAndOpenKeycloakAuthenticationRequired(serverURL: oks.keycloakServer,
                                                                clientId: oks.clientId,
                                                                clientSecret: oks.clientSecret,
                                                                ownedCryptoId: ownedCryptoId,
                                                                title: Strings.AuthenticationRequiredTokenExpired,
                                                                message: Strings.AuthenticationRequiredTokenExpiredMessage)
    }


    /// Throws a KeycloakDialogError
    private func openKeycloakAuthenticationRequiredUserIdChanged(internalKeycloakState iks: InternalKeycloakState, ownedCryptoId: ObvCryptoId) async throws {
        os_log("🧥 Call to openKeycloakAuthenticationRequiredUserIdChanged", log: KeycloakManager.log, type: .info)
        try await selfTestAndOpenKeycloakAuthenticationRequired(serverURL: iks.keycloakServer,
                                                                clientId: iks.clientId,
                                                                clientSecret: iks.clientSecret,
                                                                ownedCryptoId: ownedCryptoId,
                                                                title: Strings.AuthenticationRequiredUserIdChanged,
                                                                message: Strings.AuthenticationRequiredUserIdChangedMessage)
    }


    /// Shall only be called from selfTestAndOpenKeycloakAuthenticationRequired
    private func selfRevocationTest(serverURL: URL, selfRevocationTestNonce: String) async throws -> Bool {
        os_log("🧥 Call to selfRevocationTest", log: KeycloakManager.log, type: .info)

        let selfRevocationTestJSON = SelfRevocationTestJSON(selfRevocationTestNonce: selfRevocationTestNonce)
        let encoder = JSONEncoder()
        let dataToSend = try encoder.encode(selfRevocationTestJSON)

        let apiResultForRevocationTestPath: KeycloakManager.ApiResultForRevocationTestPath = try await keycloakApiRequest(serverURL: serverURL, path: KeycloakManager.revocationTestPath, accessToken: nil, dataToSend: dataToSend)
        return apiResultForRevocationTestPath.isRevoked
    }


    /// Throws a KeycloakDialogError
    @MainActor
    private func openKeycloakRevocation(serverURL: URL, authState: OIDAuthState, ownedCryptoId: ObvCryptoId) async throws {
        os_log("🧥 Call to openKeycloakRevocation", log: KeycloakManager.log, type: .info)
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
            
            let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: .cancel) { _ in
                continuation.resume(throwing: KeycloakDialogError.userHasCancelled)
            }
            
            menu.addAction(revokeAction)
            menu.addAction(cancelAction)
            
            viewController.present(menu, animated: true, completion: nil)

        }
            
    }


    @MainActor
    func openKeycloakRevocationForbidden() async throws {
        os_log("🧥 Call to openKeycloakRevocationForbidden", log: KeycloakManager.log, type: .info)
        assert(Thread.isMainThread)

        guard let keycloakSceneDelegate = await keycloakSceneDelegate else {
            assertionFailure()
            throw Self.makeError(message: "The keycloakSceneDelegate is not set")
        }
        
        let viewController = try await keycloakSceneDelegate.requestViewControllerForPresenting()

        let alert = UIAlertController(title: Strings.KeycloakRevocationForbidden.title, message: Strings.KeycloakRevocationForbidden.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction.init(title: CommonString.Word.Ok, style: .cancel))
        viewController.present(alert, animated: true)
    }


    /// Throws a KeycloakDialogError
    @MainActor
    func openAddContact(userDetail: UserDetails, ownedCryptoId: ObvCryptoId) async throws {
        os_log("🧥 Call to openAddContact", log: KeycloakManager.log, type: .info)

        assert(Thread.isMainThread)

        guard let identity = userDetail.identity else { return }

        guard let keycloakSceneDelegate = await keycloakSceneDelegate else {
            assertionFailure()
            throw Self.makeError(message: "The keycloakSceneDelegate is not set")
        }
        
        let viewController = try await keycloakSceneDelegate.requestViewControllerForPresenting()
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        
            assert(Thread.isMainThread)

            let menu = UIAlertController(title: Strings.AddContactTitle, message: Strings.AddContactMessage(userDetail.firstNameAndLastName), preferredStyle: UIDevice.current.actionSheetIfPhoneAndAlertOtherwise)
            
            let addContactAction = UIAlertAction(title: Strings.AddContactButton, style: .default) { _ in
                Task { [weak self] in
                    guard let _self = self else { return }
                    do {
                        try await _self.addContact(ownedCryptoId: ownedCryptoId, userId: userDetail.id, userIdentity: identity)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: KeycloakDialogError.keycloakManagerError(error))
                    }
                }
            }
            
            let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: .cancel) { _ in
                continuation.resume(throwing: KeycloakDialogError.userHasCancelled)
            }
            
            menu.addAction(addContactAction)
            menu.addAction(cancelAction)
            
            viewController.present(menu, animated: true, completion: nil)

        }
        
    }


    /// This method is called each time the user re-authenticates succesfully. It saves the fresh jwks and auth state both in cache and within the engine.
    /// It also forces a new sychronization with the keycloak server.
    private func reAuthenticationSuccessful(ownedCryptoId: ObvCryptoId, jwks: ObvJWKSet, authState: OIDAuthState) {
        os_log("🧥 Call to reAuthenticationSuccessful", log: KeycloakManager.log, type: .info)

        // Save the jwks within the engine

        do {
            try obvEngine.saveKeycloakJwks(with: ownedCryptoId, jwks: jwks)
        } catch {
            os_log("🧥 Could not save the new jwks within the engine", log: KeycloakManager.log, type: .fault)
            assertionFailure()
            return
        }

        do {
            let rawAuthState = try authState.serialize()
            try obvEngine.saveKeycloakAuthState(with: ownedCryptoId, rawAuthState: rawAuthState)
        } catch {
            os_log("🧥 Could not save the new auth state within the engine", log: KeycloakManager.log, type: .fault)
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

        static let AuthenticationRequiredTokenExpired = NSLocalizedString("AUTHENTICATION_REQUIRED", comment: "")
        static let AuthenticationRequiredTokenExpiredMessage = NSLocalizedString("AUTHENTICATION_REQUIRED_TOKEN_EXPIRED_MESSAGE", comment: "")

        static let AuthenticationRequiredUserIdChanged = NSLocalizedString("USER_CHANGE_DETECTED", comment: "")
        static let AuthenticationRequiredUserIdChangedMessage = NSLocalizedString("AUTHENTICATION_REQUIRED_USER_ID_CHANGED_MESSAGE", comment: "")

        static let KeycloakRevocation = NSLocalizedString("KEYCLOAK_REVOCATION", comment: "")
        static let KeycloakRevocationButton = NSLocalizedString("KEYCLOAK_REVOCATION_BUTTON", comment: "")
        static let KeycloakRevocationMessage = NSLocalizedString("KEYCLOAK_REVOCATION_MESSAGE", comment: "")
        static let KeycloakRevocationSuccessful = NSLocalizedString("KEYCLOAK_REVOCATION_SUCCESSFUL", comment: "")
        static let KeycloakRevocationFailure = NSLocalizedString("KEYCLOAK_REVOCATION_FAILURE", comment: "")

        struct KeycloakRevocationForbidden {
            static let title = NSLocalizedString("KEYCLOAK_REVOCATION_FORBIDDEN_TITLE", comment: "")
            static let message = NSLocalizedString("KEYCLOAK_REVOCATION_FORBIDDEN_MESSAGE", comment: "")
        }

        static let AddContactButton = NSLocalizedString("ADD_CONTACT_BUTTON", comment: "")
        static let AddContactTitle = NSLocalizedString("ADD_CONTACT_TITLE", comment: "")
        static let AddContactMessage = { (contactName: String) in
            String.localizedStringWithFormat(NSLocalizedString("You selected to add %@ to your contacts. Do you want to proceed?", comment: "Alert message"), contactName)
        }

        struct KeycloakIdentityWasRevokedAlert {
            static let title = NSLocalizedString("DIALOG_TITLE_KEYCLOAK_IDENTITY_WAS_REVOKED", comment: "")
            static let message = NSLocalizedString("DIALOG_MESSAGE_KEYCLOAK_IDENTITY_WAS_REVOKED", comment: "")
        }

        struct KeycloakSignatureKeyChangedAlert {
            static let title = NSLocalizedString("DIALOG_TITLE_KEYCLOAK_SIGNATURE_KEY_CHANGED", comment: "")
            static let message = NSLocalizedString("DIALOG_MESSAGE_KEYCLOAK_SIGNATURE_KEY_CHANGED", comment: "")
            static let positiveButtonTitle = NSLocalizedString("BUTTON_LABEL_UPDATE_KEY", comment: "")
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
    let latestRevocationListTimestamp: Date?
    let signedOwnedDetails: SignedUserDetails? // Our owned details, signed by the keycloak server, as we know them locally in the identity manager
}


fileprivate extension Task where Success == Never, Failure == Never {
    
    static func sleep(failedAttemps: Int) async throws {
        let halfASecond: Double = 0.5 * Double((Int(1)<<failedAttemps))
        try await Self.sleep(seconds: halfASecond)
    }
    
}


protocol KeycloakSceneDelegate: AnyObject {
   @MainActor func requestViewControllerForPresenting() async throws -> UIViewController
}


// MARK: Extending OIDAuthorizationService to perform async requests

extension OIDAuthorizationService: ObvErrorMaker {
    
    public static let errorDomain = "OIDAuthorizationService"
    
    @MainActor
    class func present(_ request: OIDAuthorizationRequest, presenting presentingViewController: UIViewController, storeSession: (OIDExternalUserAgentSession) -> Void) async throws -> OIDAuthorizationResponse {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OIDAuthorizationResponse, Error>) in
            assert(Thread.isMainThread)
            let session = self.present(request, presenting: presentingViewController) { response, error in
                if let response = response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: error ?? Self.makeError(message: "Could not present authorization request"))
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
                    continuation.resume(throwing: error ?? Self.makeError(message: "Failed to perform request"))
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
                    continuation.resume(throwing: error ?? Self.makeError(message: "Failed to perform request"))
                }
            }
        }
    }

}


// MARK: Extending OIDAuthState to perform async requests
 
extension OIDAuthState: ObvErrorMaker {
    
    public static let errorDomain = "OIDAuthState"

    func performAction() async throws -> (accessToken: String?, idToken: String?) {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(accessToken: String?, idToken: String?), Error>) in
            self.performAction { (accessToken, idToken, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (accessToken, idToken))
                }
            }
        }
    }
        
}
