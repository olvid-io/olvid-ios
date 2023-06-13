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
import ObvTypes
import ObvCrypto


final class CreateOrUpdateIfRequiredServerPushNotificationOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let pushNotification: ObvPushNotificationType
    
    private(set) var thereIsANewServerPushNotificationToRegister = false
    
    init(pushNotification: ObvPushNotificationType) {
        self.pushNotification = pushNotification
        super.init()
    }
    
    override func main() {

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {
            do {
             
                let kickOtherDeviceToKeep: Bool
                
                if let serverPushNotification = try ServerPushNotification.getServerPushNotificationOfType(pushNotification.byteId,
                                                                                                                       ownedCryptoId: pushNotification.ownedCryptoId,
                                                                                                                       within: obvContext.context) {
                    let existingPushNotification = try serverPushNotification.pushNotification
                    guard existingPushNotification != pushNotification else {
                        // Nothing left to do, an identical ServerPushNotification entry already exists in database
                        return
                    }
                    kickOtherDeviceToKeep = existingPushNotification.kickOtherDevices
                    try serverPushNotification.delete()
                    
                } else {
                    
                    kickOtherDeviceToKeep = false
                
                }
                
                // If we reach this point, we must create a new ServerPushNotification
                
                let serverPushNotification = try ServerPushNotification.createOrThrowIfOneAlreadyExists(pushNotificationType: pushNotification, within: obvContext.context)
                
                if kickOtherDeviceToKeep {
                    serverPushNotification.setKickOtherDevices(to: true)
                }
                
                assert((try? serverPushNotification.serverRegistrationStatus.byteId) == .toRegister)
                thereIsANewServerPushNotificationToRegister = true
                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
        }
        
    }
    
}
