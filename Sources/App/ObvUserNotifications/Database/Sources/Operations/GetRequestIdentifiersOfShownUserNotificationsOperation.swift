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
import ObvAppTypes
import ObvCrypto


public final class GetRequestIdentifiersOfShownUserNotificationsOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let input: InputType
    
    public enum InputType {
        case discussionAndLastReadMessageServerTimestamp(discussionIdentifier: ObvDiscussionIdentifier, lastReadMessageServerTimestamp: Date?)
        case messageIdentifiers(messageAppIdentifiers: [ObvMessageAppIdentifier])
        case restrictToReactionNotifications(discussionIdentifier: ObvDiscussionIdentifier)
        case ownedCryptoId(ownedCryptoId: ObvCryptoId)
    }
    
    public init(_ input: InputType) {
        self.input = input
        super.init()
    }
    
    public private(set) var requestIdentifiers = [String]()
    
    public override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            switch input {
                
            case .discussionAndLastReadMessageServerTimestamp(discussionIdentifier: let discussionIdentifier, lastReadMessageServerTimestamp: let lastReadMessageServerTimestamp):

                requestIdentifiers = try PersistedUserNotification.getRequestIdentifiersForShownUserNotifications(
                    discussionIdentifier: discussionIdentifier,
                    lastReadMessageServerTimestamp: lastReadMessageServerTimestamp,
                    within: obvContext.context)
                
            case .messageIdentifiers(messageAppIdentifiers: let messageAppIdentifiers):
                
                requestIdentifiers = try messageAppIdentifiers.compactMap { messageAppIdentifier in
                    try PersistedUserNotification.getRequestIdentifierForShownUserNotification(
                        messageAppIdentifier: messageAppIdentifier,
                        within: obvContext.context)
                }
                
            case .restrictToReactionNotifications(discussionIdentifier: let discussionIdentifier):
                
                requestIdentifiers = try PersistedUserNotification.getRequestIdentifiersForShownReactionsOnSentMessages(
                    discussionIdentifier: discussionIdentifier,
                    within: obvContext.context)
                
            case .ownedCryptoId(ownedCryptoId: let ownedCryptoId):
                
                requestIdentifiers = try PersistedUserNotification.getRequestIdentifiersForShownUserNotifications(
                    ownedCryptoId: ownedCryptoId,
                    within: obvContext.context)

            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
