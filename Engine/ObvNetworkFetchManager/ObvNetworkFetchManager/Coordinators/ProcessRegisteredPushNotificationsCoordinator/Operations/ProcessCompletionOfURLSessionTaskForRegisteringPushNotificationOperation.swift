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
import ObvServerInterface
import os.log
import ObvCrypto
import ObvTypes


final class ProcessCompletionOfURLSessionTaskForRegisteringPushNotificationOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let urlSessionTaskIdentifier: Int
    private let responseData: Data
    private let log: OSLog
    
    enum ServerReturnStatus {
        case serverReturnedDataDiscardedAsItWasObsolete
        case ok(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier)
        case invalidSession(ownedCryptoId: ObvCryptoIdentity, pushNotificationType: ObvPushNotificationType.ByteId, flowId: FlowIdentifier)
        case anotherDeviceIsAlreadyRegistered(ownedCryptoId: ObvCryptoIdentity, pushNotificationType: ObvPushNotificationType.ByteId, flowId: FlowIdentifier)
        case generalError(ownedCryptoId: ObvCryptoIdentity, pushNotificationType: ObvPushNotificationType.ByteId, flowId: FlowIdentifier)
        case couldNotParseServerResponse(ownedCryptoId: ObvCryptoIdentity, pushNotificationType: ObvPushNotificationType.ByteId, flowId: FlowIdentifier)
    }
    
    private(set) var serverReturnStatus: ServerReturnStatus? = nil
    
    init(urlSessionTaskIdentifier: Int, responseData: Data, log: OSLog) {
        self.urlSessionTaskIdentifier = urlSessionTaskIdentifier
        self.responseData = responseData
        self.log = log
        super.init()
    }
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {
            do {

                guard let serverPushNotification = try ServerPushNotification.getRegisteringAndCorrespondingToURLSessionTaskIdentifier(urlSessionTaskIdentifier, within: obvContext.context) else {
                    // This happens if we had to relaunch a registration after launching a, now obsolete, request. In that case the ServerPushNotification entry which lead to the obsolete request may have been deleted.
                    // We simply discard the result of the obsolete URL request
                    serverReturnStatus = .serverReturnedDataDiscardedAsItWasObsolete
                    return
                }

                let pushNotification = try serverPushNotification.pushNotification

                guard let status = ObvServerRegisterRemotePushNotificationMethod.parseObvServerResponse(responseData: responseData, using: log) else {
                    try serverPushNotification.switchToServerRegistrationStatus(.toRegister)
                    serverReturnStatus = .couldNotParseServerResponse(ownedCryptoId: pushNotification.ownedCryptoId, pushNotificationType: pushNotification.byteId, flowId: obvContext.flowId)
                    return
                }

                switch status {

                case .ok:
                    os_log("The push notification registration was successfully received by the server for identity %{public}@. This device is registered 🥳.", log: log, type: .info, pushNotification.ownedCryptoId.debugDescription)
                    try serverPushNotification.switchToServerRegistrationStatus(.registered)
                    serverReturnStatus = .ok(ownedCryptoId: pushNotification.ownedCryptoId, flowId: obvContext.flowId)
                    return
                    
                case .invalidSession:
                    try serverPushNotification.switchToServerRegistrationStatus(.toRegister)
                    serverReturnStatus = .invalidSession(ownedCryptoId: pushNotification.ownedCryptoId, pushNotificationType: pushNotification.byteId, flowId: obvContext.flowId)
                    return // the serverRetrunStatus was set, we will deal with this case in the completion handler of the operation
                    
                case .anotherDeviceIsAlreadyRegistered:
                    try serverPushNotification.delete()
                    serverReturnStatus = .anotherDeviceIsAlreadyRegistered(ownedCryptoId: pushNotification.ownedCryptoId, pushNotificationType: pushNotification.byteId, flowId: obvContext.flowId)
                    return // the serverRetrunStatus was set, we will deal with this case in the completion handler of the operation

                case .generalError:
                    try serverPushNotification.switchToServerRegistrationStatus(.toRegister)
                    serverReturnStatus = .generalError(ownedCryptoId: pushNotification.ownedCryptoId, pushNotificationType: pushNotification.byteId, flowId: obvContext.flowId)
                    return // the serverRetrunStatus was set, we will deal with this case in the completion handler of the operation

                }
                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
        }
        
    }
    
}
