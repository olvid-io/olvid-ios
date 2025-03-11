/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import os.log
import ObvServerInterface
import ObvTypes
import ObvOperation
import ObvCrypto
import ObvMetaManager
import OlvidUtils


actor ServerPushNotificationsCoordinator: ServerPushNotificationsDelegate {
    
    private static let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    private static let logCategory = "ServerPushNotificationsCoordinator"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)

    weak var delegateManager: ObvNetworkFetchDelegateManager?
    private let remoteNotificationByteIdentifierForServer: Data
    private let prng: PRNGService

    private var failedAttemptsCounterManager = FailedAttemptsCounterManager()
    private var retryManager = FetchRetryManager()
    
    init(remoteNotificationByteIdentifierForServer: Data, prng: PRNGService, logPrefix: String) {
        self.remoteNotificationByteIdentifierForServer = remoteNotificationByteIdentifierForServer
        self.prng = prng
        let logSubsystem = "\(logPrefix).\(Self.defaultLogSubsystem)"
        Self.log = OSLog(subsystem: logSubsystem, category: Self.logCategory)
    }
        
    private var cache = [ObvPushNotificationType: RegistrationTask]()
    private enum RegistrationTask {
        case inProgress(Task<ObvServerRegisterRemotePushNotificationMethod.PossibleReturnStatus, Error>)
    }
    
    // MARK: - ServerPushNotificationsDelegate
    
    func registerPushNotification(_ pushNotification: ObvPushNotificationType, flowId: FlowIdentifier) async throws {
        
        let requestUUID = UUID()
        
        os_log("🫸[%{public}@] New pushNotification to register: %{public}@", log: Self.log, type: .info, requestUUID.debugDescription, pushNotification.debugDescription)
        
        try await registerPushNotification(pushNotification, flowId: flowId, requestUUID: requestUUID)
        
        os_log("🫸[%{public}@] Push notification processed", log: Self.log, type: .info, requestUUID.debugDescription)

    }
    
    
    func setDelegateManager(_ delegateManager: ObvNetworkFetchDelegateManager) {
        self.delegateManager = delegateManager
    }
    
    
    // MARK: - Helper methods
    
    /// If this method throws, it throws one of the following errors:
    /// - ObvError.anotherDeviceIsAlreadyRegistered
    /// - ObvError.deviceToReplaceIsNotRegistered
    private func registerPushNotification(_ pushNotification: ObvPushNotificationType, flowId: FlowIdentifier, requestUUID: UUID) async throws {
        
        let returnStatus: ObvServerRegisterRemotePushNotificationMethod.PossibleReturnStatus
        do {
            returnStatus = try await registerPushNotificationOnServer(pushNotification, flowId: flowId, requestUUID: requestUUID)
        } catch {
            let delay = failedAttemptsCounterManager.incrementAndGetDelay(.registerPushNotification(ownedIdentity: pushNotification.ownedCryptoId))
            os_log("Will retry the call to registerPushNotification in %f seconds", log: Self.log, type: .error, Double(delay) / 1000.0)
            await retryManager.waitForDelay(milliseconds: delay)
            return try await registerPushNotification(pushNotification, flowId: flowId, requestUUID: requestUUID)
        }
        
        os_log("🫸[%{public}@] Status returned by the server: %{public}@", log: Self.log, type: .info, requestUUID.debugDescription, returnStatus.debugDescription)
        
        switch returnStatus {
        case .ok:
            failedAttemptsCounterManager.reset(counter: .registerPushNotification(ownedIdentity: pushNotification.ownedCryptoId))
            return
        case .invalidSession, .generalError:
            // No need to inform the delegate that our session is invalid, this has been done already in registerPushNotificationOnServer(_:flowId:requestUUID:)
            let delay = failedAttemptsCounterManager.incrementAndGetDelay(.registerPushNotification(ownedIdentity: pushNotification.ownedCryptoId))
            os_log("Will retry the call to registerPushNotification in %f seconds", log: Self.log, type: .error, Double(delay) / 1000.0)
            await retryManager.waitForDelay(milliseconds: delay)
            try await registerPushNotification(pushNotification, flowId: flowId, requestUUID: requestUUID)
        case .anotherDeviceIsAlreadyRegistered:
            failedAttemptsCounterManager.reset(counter: .registerPushNotification(ownedIdentity: pushNotification.ownedCryptoId))
            throw ObvError.anotherDeviceIsAlreadyRegistered
        case .deviceToReplaceIsNotRegistered:
            failedAttemptsCounterManager.reset(counter: .registerPushNotification(ownedIdentity: pushNotification.ownedCryptoId))
            throw ObvError.deviceToReplaceIsNotRegistered
        }
        
    }

    
    private func registerPushNotificationOnServer(_ pushNotification: ObvPushNotificationType, flowId: FlowIdentifier, requestUUID: UUID) async throws -> ObvServerRegisterRemotePushNotificationMethod.PossibleReturnStatus {

        guard let delegateManager = delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        let sessionToken = try await delegateManager.serverSessionDelegate.getValidServerSessionToken(for: pushNotification.ownedCryptoId, currentInvalidToken: nil, flowId: flowId).serverSessionToken

        if let cached = cache[pushNotification] {
            switch cached {
            case .inProgress(let task):
                os_log("🫸[%{public}@] Cache hit: in progress", log: Self.log, type: .info, requestUUID.debugDescription)
                return try await task.value
            }
        }
        
        os_log("🫸[%{public}@] Not in cache", log: Self.log, type: .info, requestUUID.debugDescription)
                
        let task = Task {
            
            guard let method = ObvServerRegisterRemotePushNotificationMethod(
                pushNotification: pushNotification,
                sessionToken: sessionToken,
                remoteNotificationByteIdentifierForServer: remoteNotificationByteIdentifierForServer,
                flowId: flowId,
                prng: prng) else {
                assertionFailure()
                throw ObvError.failedToCreateServerMethod
            }
            
            os_log("🫸[%{public}@] Performing server query using session token %{public}@", log: Self.log, type: .info, requestUUID.debugDescription, sessionToken.hexString())

            let (data, response) = try await URLSession.shared.data(for: method.getURLRequest())
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw ObvError.invalidServerResponse
            }
            
            guard let returnStatus = ObvServerRegisterRemotePushNotificationMethod.parseObvServerResponse(responseData: data, using: Self.log) else {
                assertionFailure()
                throw ObvError.couldNotParseReturnStatusFromServer
            }
            
            return returnStatus
            
        }
        
        cache[pushNotification] = .inProgress(task)
        
        os_log("🫸[%{public}@] In progress", log: Self.log, type: .info, requestUUID.debugDescription)

        do {
            let returnStatus = try await task.value
            cache.removeValue(forKey: pushNotification)
            switch returnStatus {
            case .invalidSession:
                os_log("🫸[%{public}@] We inform our delegate that the following session token is invalid: %{public}@", log: Self.log, type: .info, requestUUID.debugDescription, sessionToken.hexString())
                _ = try await delegateManager.networkFetchFlowDelegate.getValidServerSessionToken(for: pushNotification.ownedCryptoId, currentInvalidToken: sessionToken, flowId: flowId)
                os_log("🫸[%{public}@] We informed our delegate that the following session token is invalid: %{public}@ and we try to register again", log: Self.log, type: .info, requestUUID.debugDescription, sessionToken.hexString())
                return try await registerPushNotificationOnServer(pushNotification, flowId: flowId, requestUUID: requestUUID)
            default:
                break
            }
            return returnStatus
        } catch {
            cache.removeValue(forKey: pushNotification)
            throw error
        }
                
    }
    
    enum ObvError: LocalizedError {
        case invalidServerResponse
        case theDelegateManagerIsNotSet
        case couldNotParseReturnStatusFromServer
        case anotherDeviceIsAlreadyRegistered
        case deviceToReplaceIsNotRegistered
        case failedToCreateServerMethod
        
        var errorDescription: String? {
            switch self {
            case .invalidServerResponse:
                return "Invalid server response"
            case .theDelegateManagerIsNotSet:
                return "The delegate manager is not set"
            case .couldNotParseReturnStatusFromServer:
                return "Could not parse return status from server"
            case .anotherDeviceIsAlreadyRegistered:
                return "Another device is already registered"
            case .deviceToReplaceIsNotRegistered:
                return "Device to replace is not registered"
            case .failedToCreateServerMethod:
                return "Failed to create server method"
            }
        }
    }
    
}
