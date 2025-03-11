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
import CoreData
import OlvidUtils
import ObvTypes
import ObvCrypto
import ObvUserNotificationsDatabase


final class GetRequestIdentifierOfShownUserNotificationForReceivedMessageOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let ownedCryptoId: ObvTypes.ObvCryptoId
    private let messageIdFromServer: ObvCrypto.UID
    
    init(ownedCryptoId: ObvTypes.ObvCryptoId, messageIdFromServer: ObvCrypto.UID) {
        self.ownedCryptoId = ownedCryptoId
        self.messageIdFromServer = messageIdFromServer
        super.init()
    }
    
    private(set) var requestIdentifier: String?
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            requestIdentifier = try PersistedUserNotification.getRequestIdentifierForShownReceivedMessage(
                ownedCryptoId: ownedCryptoId,
                messageIdFromServer: messageIdFromServer,
                within: obvContext.context)
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
