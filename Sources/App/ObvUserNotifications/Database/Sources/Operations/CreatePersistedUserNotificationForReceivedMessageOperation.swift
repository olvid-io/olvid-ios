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
import OSLog
import CoreData
import OlvidUtils
import ObvTypes
import ObvAppTypes
import ObvUserNotificationsTypes


public final class CreatePersistedUserNotificationForReceivedMessageOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let requestIdentifier: String
    private let obvMessage: ObvMessage
    private let receivedMessageAppIdentifier: ObvMessageAppIdentifier
    private let userNotificationCategory: ObvUserNotificationCategoryIdentifier
    private let creator: PersistedUserNotification.Creator

    public init(requestIdentifier: String, obvMessage: ObvMessage, receivedMessageAppIdentifier: ObvMessageAppIdentifier, userNotificationCategory: ObvUserNotificationCategoryIdentifier, creator: PersistedUserNotification.Creator) {
        self.requestIdentifier = requestIdentifier
        self.obvMessage = obvMessage
        self.receivedMessageAppIdentifier = receivedMessageAppIdentifier
        self.userNotificationCategory = userNotificationCategory
        self.creator = creator
        super.init()
    }
    
    public enum Result {
        case created
        case existed
    }
    
    public private(set) var result: Result?
    
    public override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            if try PersistedUserNotification.exists(requestIdentifier: requestIdentifier, obvMessage: obvMessage, within: obvContext.context) {
                result = .existed
            } else {
                _ = try PersistedUserNotification.createForReceivedMessage(
                    creator: creator,
                    requestIdentifier: requestIdentifier,
                    obvMessage: obvMessage,
                    receivedMessageAppIdentifier: receivedMessageAppIdentifier,
                    userNotificationCategory: userNotificationCategory,
                    within: obvContext.context)
                result = .created
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
