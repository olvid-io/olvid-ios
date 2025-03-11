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
import OSLog
import OlvidUtils
import ObvUICoreData
import ObvTypes
import ObvCrypto
import ObvAppTypes

/// Given a message, this operation determines the permanent identifier of its discussion.
final class FetchDiscussionPermanentIDCorrespondingToMessage: ContextualOperationWithSpecificReasonForCancel<FetchDiscussionPermanentIDCorrespondingToMessage.ReasonForCancel>, @unchecked Sendable {

    private let messageAppIdentifier: ObvAppTypes.ObvMessageAppIdentifier

    init(messageAppIdentifier: ObvAppTypes.ObvMessageAppIdentifier) {
        self.messageAppIdentifier = messageAppIdentifier
        super.init()
    }


    private(set) var discussionPermanentID: DiscussionPermanentID?


    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {

        do {
            
            guard let message = try PersistedMessage.getMessage(messageAppIdentifier: messageAppIdentifier, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindMessageInDatabase)
            }
            
            guard let discussion = message.discussion else {
                return cancel(withReason: .couldNotFindDiscussionInDatabase)
            }
            
            self.discussionPermanentID = discussion.discussionPermanentID
            
        } catch {
            return cancel(withReason: .error(error: error))
        }

    }


    public enum ReasonForCancel: LocalizedErrorWithLogType {

        case error(error: Error)
        case couldNotFindMessageInDatabase
        case couldNotFindDiscussionInDatabase

        public var logType: OSLogType {
            switch self {
            case .error:
                return .fault
            case .couldNotFindMessageInDatabase,
                    .couldNotFindDiscussionInDatabase:
                return .error
            }
        }

        public var errorDescription: String? {
            switch self {
            case .error(error: let error):
                return "error: \(error.localizedDescription)"
            case .couldNotFindMessageInDatabase:
                return "Could not find PersistedMessage in database"
            case .couldNotFindDiscussionInDatabase:
                return "Could not find Discussion in database"
            }
        }

    }

}
