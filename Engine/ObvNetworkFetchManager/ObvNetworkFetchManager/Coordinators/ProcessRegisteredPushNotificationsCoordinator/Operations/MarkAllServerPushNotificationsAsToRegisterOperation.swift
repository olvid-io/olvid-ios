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
import ObvTypes


final class MarkAllServerPushNotificationsAsToRegisterOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private(set) var serverPushNotificationsToRegister = [(ownedCryptoId: ObvCryptoIdentity, pushNotificationType: ObvPushNotificationType.ByteId)]()
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {
            do {
                
                let serverPushNotifications = try ServerPushNotification.getAllServerPushNotification(within: obvContext.context)
                
                try serverPushNotifications.forEach { serverPushNotification in
                    
                    try serverPushNotification.switchToServerRegistrationStatus(.toRegister)
                    
                    let pushNotification = try serverPushNotification.pushNotification
                    
                    serverPushNotificationsToRegister.append((ownedCryptoId: pushNotification.ownedCryptoId, pushNotificationType: pushNotification.byteId))
                    
                }
                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
        }
        
    }
    
}
