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
import OlvidUtils
import ObvCrypto
import ObvServerInterface
import ObvMetaManager
import os.log
import ObvTypes


final class RegisterPushNotificationToRegisterOperation: ContextualOperationWithSpecificReasonForCancel<RegisterUnregisteredPushNotificationOperationReasonForCancel> {
    
    private let ownedCryptoId: ObvCryptoIdentity
    private let pushNotificationType: ObvPushNotificationType.ByteId
    private let remoteNotificationByteIdentifierForServer: Data
    private let identityDelegate: ObvIdentityDelegate
    private let session: URLSession
    
    init(ownedCryptoId: ObvCryptoIdentity, pushNotificationType: ObvPushNotificationType.ByteId, remoteNotificationByteIdentifierForServer: Data, session: URLSession, identityDelegate: ObvIdentityDelegate) {
        self.ownedCryptoId = ownedCryptoId
        self.pushNotificationType = pushNotificationType
        self.remoteNotificationByteIdentifierForServer = remoteNotificationByteIdentifierForServer
        self.session = session
        self.identityDelegate = identityDelegate
        super.init()
    }
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {
            do {

                guard let serverPushNotification = try ServerPushNotification.getServerPushNotificationOfType(pushNotificationType, ownedCryptoId: ownedCryptoId, within: obvContext.context) else {
                    // Nothing to do
                    return
                }

                guard try serverPushNotification.serverRegistrationStatus.byteId == .toRegister else {
                    // Nothing to do
                    return
                }

                guard let serverSession = try ServerSession.get(within: obvContext, withIdentity: ownedCryptoId) else {
                    return cancel(withReason: .serverSessionRequired)
                }

                guard let token = serverSession.token else {
                    return cancel(withReason: .serverSessionRequired)
                }
                                                
                let pushNotification = try serverPushNotification.pushNotification
                
                switch pushNotification {
                    
                case .remote(let ownedCryptoId, let currentDeviceUID, let pushToken, let voipToken, let maskingUID, let parameters):
                    
                    let method = ObvServerRegisterRemotePushNotificationMethod(ownedIdentity: ownedCryptoId,
                                                                               token: token,
                                                                               deviceUid: currentDeviceUID,
                                                                               remoteNotificationByteIdentifierForServer: remoteNotificationByteIdentifierForServer,
                                                                               deviceTokensAndmaskingUID: (pushToken, voipToken, maskingUID),
                                                                               parameters: parameters,
                                                                               keycloakPushTopics: parameters.keycloakPushTopics,
                                                                               flowId: obvContext.flowId)
                    method.identityDelegate = identityDelegate
                    
                    let task: URLSessionDataTask
                    do {
                        task = try method.dataTask(within: self.session)
                    } catch let error {
                        return cancel(withReason: .failedToCreateURLSessionDataTask(error: error))
                    }
                    task.resume()
                    
                    try serverPushNotification.switchToServerRegistrationStatus(.registering(urlSessionTaskIdentifier: task.taskIdentifier))
                    
                case .registerDeviceUid(ownedCryptoId: let ownedCryptoId, currentDeviceUID: let currentDeviceUID, parameters: let parameters):
                    
                    let method = ObvServerRegisterRemotePushNotificationMethod(ownedIdentity: ownedCryptoId,
                                                                               token: token,
                                                                               deviceUid: currentDeviceUID,
                                                                               remoteNotificationByteIdentifierForServer: Data([0xff]),
                                                                               deviceTokensAndmaskingUID: nil,
                                                                               parameters: parameters,
                                                                               keycloakPushTopics: parameters.keycloakPushTopics,
                                                                               flowId: obvContext.flowId)
                    method.identityDelegate = identityDelegate

                    let task: URLSessionDataTask
                    do {
                        task = try method.dataTask(within: self.session)
                    } catch let error {
                        return cancel(withReason: .failedToCreateURLSessionDataTask(error: error))
                    }

                    task.resume()
                    
                    try serverPushNotification.switchToServerRegistrationStatus(.registering(urlSessionTaskIdentifier: task.taskIdentifier))

                }
                
                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
        }
        
    }
    
}


public enum RegisterUnregisteredPushNotificationOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case contextIsNil
    case failedToCreateURLSessionDataTask(error: Error)
    case serverSessionRequired

    public var logType: OSLogType {
        switch self {
        case .serverSessionRequired:
            return .error
        case .coreDataError, .contextIsNil, .failedToCreateURLSessionDataTask:
            return .fault
        }
    }

    public var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .failedToCreateURLSessionDataTask(error: let error):
            return "Failed to create URLSessionDataTask: \(error.localizedDescription)"
        case .serverSessionRequired:
            return "Server session required"
        }
    }

}
