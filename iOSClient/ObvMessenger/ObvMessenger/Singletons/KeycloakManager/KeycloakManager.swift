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

final class KeycloakManager: NSObject {

    private static var _shared: KeycloakManager?
    private static let sharedQueue = DispatchQueue(label: "KeycloakManager.shared")
    static var shared: KeycloakManager {
        sharedQueue.sync {
            guard let shared = _shared else {
                let keycloakManager = KeycloakManager()
                _shared = keycloakManager
                return keycloakManager
            }
            return shared
        }
    }

    private var currentAuthorizationFlow: OIDExternalUserAgentSession?

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
        assert(OperationQueue.current == internalQueue)
        return _lastSynchronizationDateForOwnedIdentity[ownedIdentity] ?? Date.distantPast
    }
    
    private func setLastSynchronizationDate(forOwnedIdentity ownedIdentity: ObvCryptoId, to date: Date?) {
        assert(OperationQueue.current == internalQueue)
        if let date = date {
            _lastSynchronizationDateForOwnedIdentity[ownedIdentity] = date
        } else {
            _ = _lastSynchronizationDateForOwnedIdentity.removeValue(forKey: ownedIdentity)
        }
    }
    
    private var obvEngine: ObvEngine {
        var obvEngine: ObvEngine! = nil
        if Thread.isMainThread {
            let appDelegate = UIApplication.shared.delegate as! AppDelegate
            obvEngine = appDelegate.obvEngine
        } else {
            var appDelegate: AppDelegate! = nil
            DispatchQueue.main.sync {
                appDelegate = (UIApplication.shared.delegate as! AppDelegate)
                obvEngine = appDelegate.obvEngine
            }
        }
        return obvEngine
    }

    private var currentlySyncingOwnedIdentities = Set<ObvCryptoId>()
    
    private var ownedCryptoIdForOIDAuthState = [OIDAuthState: ObvCryptoId]()
    
    private var rootViewController: UIViewController? {
        assert(Thread.isMainThread)
        return UIApplication.shared.windows
            .first(where: { $0.rootViewController is MetaFlowController })?
            .rootViewController
    }
    
    private lazy var internalUnderlyingQueue = DispatchQueue(label: "KeycloakManager internal queue", qos: .default)
    private lazy var internalQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.underlyingQueue = internalUnderlyingQueue
        queue.maxConcurrentOperationCount = 1
        queue.name = "KeycloakManager internal queue"
        queue.qualityOfService = .default
        return queue
    }()
    

    // MARK: - Public Methods
    
    
    func registerKeycloakManagedOwnedIdentity(ownedCryptoId: ObvCryptoId, firstKeycloakBinding: Bool) {
        os_log("🧥 Call to registerKeycloakManagedOwnedIdentity", log: KeycloakManager.log, type: .info)
        internalQueue.addOperation { [weak self] in

            // Unless this is the first keycloak binding, we synchronize the owned identity with the keycloak server
            
            if !firstKeycloakBinding {
                self?.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: false)
            }
            
        }
    }

    
    /// Returns a view controller that is suitable for presenting another view controller
    private var viewControllerForPresentation: UIViewController? {
        assert(Thread.isMainThread)
        guard var vcToReturn = rootViewController else { return nil }
        while let vc = vcToReturn.presentedViewController {
            vcToReturn = vc
        }
        return vcToReturn
    }
    
    
    func unregisterKeycloakManagedOwnedIdentity(ownedCryptoId: ObvCryptoId, failedAttempts: Int = 0, completion: @escaping (Result<Void, Error>) -> Void) {
        os_log("🧥 Call to unregisterKeycloakManagedOwnedIdentity", log: KeycloakManager.log, type: .info)
        internalQueue.addOperation { [weak self] in
            do {
                self?.setLastSynchronizationDate(forOwnedIdentity: ownedCryptoId, to: nil)
                try self?.obvEngine.unbindOwnedIdentityFromKeycloakServer(ownedCryptoId: ownedCryptoId, completion: completion)
            } catch {
                guard let _self = self else { return }
                guard failedAttempts < _self.maxFailCount else { assertionFailure(); completion(.failure(error)); return}
                self?.internalQueue.schedule(failedAttempts: failedAttempts) {
                    self?.unregisterKeycloakManagedOwnedIdentity(ownedCryptoId: ownedCryptoId, failedAttempts: failedAttempts + 1, completion: completion)
                }
            }
        }
    }
    
    /// When receiving a silent push notification originated in the keycloak server, we sync the managed owned identity associated with the push topic indicated whithin the infos of the push notification
    func forceSyncManagedIdentitiesAssociatedWithPushTopics(_ receivedPushTopic: String, failedAttempts: Int = 0, completion: @escaping (Result<Void, Error>) -> Void) {
        os_log("🧥 Call to syncManagedIdentitiesAssociatedWithPushTopics", log: KeycloakManager.log, type: .info)
        internalQueue.addOperation { [weak self] in
            guard let _self = self else { return }
            do {
                let associatedOwnedIdentities = try _self.obvEngine.getManagedOwnedIdentitiesAssociatedWithThePushTopic(receivedPushTopic)
                associatedOwnedIdentities.forEach { ownedIdentity in
                    self?.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedIdentity.cryptoId, ignoreSynchronizationInterval: true)
                }
                completion(.success(()))
                return
            } catch {
                guard failedAttempts < _self.maxFailCount else { assertionFailure(); completion(.failure(error)); return}
                self?.internalQueue.schedule(failedAttempts: failedAttempts) {
                    self?.forceSyncManagedIdentitiesAssociatedWithPushTopics(receivedPushTopic, failedAttempts: failedAttempts+1, completion: completion)
                }
                return
            }
        }
    }
    
    private func syncAllManagedIdentities(failedAttempts: Int = 0, ignoreSynchronizationInterval: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        os_log("🧥 Call to syncAllManagedIdentities", log: KeycloakManager.log, type: .info)
        internalQueue.addOperation { [weak self] in
            guard let _self = self else { return }
            do {
                let ownedIdentities = (try _self.obvEngine.getOwnedIdentities()).filter({ $0.isKeycloakManaged })
                for ownedIdentity in ownedIdentities {
                    self?.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedIdentity.cryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval)
                }
            } catch {
                guard let _self = self else { return }
                guard failedAttempts < _self.maxFailCount else { assertionFailure(); completion(.failure(error)); return}
                self?.internalQueue.schedule(failedAttempts: failedAttempts) {
                    self?.syncAllManagedIdentities(failedAttempts: failedAttempts + 1, ignoreSynchronizationInterval: ignoreSynchronizationInterval, completion: completion)
                }
            }
        }
    }

    
    func uploadOwnIdentity(ownedCryptoId: ObvCryptoId, completionHandler: @escaping (Result<Void, UploadOwnedIdentityError>) -> Void) {
        os_log("🧥 Call to uploadOwnIdentity", log: KeycloakManager.log, type: .info)
        internalQueue.addOperation { [weak self] in
            
            self?.getInternalKeycloakState(for: ownedCryptoId) { result in

                switch result {

                case .failure(let error):

                    completionHandler(.failure(.unkownError(error)))
                    return

                case .success(let iks):
                    
                    self?.uploadOwnedIdentity(serverURL: iks.keycloakServer, authState: iks.authState, ownedIdentity: ownedCryptoId) { [weak self] result in
                        guard let _self = self else { return }
                        switch result {
                            
                        case .failure(let error):
                            switch error {
                            case .ownedIdentityWasRevoked:
                                completionHandler(.failure(.ownedIdentityWasRevoked))
                                return
                            case .authenticationRequired:
                                self?.openKeycloakAuthenticationRequiredTokenExpired(internalKeycloakState: iks, ownedCryptoId: ownedCryptoId) { [weak self] result in
                                    switch result {
                                    case .failure(let error):
                                        switch error {
                                        case .userHasCancelled:
                                            completionHandler(.failure(.userHasCancelled))
                                            return
                                        case .keycloakManagerError(let error):
                                            completionHandler(.failure(.unkownError(error)))
                                            return
                                        }
                                    case .success:
                                        self?.uploadOwnIdentity(ownedCryptoId: ownedCryptoId, completionHandler: completionHandler)
                                        return
                                    }
                                }
                                return
                            case .userHasCancelled:
                                completionHandler(.failure(.userHasCancelled))
                                return
                            case .identityAlreadyUploaded:
                                assert(OperationQueue.current == _self.internalQueue)
                                self?.openKeycloakRevocationForbidden()
                                completionHandler(.failure(error))
                                return
                            case .badResponse,
                                    .serverError,
                                    .unkownError:
                                self?.internalQueue.schedule(failedAttempts: 1) {
                                    assert(OperationQueue.current == _self.internalQueue)
                                    assert(self?.currentlySyncingOwnedIdentities.contains(ownedCryptoId) == false)
                                    self?.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: false, failedAttempts: 1)
                                }
                                completionHandler(.failure(error))
                                return
                            }
                            
                        case .success:
                            self?.internalQueue.addOperation {
                                self?.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: false)
                            }
                            completionHandler(.success(()))
                            return
                        }
                    }

                }
            }
        }
        
    }

    
    public func search(ownedCryptoId: ObvCryptoId, searchQuery: String?, completionHandler: @escaping (Result<(userDetails: [UserDetails], numberOfMissingResults: Int), SearchError>) -> Void) {
        os_log("🧥 Call to search", log: KeycloakManager.log, type: .info)
        internalQueue.addOperation { [weak self] in
            self?.getInternalKeycloakState(for: ownedCryptoId) { result in

                switch result {

                case .failure(let error):

                    completionHandler(.failure(.unkownError(error)))
                    return

                case .success(let iks):

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
                        completionHandler(.failure(.unkownError(error)))
                        return
                    }

                    self?.keycloakApiRequest(serverURL: iks.keycloakServer, path: KeycloakManager.searchPath, accessToken: iks.accessToken, dataToSend: dataToSend) { (result: Result<KeycloakManager.ApiResultForSearchPath, KeycloakApiRequestError>) in
                        guard let _self = self else { return }
                        assert(OperationQueue.current == _self.internalQueue)
                        switch result {
                        case .failure(let error):
                            completionHandler(.failure(.keycloakApiRequest(error)))
                            return
                        case .success(let result):
                            if let userDetails = result.userDetails {
                                let numberOfMissingResults: Int
                                if let numberOfResultsOnServer = result.numberOfResultsOnServer {
                                    assert(userDetails.count <= numberOfResultsOnServer)
                                    numberOfMissingResults = max(0, numberOfResultsOnServer - userDetails.count)
                                } else {
                                    numberOfMissingResults = 0
                                }
                                completionHandler(.success((userDetails, numberOfMissingResults)))
                                return
                            } else if let errorCode = result.errorCode, let error = KeycloakApiRequestError(rawValue: errorCode) {
                                completionHandler(.failure(.keycloakApiRequest(error)))
                                return
                            } else {
                                completionHandler(.failure(.unkownError(_self.makeError(message: "Unexpected error"))))
                                return
                            }
                        }
                    }

                }
            }
        }

    }

    
    func addContact(ownedCryptoId: ObvCryptoId, userId: String, userIdentity: Data, completionHandler: @escaping (Result<Void, AddContactError>) -> Void) {
        os_log("🧥 Call to addContact", log: KeycloakManager.log, type: .info)

        internalQueue.addOperation { [weak self] in
            self?.getInternalKeycloakState(for: ownedCryptoId) { result in

                switch result {

                case .failure(let error):

                    completionHandler(.failure(.unkownError(error)))
                    return

                case .success(let iks):

                    let addContactJSON = AddContactJSON(userId: userId)
                    let encoder = JSONEncoder()
                    let dataToSend: Data
                    do {
                        dataToSend = try encoder.encode(addContactJSON)
                    } catch(let error) {
                        completionHandler(.failure(.unkownError(error)))
                        return
                    }

                    self?.keycloakApiRequest(serverURL: iks.keycloakServer, path: KeycloakManager.getKeyPath, accessToken: iks.accessToken, dataToSend: dataToSend) { [weak self] (result: Result<KeycloakManager.ApiResultForGetKeyPath, KeycloakApiRequestError>) in
                        guard let _self = self else { return }
                        assert(OperationQueue.current == _self.internalQueue)
                        
                        switch result {
                            
                        case .failure(let error):
                            
                            switch error {
                            case .permissionDenied:
                                completionHandler(.failure(.authenticationRequired))
                                return
                            case .internalError, .invalidRequest, .identityAlreadyUploaded, .badResponse, .decodingFailed:
                                completionHandler(.failure(.badResponse))
                                return
                            case .ownedIdentityWasRevoked:
                                completionHandler(.failure(.ownedIdentityWasRevoked))
                                return
                            }
                            
                        case .success(let result):
                            
                            let signedUserDetails: SignedUserDetails
                            do {
                                guard let signatureVerificationKey = iks.signatureVerificationKey else {
                                    // We did not save the signature key used to sign our own details, se we cannot make sure the details of our future contact are signed with the appropriate key.
                                    // We fail and force a resync that will eventually store this server signature verification key
                                    self?.setLastSynchronizationDate(forOwnedIdentity: ownedCryptoId, to: nil)
                                    self?.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                                    self?.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: false, failedAttempts: 0)
                                    completionHandler(.failure(.willSyncKeycloakServerSignatureKey))
                                    return
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
                                        completionHandler(.failure(.invalidSignature(error)))
                                        return
                                    }
                                    // If we reach this point, the signature is valid but with the wrong signature key --> we force a resync to detect key change and prompt user with a dialog
                                    self?.setLastSynchronizationDate(forOwnedIdentity: ownedCryptoId, to: nil)
                                    self?.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                                    self?.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: false, failedAttempts: 0)
                                    completionHandler(.failure(.willSyncKeycloakServerSignatureKey))
                                    return
                                }
                            }
                            guard signedUserDetails.identity == userIdentity else {
                                completionHandler(.failure(.badResponse))
                                return
                            }
                            do {
                                try self?.obvEngine.addKeycloakContact(with: ownedCryptoId, signedContactDetails: signedUserDetails)
                            } catch(let error) {
                                completionHandler(.failure(.unkownError(error)))
                                return
                            }
                            completionHandler(.success(()))
                            return
                        }

                    }

                }

            }
        }

    }

    
    func authenticate(configuration: OIDServiceConfiguration, clientId: String, clientSecret: String?, ownedCryptoId: ObvCryptoId?, completion: @escaping (Result<OIDAuthState, Error>) -> Void) {

        os_log("🧥 Call to authenticate", log: KeycloakManager.log, type: .info)

        let kRedirectURI = "https://\(ObvMessengerConstants.Host.forOpenIdRedirect)/"

        guard let redirectURI = URL(string: kRedirectURI) else {
            completion(.failure(KeycloakManager.makeError(message: "Error creating URL for : \(kRedirectURI)")))
            return
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

        DispatchQueue.main.async { [weak self] in
            guard let _self = self else { return }
            guard let viewController = _self.viewControllerForPresentation else {
                completion(.failure(KeycloakManager.makeError(message: "The view controller was deallocated")))
                return
            }
            AppStateManager.shared.ignoreNextResignActiveTransition = true
            _self.currentAuthorizationFlow = OIDAuthorizationService.present(request, presenting: viewController) { (authorizationResponse, error) in
                os_log("🧥 OIDAuthorizationService did return", log: KeycloakManager.log, type: .info)
                guard error == nil && authorizationResponse != nil else {
                    os_log("🧥 Could not perform authorization request: %{public}@", log: KeycloakManager.log, type: .fault, error!.localizedDescription)
                    completion(.failure(error!))
                    return
                }

                let authState: OIDAuthState
                if let ownedCryptoId = ownedCryptoId,
                   let keycloakState = try? _self.obvEngine.getOwnedIdentityKeycloakState(with: ownedCryptoId).obvKeycloakState,
                   let rawAuthState = keycloakState.rawAuthState,
                   let _authState = OIDAuthState.deserialize(from: rawAuthState) {
                    authState = _authState
                    authState.update(with: authorizationResponse, error: nil)
                } else {
                    authState = OIDAuthState(authorizationResponse: authorizationResponse!)
                }
                _self.ownedCryptoIdForOIDAuthState[authState] = ownedCryptoId // It's nil during onboarding
                authState.stateChangeDelegate = self

                guard let authorizationResponse = authorizationResponse else {
                    completion(.failure(KeycloakManager.makeError(message: "No response from OIDAuthorizationService")))
                    return
                }

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

                OIDAuthorizationService.perform(tokenRequest) { tokenResponse, error in
                    authState.update(with: tokenResponse, error: error)
                    guard error == nil else {
                        os_log("🧥 Could not perform token request: %{public}@", log: KeycloakManager.log, type: .fault, error!.localizedDescription)
                        completion(.failure(error!))
                        return
                    }
                    completion(.success(authState))
                }
            }
        }

    }

    
    func discoverKeycloakServer(for serverURL: URL, completionHandler: @escaping (Result<(ObvJWKSet, OIDServiceConfiguration), Error>) -> Void) {

        os_log("🧥 Call to discoverKeycloakServer", log: KeycloakManager.log, type: .info)

        OIDAuthorizationService.discoverConfiguration(forIssuer: serverURL) { [weak self] (configuration, error) in
            guard error == nil else {
                completionHandler(.failure(KeycloakManager.makeError(message: "Error retrieving discovery document: \(error!.localizedDescription)")))
                return
            }
            guard let configuration = configuration else {
                completionHandler(.failure(KeycloakManager.makeError(message: "Error retrieving discovery document")))
                return
            }
            guard let discoveryDocument = configuration.discoveryDocument else {
                completionHandler(.failure(KeycloakManager.makeError(message: "No discovery document available")))
                return
            }
            self?.getJkws(url: discoveryDocument.jwksURL) { result in
                switch result {
                case .failure(let error):
                    completionHandler(.failure(error))
                case .success(let jwksData):
                    let jwks: ObvJWKSet
                    do {
                        jwks = try ObvJWKSet(data: jwksData)
                    } catch {
                        completionHandler(.failure(KeycloakManager.makeError(message: "Cannot build JWKS from received data")))
                        return
                    }
                    completionHandler(.success((jwks, configuration)))
                }
            }
        }
    }

    
    func getOwnDetails(keycloakServer: URL, authState: OIDAuthState, clientSecret: String?, jwks: ObvJWKSet, latestLocalRevocationListTimestamp: Date?, completion: @escaping (Result<(keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff), GetOwnDetailsError>) -> Void) {
        
        os_log("🧥 Call to getOwnDetails", log: KeycloakManager.log, type: .info)

        authState.performAction { (accessToken, idToken, error) in
            
            guard error == nil && accessToken != nil else {
                os_log("🧥 Authentication required in getOwnDetails", log: KeycloakManager.log, type: .info)
                completion(.failure(.authenticationRequired))
                return
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

            self.keycloakApiRequest(serverURL: keycloakServer, path: KeycloakManager.mePath, accessToken: accessToken!, dataToSend: dataToSend) { [weak self] (result: Result<KeycloakManager.ApiResultForMePath, KeycloakApiRequestError>) in
                guard let _self = self else { return }
                assert(OperationQueue.current == _self.internalQueue)
                
                os_log("🧥 The call to the /me entry on the keycloak server returned to the getOwnDetails method", log: KeycloakManager.log, type: .info)

                switch result {
                case .failure(let error):
                    switch error {
                    case .permissionDenied:
                        os_log("🧥 The keycloak server returned a permission denied error", log: KeycloakManager.log, type: .error)
                        completion(.failure(.authenticationRequired))
                        return
                    case .internalError, .invalidRequest, .identityAlreadyUploaded, .badResponse, .decodingFailed:
                        os_log("🧥 The keycloak server returned an error", log: KeycloakManager.log, type: .error)
                        completion(.failure(.serverError))
                        return
                    case .ownedIdentityWasRevoked:
                        os_log("🧥 The keycloak server indicates that the owned identity was revoked", log: KeycloakManager.log, type: .error)
                        completion(.failure(.ownedIdentityWasRevoked))
                        return
                    }
                case .success(let apiResult):
                    os_log("🧥 The call to the /me entry point succeeded", log: KeycloakManager.log, type: .info)
                    let keycloakServerSignatureVerificationKey: ObvJWK
                    let signedUserDetails: SignedUserDetails
                    do {
                        (signedUserDetails, keycloakServerSignatureVerificationKey) = try SignedUserDetails.verifySignedUserDetails(apiResult.signature, with: jwks)
                    } catch {
                        os_log("🧥 The server signature is invalid", log: KeycloakManager.log, type: .error)
                        completion(.failure(.invalidSignature(error)))
                        return
                    }
                    os_log("🧥 The server signature is valid", log: KeycloakManager.log, type: .info)
                    let keycloakUserDetailsAndStuff = KeycloakUserDetailsAndStuff(
                        signedUserDetails: signedUserDetails,
                        serverSignatureVerificationKey: keycloakServerSignatureVerificationKey,
                        server: apiResult.server,
                        apiKey: apiResult.apiKey,
                        pushTopics: apiResult.pushTopics,
                        selfRevocationTestNonce: apiResult.selfRevocationTestNonce)
                    let keycloakServerRevocationsAndStuff = KeycloakServerRevocationsAndStuff(
                        revocationAllowed: apiResult.revocationAllowed,
                        currentServerTimestamp: apiResult.currentServerTimestamp,
                        signedRevocations: apiResult.signedRevocations,
                        minimumIOSBuildVersion: apiResult.minimumIOSBuildVersion)
                    os_log("🧥 Calling the completion of the getOwnDetails method", log: KeycloakManager.log, type: .info)
                    completion(.success((keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff)))
                    return
                }
            }

        }
    }
    
    
    /// Called when the user resumes an OpendId connect authentication
    func resumeExternalUserAgentFlow(with url: URL) -> Bool {
        os_log("🧥 Resume External Agent flow...", log: KeycloakManager.log, type: .info)
        assert(Thread.isMainThread)
        if let authorizationFlow = self.currentAuthorizationFlow, authorizationFlow.resumeExternalUserAgentFlow(with: url) {
            os_log("🧥 Resume External Agent succeed", log: KeycloakManager.log, type: .info)
            self.currentAuthorizationFlow = nil
            return true
        } else {
            os_log("🧥 Resume External Agent flow failed", log: KeycloakManager.log, type: .error)
            return false
        }
    }

    
    // MARK: - Private Methods and helpers
    
    
    private func synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ObvCryptoId, ignoreSynchronizationInterval: Bool, failedAttempts: Int = 0) {

        assert(OperationQueue.current == internalQueue)
        os_log("🧥 Call to synchronizeOwnedIdentityWithKeycloakServer", log: KeycloakManager.log, type: .info)

        getInternalKeycloakState(for: ownedCryptoId) { [weak self] result in
            
            guard let _self = self else { return }
            
            assert(OperationQueue.current == _self.internalQueue)
            
            switch result {

            case .failure(let error):
                
                switch error {
                case .userHasCancelled:
                    assert(OperationQueue.current == _self.internalQueue)
                    _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                    return
                case .unkownError(let error):
                    _self.retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                    return
                }

            case .success(let iks):

                let lastSynchronizationDate = _self.getLastSynchronizationDate(forOwnedIdentity: ownedCryptoId)
                
                assert(OperationQueue.current == _self.internalQueue)
                assert(Date().timeIntervalSince(lastSynchronizationDate) > 0)
                guard Date().timeIntervalSince(lastSynchronizationDate) > _self.synchronizationInterval || ignoreSynchronizationInterval else {
                    return
                }

                // Mark the identity as currently syncing --> un-mark it as soon as success or failure

                assert(OperationQueue.current == _self.internalQueue)
                guard !_self.currentlySyncingOwnedIdentities.contains(ownedCryptoId) else {
                    os_log("🧥 Trying to sync an owned identity that is already syncing", log: KeycloakManager.log, type: .error)
                    return
                }
                assert(OperationQueue.current == _self.internalQueue)
                _self.currentlySyncingOwnedIdentities.insert(ownedCryptoId)
                
                // If we reach this point, we should synchronize the owned identity with the keycloak server
                
                let latestLocalRevocationListTimestamp = iks.latestRevocationListTimestamp ?? Date.distantPast
                _self.getOwnDetails(keycloakServer: iks.keycloakServer, authState: iks.authState, clientSecret: iks.clientSecret, jwks: iks.jwks, latestLocalRevocationListTimestamp: latestLocalRevocationListTimestamp) { result in

                    switch result {

                    case .failure(let error):
                        switch error {
                        case .authenticationRequired:
                            assert(OperationQueue.current == _self.internalQueue)
                            _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                            _self.openKeycloakAuthenticationRequiredTokenExpired(internalKeycloakState: iks, ownedCryptoId: ownedCryptoId) { result in
                                switch result {
                                case .failure(let error):
                                    switch error {
                                    case .userHasCancelled:
                                        return
                                    case .keycloakManagerError(let error):
                                        assertionFailure(error.localizedDescription)
                                        return
                                    }
                                case .success:
                                    assert(OperationQueue.current == _self.internalQueue)
                                    _self.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, failedAttempts: failedAttempts + 1)
                                    return
                                }
                            }
                            return
                        case .badResponse, .invalidSignature, .serverError, .unkownError:
                            _self.retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                            return
                        case .ownedIdentityWasRevoked:
                            _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                            ObvMessengerInternalNotification.userOwnedIdentityWasRevokedByKeycloak(ownedCryptoId: ownedCryptoId)
                                .postOnDispatchQueue()
                            return
                        }

                    case .success(let (keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff)):
                        
                        os_log("🧥 Successfully downloaded own details from keycloak server", log: KeycloakManager.log, type: .info)

                        // Check that our Olvid version is not outdated
                        
                        if let minimumBuildVersion = keycloakServerRevocationsAndStuff.minimumIOSBuildVersion {
                            if ObvMessengerConstants.bundleVersionAsInt < minimumBuildVersion {
                                ObvMessengerInternalNotification.installedOlvidAppIsOutdated(presentingViewController: nil)
                                    .postOnDispatchQueue()
                            }
                        }
                        
                        let userDetailsOnServer = keycloakUserDetailsAndStuff.signedUserDetails.userDetails
                        
                        // Verify that the signature key matches what is stored, ask for user confirmation otherwise

                        do {
                            if let signatureVerificationKeyKnownByEngine = iks.signatureVerificationKey {
                                guard signatureVerificationKeyKnownByEngine == keycloakUserDetailsAndStuff.serverSignatureVerificationKey else {
                                    // The server signature key stored within the engine is distinct from one returned by the server. This is unexpected as the server is not supposed to change signature key as often as he changes his shirt. We ask the user what she want's to do.
                                    assert(OperationQueue.current == _self.internalQueue)
                                    _self.openAppDialogKeycloakSignatureKeyChanged { userAcceptedToUpdateSignatureVerificationKeyKnownByEngine in
                                        if userAcceptedToUpdateSignatureVerificationKeyKnownByEngine {
                                            do {
                                                try _self.obvEngine.setOwnedIdentityKeycloakSignatureKey(ownedCryptoId: ownedCryptoId, keycloakServersignatureVerificationKey: keycloakUserDetailsAndStuff.serverSignatureVerificationKey)
                                                assert(OperationQueue.current == _self.internalQueue)
                                                _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                                                _self.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, failedAttempts: failedAttempts + 1)
                                            } catch {
                                                os_log("🧥 Could not store the keycloak server signature key within the engine (2): %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
                                                _self.retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                                                return
                                            }
                                        } else {
                                            // The user refused to update the signature key stored within the engine. There is not much we can do...
                                            assert(OperationQueue.current == _self.internalQueue)
                                            _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                                            return
                                        }
                                    }
                                    return
                                }
                            } else {
                                // The engine is not aware of the server signature key, we store it now
                                do {
                                    try _self.obvEngine.setOwnedIdentityKeycloakSignatureKey(ownedCryptoId: ownedCryptoId, keycloakServersignatureVerificationKey: keycloakUserDetailsAndStuff.serverSignatureVerificationKey)
                                } catch {
                                    os_log("🧥 Could not store the keycloak server signature key within the engine: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
                                    _self.retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                                    return
                                }
                                // If we reach this point, the signature key has been stored within the engine, we can continue
                            }
                        }
                        
                        // If we reach this point, the engine is aware of the server signature key, and stores exactly the same value as the one just returned
                        os_log("🧥 The server signature verification key matches the one stored locally", log: KeycloakManager.log, type: .info)

                        // We synchronise the UserId
                        
                        let previousUserId: String?
                        do {
                            previousUserId = try _self.obvEngine.getOwnedIdentityKeycloakUserId(with: ownedCryptoId)
                        } catch {
                            os_log("🧥 Could not get Keycloak UserId of owned identity: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
                            _self.retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                            return
                        }
                        
                        if let previousUserId = previousUserId {
                            // There was a previous UserId. If it is identical to the one returned by the keycloak server, no problem. Otherwise, we have work to do before retrying to synchronize
                            guard previousUserId == userDetailsOnServer.id else {
                                // The userId changed on keycloak --> probably an authentication with the wrong login check the identity and only update id locally if the identity is the same
                                if ownedCryptoId.getIdentity() == userDetailsOnServer.identity {
                                    assert(OperationQueue.current == _self.internalQueue)
                                    do {
                                        try _self.obvEngine.setOwnedIdentityKeycloakUserId(with: ownedCryptoId, userId: userDetailsOnServer.id)
                                    } catch {
                                        os_log("🧥 Coult not set the new user id within the engine: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
                                        _self.retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                                        return
                                    }
                                    _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                                    _self.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, failedAttempts: failedAttempts)
                                    return
                                } else {
                                    assert(OperationQueue.current == _self.internalQueue)
                                    _self.openKeycloakAuthenticationRequiredUserIdChanged(internalKeycloakState: iks, ownedCryptoId: ownedCryptoId) { result in
                                        switch result {
                                        case .failure(let error):
                                            switch error {
                                            case .userHasCancelled:
                                                assert(OperationQueue.current == _self.internalQueue)
                                                _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                                            case .keycloakManagerError:
                                                _self.retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                                            }
                                            return
                                        case .success:
                                            assert(OperationQueue.current == _self.internalQueue)
                                            _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                                            _self.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, failedAttempts: failedAttempts)
                                            return
                                        }
                                    }
                                    return
                                }
                            }
                        } else {
                            // No previous user Id. We can save the one just returned by the keycloak server
                            do {
                                try _self.obvEngine.setOwnedIdentityKeycloakUserId(with: ownedCryptoId, userId: userDetailsOnServer.id)
                                assert(OperationQueue.current == _self.internalQueue)
                                _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                            } catch {
                                os_log("🧥 Coult not set the new user id within the engine: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
                                _self.retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                                return
                            }
                        }
                        
                        // If we reach this point, the clientId are identical on the server and on this device
                        // If the owned olvid identity was never uploaded, we do it now.
                        
                        guard let identityOnServer = userDetailsOnServer.identity, let cryptoIdOnServer = try? ObvCryptoId(identity: identityOnServer) else {
                            // Upload the owned olvid identity
                            _self.uploadOwnedIdentity(serverURL: iks.keycloakServer, authState: iks.authState, ownedIdentity: ownedCryptoId) { result in
                                switch result {
                                case .failure(let error):
                                    switch error {
                                    case .ownedIdentityWasRevoked:
                                        _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                                        ObvMessengerInternalNotification.userOwnedIdentityWasRevokedByKeycloak(ownedCryptoId: ownedCryptoId)
                                            .postOnDispatchQueue()
                                        return
                                    case .userHasCancelled:
                                        assert(OperationQueue.current == _self.internalQueue)
                                        _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                                    case .authenticationRequired:
                                        assert(OperationQueue.current == _self.internalQueue)
                                        _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                                        _self.openKeycloakAuthenticationRequiredTokenExpired(internalKeycloakState: iks, ownedCryptoId: ownedCryptoId) { result in
                                            switch result {
                                            case .failure(let error):
                                                switch error {
                                                case .userHasCancelled:
                                                    return
                                                case .keycloakManagerError(let error):
                                                    assertionFailure(error.localizedDescription)
                                                    return
                                                }
                                            case .success:
                                                _self.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, failedAttempts: failedAttempts + 1)
                                                return
                                            }
                                        }
                                        return
                                    case .serverError,
                                            .badResponse,
                                            .identityAlreadyUploaded,
                                            .unkownError:
                                        guard failedAttempts < _self.maxFailCount else {
                                            assert(OperationQueue.current == _self.internalQueue)
                                            _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                                            assertionFailure()
                                            return
                                        }
                                        _self.internalQueue.schedule(failedAttempts: failedAttempts) {
                                            assert(OperationQueue.current == _self.internalQueue)
                                            _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                                            _self.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, failedAttempts: failedAttempts + 1)
                                        }
                                        return
                                    }
                                case .success:
                                    // We uploaded our own key --> re-sync
                                    assert(OperationQueue.current == _self.internalQueue)
                                    _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                                    _self.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval)
                                }
                            }
                            return
                        }
                        
                        // If we reach this point, there is an identity on the server. We make sure it is the correct one.

                        guard cryptoIdOnServer == ownedCryptoId else {
                            // The olvid identity on the server does not match the one on this device. The old one should be revoked.
                            if !keycloakServerRevocationsAndStuff.revocationAllowed {
                                assert(OperationQueue.current == _self.internalQueue)
                                _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                                _self.openKeycloakRevocationForbidden()
                            } else {
                                assert(OperationQueue.current == _self.internalQueue)
                                _self.openKeycloakRevocation(serverURL: iks.keycloakServer, authState: iks.authState, ownedCryptoId: ownedCryptoId) { result in
                                    switch result {
                                    case .failure(let error):
                                        switch error {
                                        case .userHasCancelled:
                                            assert(OperationQueue.current == _self.internalQueue)
                                            _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                                            return
                                        case .keycloakManagerError(let error):
                                            os_log("🧥 Could not perform keycloak revocation: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
                                            guard failedAttempts < _self.maxFailCount else {
                                                assert(OperationQueue.current == _self.internalQueue)
                                                _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                                                assertionFailure()
                                                return
                                            }
                                            _self.internalQueue.schedule(failedAttempts: failedAttempts) {
                                                assert(OperationQueue.current == _self.internalQueue)
                                                _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                                                _self.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, failedAttempts: failedAttempts + 1)
                                            }
                                            return
                                        }
                                    case .success:
                                        // We revoqued the previous identity --> re-sync
                                        assert(OperationQueue.current == _self.internalQueue)
                                        _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                                        _self.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval)
                                    }
                                }
                            }
                            return
                        }

                        // If we reach this point, the owned identity on the server matches the one stored locally.
                        
                        // We make sure the engine knows about the signed details returned by the keycloak server. If not, we update our local details
                        
                        guard let localSignedOwnedDetails = iks.signedOwnedDetails else {
                            os_log("🧥 We do not have signed owned details locally, we store the ones returned by the keycloak server now.", log: KeycloakManager.log, type: .info)
                            // The engine is not aware of the signed details from the keycloak server, so we store them now
                            _self.updatePublishedIdentityDetailsOfOwnedIdentityUsingKeycloakInformations(
                                ownedCryptoId: ownedCryptoId,
                                ignoreSynchronizationInterval: ignoreSynchronizationInterval,
                                currentFailedAttempts: failedAttempts,
                                keycloakUserDetailsAndStuff: keycloakUserDetailsAndStuff)
                            return
                        }
                        
                        // If we reach this point, the server returned signed owned details, and the engine knows about signed owned details as well.
                        // We must compare them to make sure they match. If the signature was have on our owned details is too old, we store/publish the one we just received.
                        guard localSignedOwnedDetails.identical(to: keycloakUserDetailsAndStuff.signedUserDetails, acceptableTimestampsDifference: KeycloakManager.signedOwnedDetailsRenewalInterval) else {
                            os_log("🧥 The owned identity core details returned by the server differ from the ones stored locally. We update the local details.", log: KeycloakManager.log, type: .info)
                            // The details on the server differ from the one stored on device. We should update them locally.
                            _self.updatePublishedIdentityDetailsOfOwnedIdentityUsingKeycloakInformations(
                                ownedCryptoId: ownedCryptoId,
                                ignoreSynchronizationInterval: ignoreSynchronizationInterval,
                                currentFailedAttempts: failedAttempts,
                                keycloakUserDetailsAndStuff: keycloakUserDetailsAndStuff)
                            return
                        }
                        
                        // If we reach this point, the details on the server are identical to the ones stored locally.
                        // We update the current API key if needed
                        
                        let apiKey: UUID
                        do {
                            apiKey = try _self.obvEngine.getApiKeyForOwnedIdentity(with: ownedCryptoId)
                        } catch {
                            os_log("🧥 Could not retrieve the current API key from the owned identity.", log: KeycloakManager.log, type: .fault)
                            _self.retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                            return
                        }
                        
                        if let apiKeyOnServer = keycloakUserDetailsAndStuff.apiKey {
                            guard apiKey == apiKeyOnServer else {
                                // The api key returned by the server differs from the one store locally. We update the local key
                                do {
                                    try _self.obvEngine.setAPIKey(for: ownedCryptoId, apiKey: apiKeyOnServer, keycloakServerURL: iks.keycloakServer)
                                } catch {
                                    os_log("🧥 Could not update the local API key with the new one returned by the server.", log: KeycloakManager.log, type: .fault)
                                    _self.retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                                    return
                                }
                                assert(OperationQueue.current == _self.internalQueue)
                                _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                                _self.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, failedAttempts: failedAttempts)
                                return
                            }
                        }
                        
                        // If we reach this point, the API key stored locally is ok.
                        
                        // We update the Keycloak push topics stored within the engine
                        
                        do {
                            try _self.obvEngine.updateKeycloakPushTopicsIfNeeded(ownedCryptoId: ownedCryptoId, pushTopics: keycloakUserDetailsAndStuff.pushTopics)
                        } catch {
                            os_log("🧥 Could not update the engine using the push topics returned by the server.", log: KeycloakManager.log, type: .fault)
                            _self.retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                            return
                        }
                        
                        // If we reach this point, we managed to pass the push topics to the engine

                        // We reset the self revocation test nonce stored within the engine
                        
                        do {
                            try _self.obvEngine.setOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoId: ownedCryptoId, newSelfRevocationTestNonce: keycloakUserDetailsAndStuff.selfRevocationTestNonce)
                        } catch {
                            os_log("🧥 Could not update the self revocation test nonce using the nonce returned by the server.", log: KeycloakManager.log, type: .fault)
                            _self.retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                            return
                        }
                        
                        // If we reach this point, we successfully reset the self revocation test nonce stored within the engine
                        
                        // Update revocation list and latest revocation list timestamp iff the server returned signed revocations (an empty list is ok) and a current server timestamp

                        if let signedRevocations = keycloakServerRevocationsAndStuff.signedRevocations, let currentServerTimestamp = keycloakServerRevocationsAndStuff.currentServerTimestamp {
                            os_log("🧥 The server returned %d signed revocations, we update the engine now", log: KeycloakManager.log, type: .fault, signedRevocations.count)
                            do {
                                try _self.obvEngine.updateKeycloakRevocationList(
                                    ownedCryptoId: ownedCryptoId,
                                    latestRevocationListTimestamp: currentServerTimestamp,
                                    signedRevocations: signedRevocations)
                            } catch {
                                os_log("🧥 Could not update the keycloak revocation list: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
                                _self.retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: failedAttempts)
                                return
                            }
                            os_log("🧥 The engine was updated using the the revocations returned by the server", log: KeycloakManager.log, type: .fault)
                        }
                        
                        // We are done with the sync !!! We can update the sync timestamp

                        os_log("🧥 Keycloak server synchronization succeeded!", log: KeycloakManager.log, type: .info)
                        assert(OperationQueue.current == _self.internalQueue)
                        _self.setLastSynchronizationDate(forOwnedIdentity: ownedCryptoId, to: Date())
                        _self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
                        _self.internalQueue.schedule(deadline: .now() + .seconds(Int(_self.synchronizationInterval + 10))) {
                            // Although it is very unlikely that the view controller still exist, we try to resync anyway
                            _self.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval)
                        }
                    }
                }

            }
            
        }


        
        
    }
    
    
    /// Exclusively called from `synchronizeOwnedIdentityWithKeycloakServer` when an error occurs in that method.
    private func retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: Error, ownedCryptoId: ObvCryptoId, ignoreSynchronizationInterval: Bool, currentFailedAttempts: Int) {
        assert(OperationQueue.current == self.internalQueue)
        guard currentFailedAttempts < self.maxFailCount else {
            self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
            assertionFailure(error.localizedDescription)
            return
        }
        self.internalQueue.schedule(failedAttempts: currentFailedAttempts) {
            self.currentlySyncingOwnedIdentities.remove(ownedCryptoId)
            self.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, failedAttempts: currentFailedAttempts + 1)
        }
    }

    
    /// Exclusively called from `synchronizeOwnedIdentityWithKeycloakServer` when we need to update the local owned details using information returned by the keycloak server
    private func updatePublishedIdentityDetailsOfOwnedIdentityUsingKeycloakInformations(ownedCryptoId: ObvCryptoId, ignoreSynchronizationInterval: Bool, currentFailedAttempts: Int, keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff) {
        assert(OperationQueue.current == self.internalQueue)
        let obvOwnedIdentity: ObvOwnedIdentity
        do {
            obvOwnedIdentity = try obvEngine.getOwnedIdentity(with: ownedCryptoId)
        } catch {
            os_log("🧥 Could not get the ObvOwnedIdentity from the engine: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
            retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: currentFailedAttempts)
            return
        }
        let coreDetailsOnServer: ObvIdentityCoreDetails
        do {
            coreDetailsOnServer = try keycloakUserDetailsAndStuff.getObvIdentityCoreDetails()
        } catch {
            os_log("🧥 Could not get owned core details returned by server: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
            retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: currentFailedAttempts)
            return
        }
        // We use the core details from the server, but keep the local photo URL
        let updatedIdentityDetails = ObvIdentityDetails(coreDetails: coreDetailsOnServer, photoURL: obvOwnedIdentity.currentIdentityDetails.photoURL)
        do {
            try obvEngine.updatePublishedIdentityDetailsOfOwnedIdentity(with: ownedCryptoId, with: updatedIdentityDetails)
        } catch {
            retrySynchronizeOwnedIdentityWithKeycloakServerOnError(error: error, ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: ignoreSynchronizationInterval, currentFailedAttempts: currentFailedAttempts)
            return
        }
        // The following call will re-register the owned identity and call synchronizeOwnedIdentityWithKeycloakServer
        assert(OperationQueue.current == internalQueue)
        currentlySyncingOwnedIdentities.remove(ownedCryptoId)
        registerKeycloakManagedOwnedIdentity(ownedCryptoId: ownedCryptoId, firstKeycloakBinding: false)

    }
    
    
    private func getInternalKeycloakState(for ownedCryptoId: ObvCryptoId, failedAttempts: Int = 0, completion: @escaping (Result<InternalKeycloakState, GetObvKeycloakStateError>) -> Void) {
        assert(OperationQueue.current == internalQueue)

        let obvKeycloakState: ObvKeycloakState
        let signedOwnedDetails: SignedUserDetails?
        do {
            let (_obvKeycloakState, _signedOwnedDetails) = try obvEngine.getOwnedIdentityKeycloakState(with: ownedCryptoId)
            guard let _obvKeycloakState = _obvKeycloakState else {
                os_log("🧥 Could not find keycloak state for owned identity. We cannot refresh the local keycloak state, so we delete the previous one", log: KeycloakManager.log, type: .fault)
                throw makeError(message: "🧥 Could not find keycloak state for owned identity. We cannot refresh the local keycloak state")
            }
            obvKeycloakState = _obvKeycloakState
            signedOwnedDetails = _signedOwnedDetails
        } catch {
            os_log("🧥 Could not recover keycloak state for owned identity: %{public}@. We delete any existing locally cached state", log: KeycloakManager.log, type: .fault, error.localizedDescription)
            guard failedAttempts < maxFailCount else {
                assertionFailure()
                completion(.failure(.unkownError(error)))
                return
            }
            internalQueue.schedule(failedAttempts: failedAttempts) { [weak self] in
                self?.getInternalKeycloakState(for: ownedCryptoId, failedAttempts: failedAttempts + 1, completion: completion)
                return
            }
            return
        }

        guard let rawAuthState = obvKeycloakState.rawAuthState, let authState = OIDAuthState.deserialize(from: rawAuthState) else {
            openKeycloakAuthenticationRequiredTokenExpired(obvKeycloakState: obvKeycloakState, ownedCryptoId: ownedCryptoId) { [weak self] result in
                switch result {
                case .failure(let error):
                    switch error {
                    case .userHasCancelled:
                        completion(.failure(.userHasCancelled))
                        return
                    case .keycloakManagerError(let error):
                        completion(.failure(.unkownError(error)))
                        return
                    }
                case .success:
                    self?.getInternalKeycloakState(for: ownedCryptoId, completion: completion)
                    return
                }
            }
            return
        }
        
        guard authState.isAuthorized else {
            openKeycloakAuthenticationRequiredTokenExpired(obvKeycloakState: obvKeycloakState, ownedCryptoId: ownedCryptoId) { [weak self] result in
                guard let _self = self else { return }
                assert(OperationQueue.current == _self.internalQueue)
                switch result {
                case .failure(let error):
                    switch error {
                    case .userHasCancelled:
                        completion(.failure(.userHasCancelled))
                        return
                    case .keycloakManagerError(let error):
                        completion(.failure(.unkownError(error)))
                        return
                    }
                case .success:
                    self?.getInternalKeycloakState(for: ownedCryptoId, completion: completion)
                    return
                }
            }
            return
        }

        authState.performAction { [weak self] (accessToken, idToken, error) in
            guard let accessToken = accessToken, error == nil else {
                self?.internalQueue.addOperation {
                    self?.openKeycloakAuthenticationRequiredTokenExpired(obvKeycloakState: obvKeycloakState, ownedCryptoId: ownedCryptoId) { [weak self] result in
                        switch result {
                        case .failure(let error):
                            switch error {
                            case .userHasCancelled:
                                completion(.failure(.userHasCancelled))
                                return
                            case .keycloakManagerError(let error):
                                completion(.failure(.unkownError(error)))
                                return
                            }
                        case .success:
                            self?.getInternalKeycloakState(for: ownedCryptoId, completion: completion)
                            return
                        }
                    }
                }
                return
            }
            let internalKeycloakState = InternalKeycloakState(
                keycloakServer: obvKeycloakState.keycloakServer,
                clientId: obvKeycloakState.clientId,
                clientSecret: obvKeycloakState.clientSecret,
                jwks: obvKeycloakState.jwks,
                authState: authState,
                signatureVerificationKey: obvKeycloakState.signatureVerificationKey,
                accessToken: accessToken,
                latestRevocationListTimestamp: obvKeycloakState.latestLocalRevocationListTimestamp,
                signedOwnedDetails: signedOwnedDetails)
            self?.internalQueue.addOperation {
                completion(.success(internalKeycloakState))
                return
            }
            return
        }

    }

    
    private func getJkws(url: URL, completionHandler: @escaping (Result<Data, Error>) -> Void) {
        os_log("🧥 Call to getJkws", log: KeycloakManager.log, type: .info)
        let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
            guard let data = data else {
                completionHandler(.failure(error ?? KeycloakManager.makeError(message: "No data received")))
                return
            }
            completionHandler(.success(data))
        }
        task.resume()
    }

    
    private func discoverKeycloakServerAndSaveJWKSet(for serverURL: URL, ownedCryptoId: ObvCryptoId, completionHandler: @escaping (Result<(ObvJWKSet, OIDServiceConfiguration), Error>) -> Void) {
        os_log("🧥 Call to discoverKeycloakServerAndSaveJWKSet", log: KeycloakManager.log, type: .info)
        discoverKeycloakServer(for: serverURL) { [weak self] result in
            guard let _self = self else { return }
            switch result {
            case .failure:
                completionHandler(result)
            case .success((let jwks, _)):
                // Save the jwks in DB
                do {
                    try _self.obvEngine.saveKeycloakJwks(with: ownedCryptoId, jwks: jwks)
                } catch {
                    completionHandler(.failure(KeycloakManager.makeError(message: "Cannot save JWKSet")))
                    return
                }
                completionHandler(result)
            }
        }
    }

    private func uploadOwnedIdentity(serverURL: URL, authState: OIDAuthState, ownedIdentity: ObvCryptoId, completionHandler: @escaping (Result<Void, UploadOwnedIdentityError>) -> Void) {
        os_log("🧥 Call to uploadOwnedIdentity", log: KeycloakManager.log, type: .info)
        assert(OperationQueue.current == internalQueue)
        authState.performAction { [weak self] (accessToken, idToken, error) in
            guard error == nil else {
                completionHandler(.failure(.authenticationRequired))
                return
            }
            guard let accessToken = accessToken else {
                completionHandler(.failure(.authenticationRequired))
                return
            }
            let uploadOwnedIdentityJSON = UploadOwnedIdentityJSON(identity: ownedIdentity.getIdentity())
            let encoder = JSONEncoder()
            let dataToSend: Data
            do {
                dataToSend = try encoder.encode(uploadOwnedIdentityJSON)
            } catch(let error) {
                completionHandler(.failure(.unkownError(error)))
                return
            }

            self?.keycloakApiRequest(serverURL: serverURL, path: KeycloakManager.putKeyPath, accessToken: accessToken, dataToSend: dataToSend) { [weak self] (result: Result<ApiResultForPutKeyPath, KeycloakApiRequestError>) in
                guard let _self = self else { return }
                assert(OperationQueue.current == _self.internalQueue)
                switch result {
                case .failure(let error):
                    switch error {
                    case .internalError, .permissionDenied, .invalidRequest, .badResponse, .decodingFailed:
                        completionHandler(.failure(.serverError))
                        return
                    case .identityAlreadyUploaded:
                        completionHandler(.failure(.identityAlreadyUploaded))
                        return
                    case .ownedIdentityWasRevoked:
                        completionHandler(.failure(.ownedIdentityWasRevoked))
                        return
                    }
                case .success:
                    completionHandler(.success(()))
                    return
                }
            }

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


    private func keycloakApiRequest<T: KeycloakManagerApiResult>(serverURL: URL, path: String, accessToken: String?, dataToSend: Data?, completionHandler: @escaping (Result<T, KeycloakApiRequestError>) -> Void) {

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

        let task = urlSession.uploadTask(with: urlRequest, from: dataToSend ?? Data()) { [weak self] (data, response, error) in
            guard error == nil else {
                os_log("🧥 Call to keycloakApiRequest for path %{public}@ failed: %{public}@", log: KeycloakManager.log, type: .error, path, error!.localizedDescription)
                self?.internalQueue.addOperation { completionHandler(.failure(.invalidRequest)) }
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                os_log("🧥 Call to keycloakApiRequest for path %{public}@ failed (status code is not 200)", log: KeycloakManager.log, type: .error, path)
                self?.internalQueue.addOperation { completionHandler(.failure(.invalidRequest)) }
                return
            }
            guard let data = data else {
                os_log("🧥 Call to keycloakApiRequest for path %{public}@ failed: the keycloak server returned no data", log: KeycloakManager.log, type: .error, path)
                self?.internalQueue.addOperation { completionHandler(.failure(.invalidRequest)) }
                return
            }
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let error = json[OIDOAuthErrorFieldError] as? Int {
                if let ktError = KeycloakApiRequestError(rawValue: error) {
                    os_log("🧥 Call to keycloakApiRequest for path %{public}@ failed: ktError is %{public}@", log: KeycloakManager.log, type: .error, path, ktError.localizedDescription)
                    self?.internalQueue.addOperation { completionHandler(.failure(ktError)) }
                } else {
                    os_log("🧥 Call to keycloakApiRequest for path %{public}@ failed: decoding failed (1)", log: KeycloakManager.log, type: .error, path)
                    self?.internalQueue.addOperation { completionHandler(.failure(.decodingFailed)) }
                }
                return
            }
            let decodedData: T
            do {
                decodedData = try T.decode(data)
            } catch {
                os_log("🧥 Call to keycloakApiRequest for path %{public}@ failed: decoding failed (2)", log: KeycloakManager.log, type: .error, path)
                self?.internalQueue.addOperation { completionHandler(.failure(.decodingFailed)) }
                return
            }
            os_log("🧥 Call to keycloakApiRequest for path %{public}@ succeeded", log: KeycloakManager.log, type: .info, path)
            self?.internalQueue.addOperation { completionHandler(.success(decodedData)) }
            return
        }
        task.resume()
    }
}


// MARK: - OIDAuthStateChangeDelegate

extension KeycloakManager: OIDAuthStateChangeDelegate {

    func didChange(_ state: OIDAuthState) {
        guard let ownedCryptoId = ownedCryptoIdForOIDAuthState[state] else {
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
        case keycloakManagerError(_: Error)
        case userHasCancelled
    }

    /// This method is shared by the two methods called when the user needs to authenticate. This happens when the token expires and when the user id changes.
    private func selfTestAndOpenKeycloakAuthenticationRequired(serverURL: URL, clientId: String, clientSecret: String?, ownedCryptoId: ObvCryptoId, title: String, message: String, completionHandler: @escaping (Result<Void, KeycloakDialogError>) -> Void) {
        os_log("🧥 Call to selfTestAndOpenKeycloakAuthenticationRequired", log: KeycloakManager.log, type: .info)
        assert(OperationQueue.current == internalQueue)
        
        // Before authenticating, we test whether we have been revoked by the keycloak server
        
        do {
            if let selfRevocationTestNonceFromEngine = try obvEngine.getOwnedIdentityKeycloakSelfRevocationTestNonce(ownedCryptoId: ownedCryptoId) {
                selfRevocationTest(serverURL: serverURL, selfRevocationTestNonce: selfRevocationTestNonceFromEngine) { [weak self] result in
                    switch result {
                    case .failure(let error):
                        completionHandler(.failure(.keycloakManagerError(error)))
                    case .success(let isRevoked):
                        if isRevoked {
                            // The server returned `true`, the identity is no longer managed
                            // We unbind it at the engine level and display an alert to the user
                            do {
                                self?.setLastSynchronizationDate(forOwnedIdentity: ownedCryptoId, to: nil)
                                try self?.obvEngine.unbindOwnedIdentityFromKeycloakServer(ownedCryptoId: ownedCryptoId) { result in
                                    switch result {
                                    case .failure(let error):
                                        self?.internalQueue.addOperation {
                                            assertionFailure()
                                            completionHandler(.failure(.keycloakManagerError(error)))
                                            return
                                        }
                                        return
                                    case .success:
                                        self?.internalQueue.addOperation {
                                            self?.openAppDialogKeycloakIdentityRevoked()
                                            return
                                        }
                                    }
                                    return
                                }
                            } catch {
                                os_log("Could not unbind revoked owned identity: %{public}@", log: KeycloakManager.log, type: .fault, error.localizedDescription)
                                assertionFailure()
                                // Continue anyway
                            }
                            return
                        } else {
                            self?.openKeycloakAuthenticationRequired(serverURL: serverURL, clientId: clientId, clientSecret: clientSecret, ownedCryptoId: ownedCryptoId, title: title, message: message, completionHandler: completionHandler)
                            return
                        }
                    }
                }
                return
            }
        } catch {
            completionHandler(.failure(.keycloakManagerError(error)))
            return
        }

        // If we reach this point, we have no selfRevocationTestNonceFromEngine, we can immediately prompt for authentication
        
        openKeycloakAuthenticationRequired(serverURL: serverURL, clientId: clientId, clientSecret: clientSecret, ownedCryptoId: ownedCryptoId, title: title, message: message, completionHandler: completionHandler)
        
    }
    
    
    /// Shall only be called from `selfTestAndOpenKeycloakAuthenticationRequired`
    private func openAppDialogKeycloakIdentityRevoked() {
        os_log("🧥 Call to openAppDialogKeycloakIdentityRevoked", log: KeycloakManager.log, type: .info)
        DispatchQueue.main.async { [weak self] in
            let menu = UIAlertController(
                title: Strings.KeycloakIdentityWasRevokedAlert.title,
                message: Strings.KeycloakIdentityWasRevokedAlert.message,
                preferredStyle: .alert)
            let okAction = UIAlertAction(title: CommonString.Word.Ok, style: .default)
            menu.addAction(okAction)

            guard let viewControllerForPresentation = self?.viewControllerForPresentation else {
                assertionFailure()
                return
            }

            viewControllerForPresentation.present(menu, animated: true)
        }
    }
    
    
    /// Shall only be called from selfTestAndOpenKeycloakAuthenticationRequired
    private func openKeycloakAuthenticationRequired(serverURL: URL, clientId: String, clientSecret: String?, ownedCryptoId: ObvCryptoId, title: String, message: String, completionHandler: @escaping (Result<Void, KeycloakDialogError>) -> Void) {

        os_log("🧥 Call to openKeycloakAuthenticationRequired", log: KeycloakManager.log, type: .info)
        assert(!Thread.isMainThread, "Not a big deal if this fails, but this is not expected")
        
        DispatchQueue.main.async { [weak self] in
            let menu = UIAlertController(title: title, message: message, preferredStyle: UIDevice.current.actionSheetIfPhoneAndAlertOtherwise)
            
            let authenticateAction = UIAlertAction(title: CommonString.Word.Authenticate, style: .default) { _ in
                self?.discoverKeycloakServerAndSaveJWKSet(for: serverURL, ownedCryptoId: ownedCryptoId) { result in
                    switch result {
                    case .failure(let error):
                        completionHandler(.failure(.keycloakManagerError(error)))
                    case .success((let jwks, let configuration)):
                        self?.authenticate(configuration: configuration, clientId: clientId, clientSecret: clientSecret, ownedCryptoId: ownedCryptoId) { result in
                            switch result {
                            case .failure(let error):
                                self?.internalQueue.addOperation {
                                    completionHandler(.failure(.keycloakManagerError(error)))
                                    return
                                }
                                return
                            case .success(let authState):
                                self?.internalQueue.addOperation {
                                    self?.reAuthenticationSuccessful(ownedCryptoId: ownedCryptoId, jwks: jwks, authState: authState)
                                    completionHandler(.success(()))
                                    return
                                }
                                return
                            }
                        }
                    }
                }
            }
            let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: .cancel) { _ in
                self?.internalQueue.addOperation {
                    completionHandler(.failure(.userHasCancelled))
                    return
                }
                return
            }

            menu.addAction(authenticateAction)
            menu.addAction(cancelAction)

            guard let viewControllerForPresentation = self?.viewControllerForPresentation else {
                assertionFailure()
                return
            }
            
            viewControllerForPresentation.present(menu, animated: true, completion: nil)
        }
        
        
    }
    
    
    private func openAppDialogKeycloakSignatureKeyChanged(completionHandler: @escaping (Bool) -> Void) {
        os_log("🧥 Call to openAppDialogKeycloakSignatureKeyChanged", log: KeycloakManager.log, type: .info)
        DispatchQueue.main.async { [weak self] in
            let menu = UIAlertController(title: Strings.KeycloakSignatureKeyChangedAlert.title, message: Strings.KeycloakSignatureKeyChangedAlert.message, preferredStyle: UIDevice.current.actionSheetIfPhoneAndAlertOtherwise)
            let updateAction = UIAlertAction(title: Strings.KeycloakSignatureKeyChangedAlert.positiveButtonTitle, style: .destructive) { _ in
                self?.internalQueue.addOperation { completionHandler(true) }
            }
            let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: .cancel) { _ in
                self?.internalQueue.addOperation { completionHandler(false) }
            }
            menu.addAction(updateAction)
            menu.addAction(cancelAction)
            guard let viewControllerForPresentation = self?.viewControllerForPresentation else {
                assertionFailure()
                return
            }
            viewControllerForPresentation.present(menu, animated: true)
        }
    }

    
    private func openKeycloakAuthenticationRequiredTokenExpired(internalKeycloakState iks: InternalKeycloakState, ownedCryptoId: ObvCryptoId, completionHandler: @escaping (Result<Void, KeycloakDialogError>) -> Void) {
        os_log("🧥 Call to openKeycloakAuthenticationRequiredTokenExpired", log: KeycloakManager.log, type: .info)
        assert(OperationQueue.current == internalQueue)
        selfTestAndOpenKeycloakAuthenticationRequired(serverURL: iks.keycloakServer, clientId: iks.clientId, clientSecret: iks.clientSecret, ownedCryptoId: ownedCryptoId, title: Strings.AuthenticationRequiredTokenExpired, message: Strings.AuthenticationRequiredTokenExpiredMessage, completionHandler: completionHandler)
    }

    
    /// Only called from `getInternalKeycloakState`
    private func openKeycloakAuthenticationRequiredTokenExpired(obvKeycloakState oks: ObvKeycloakState, ownedCryptoId: ObvCryptoId, completionHandler: @escaping (Result<Void, KeycloakDialogError>) -> Void) {
        os_log("🧥 Call to openKeycloakAuthenticationRequiredTokenExpired", log: KeycloakManager.log, type: .info)
        assert(OperationQueue.current == internalQueue)
        selfTestAndOpenKeycloakAuthenticationRequired(serverURL: oks.keycloakServer, clientId: oks.clientId, clientSecret: oks.clientSecret, ownedCryptoId: ownedCryptoId, title: Strings.AuthenticationRequiredTokenExpired, message: Strings.AuthenticationRequiredTokenExpiredMessage, completionHandler: completionHandler)
    }

    
    private func openKeycloakAuthenticationRequiredUserIdChanged(internalKeycloakState iks: InternalKeycloakState, ownedCryptoId: ObvCryptoId, completionHandler: @escaping (Result<Void, KeycloakDialogError>) -> Void) {
        os_log("🧥 Call to openKeycloakAuthenticationRequiredUserIdChanged", log: KeycloakManager.log, type: .info)
        assert(OperationQueue.current == internalQueue)
        selfTestAndOpenKeycloakAuthenticationRequired(serverURL: iks.keycloakServer, clientId: iks.clientId, clientSecret: iks.clientSecret, ownedCryptoId: ownedCryptoId, title: Strings.AuthenticationRequiredUserIdChanged, message: Strings.AuthenticationRequiredUserIdChangedMessage, completionHandler: completionHandler)
    }
    
    
    /// Shall only be called from selfTestAndOpenKeycloakAuthenticationRequired
    private func selfRevocationTest(serverURL: URL, selfRevocationTestNonce: String, completionHandler: @escaping (Result<Bool, Error>) -> Void) {
        os_log("🧥 Call to selfRevocationTest", log: KeycloakManager.log, type: .info)
        assert(OperationQueue.current == internalQueue)

        let selfRevocationTestJSON = SelfRevocationTestJSON(selfRevocationTestNonce: selfRevocationTestNonce)
        let encoder = JSONEncoder()
        let dataToSend: Data
        do {
            dataToSend = try encoder.encode(selfRevocationTestJSON)
        } catch {
            completionHandler(.failure(error))
            return
        }
        
        keycloakApiRequest(serverURL: serverURL, path: KeycloakManager.revocationTestPath, accessToken: nil, dataToSend: dataToSend) { [weak self] (result: Result<KeycloakManager.ApiResultForRevocationTestPath, KeycloakApiRequestError>) in
            guard let _self = self else { return }
            assert(OperationQueue.current == _self.internalQueue)
            switch result {
            case .failure(let error):
                completionHandler(.failure(error))
                return
            case .success(let apiResultForRevocationTestPath):
                completionHandler(.success(apiResultForRevocationTestPath.isRevoked))
            }
        }
    }

    
    private func openKeycloakRevocation(serverURL: URL, authState: OIDAuthState, ownedCryptoId: ObvCryptoId, completionHandler: @escaping (Result<Void, KeycloakDialogError>) -> Void) {
        os_log("🧥 Call to openKeycloakRevocation", log: KeycloakManager.log, type: .info)
        DispatchQueue.main.async { [weak self] in
            let menu = UIAlertController(title: Strings.KeycloakRevocation, message: Strings.KeycloakRevocationMessage, preferredStyle: UIDevice.current.actionSheetIfPhoneAndAlertOtherwise)

            let revokeAction = UIAlertAction(title: Strings.KeycloakRevocationButton, style: .default) { _ in
                guard let _self = self else { return }
                _self.internalQueue.addOperation {
                    _self.uploadOwnedIdentity(serverURL: serverURL, authState: authState, ownedIdentity: ownedCryptoId) { result in
                        switch result {
                        case .success:
                            completionHandler(.success(()))
                        case .failure(let error):
                            completionHandler(.failure(.keycloakManagerError(error)))
                        }
                    }
                }
            }
            let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: .cancel) { [weak self] _ in
                self?.internalQueue.addOperation {
                    completionHandler(.failure(.userHasCancelled))
                }
            }

            menu.addAction(revokeAction)
            menu.addAction(cancelAction)

            guard let viewControllerForPresentation = self?.viewControllerForPresentation else {
                assertionFailure()
                return
            }

            viewControllerForPresentation.present(menu, animated: true, completion: nil)
        }
    }
    
    
    func openKeycloakRevocationForbidden() {
        os_log("🧥 Call to openKeycloakRevocationForbidden", log: KeycloakManager.log, type: .info)
        assert(OperationQueue.current == internalQueue)
        DispatchQueue.main.async { [weak self] in
            let alert = UIAlertController(title: Strings.KeycloakRevocationForbidden.title, message: Strings.KeycloakRevocationForbidden.message, preferredStyle: .alert)
            alert.addAction(UIAlertAction.init(title: CommonString.Word.Ok, style: .cancel))
            guard let viewControllerForPresentation = self?.viewControllerForPresentation else {
                assertionFailure()
                return
            }
            viewControllerForPresentation.present(alert, animated: true)
        }
    }

    
    func openAddContact(userDetail: UserDetails, ownedCryptoId: ObvCryptoId, completionHandler: @escaping (Result<Void, KeycloakDialogError>) -> Void) {
        os_log("🧥 Call to openAddContact", log: KeycloakManager.log, type: .info)
        assert(OperationQueue.current == internalQueue)

        DispatchQueue.main.async { [weak self] in
            
            guard let identity = userDetail.identity else { return }
            let menu = UIAlertController(title: Strings.AddContactTitle, message: Strings.AddContactMessage(userDetail.firstNameAndLastName), preferredStyle: UIDevice.current.actionSheetIfPhoneAndAlertOtherwise)
            
            let addContactAction = UIAlertAction(title: Strings.AddContactButton, style: .default) { _ in
                self?.addContact(ownedCryptoId: ownedCryptoId, userId: userDetail.id, userIdentity: identity) { result in
                    switch result {
                    case .success:
                        completionHandler(.success(()))
                    case .failure(let error):
                        completionHandler(.failure(.keycloakManagerError(error)))
                    }
                }
            }
            let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: .cancel) { _ in
                completionHandler(.failure(.userHasCancelled))
            }
            
            menu.addAction(addContactAction)
            menu.addAction(cancelAction)
            
            guard let viewControllerForPresentation = self?.viewControllerForPresentation else {
                assertionFailure()
                return
            }
            viewControllerForPresentation.present(menu, animated: true, completion: nil)
            
        }
    }


    /// This method is called each time the user re-authenticates succesfully. It saves the fresh jwks and auth state both in cache and within the engine.
    /// It also forces a new sychronization with the keycloak server.
    private func reAuthenticationSuccessful(ownedCryptoId: ObvCryptoId, jwks: ObvJWKSet, authState: OIDAuthState) {
        os_log("🧥 Call to reAuthenticationSuccessful", log: KeycloakManager.log, type: .info)
        assert(OperationQueue.current == internalQueue)

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
        
        synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: true)
        
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

fileprivate extension OperationQueue {
    
    func schedule(failedAttempts: Int, block: @escaping () -> Void) {
        assert(underlyingQueue != nil)
        (underlyingQueue ?? DispatchQueue.main).asyncAfter(deadline: .now() + .milliseconds(500 << failedAttempts)) { [weak self] in
            self?.addOperation(block)
        }
    }
    
    func schedule(deadline: DispatchTime, block: @escaping () -> Void) {
        assert(underlyingQueue != nil)
        (underlyingQueue ?? DispatchQueue.main).asyncAfter(deadline: deadline) { [weak self] in
            self?.addOperation(block)
        }
    }

}
