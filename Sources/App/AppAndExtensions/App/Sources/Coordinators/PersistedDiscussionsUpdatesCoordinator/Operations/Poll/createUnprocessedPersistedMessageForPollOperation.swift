/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvUICoreData
import ObvAppTypes

final class CreateUnprocessedPersistedMessageForPollOperation: ContextualOperationWithSpecificReasonForCancel<CreateUnprocessedPersistedMessageForPollOperation.ReasonForCancel>, @unchecked Sendable {
    
    private let poll: ObvPoll
    private let discussionIdentifier: ObvDiscussionIdentifier
    
    init(discussionIdentifier: ObvDiscussionIdentifier, poll: ObvPoll) {
        self.poll = poll
        self.discussionIdentifier = discussionIdentifier
        super.init()
    }
    
    private(set) var unprocessedMessageToSend: MessageSentPermanentID?
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: discussionIdentifier.ownedCryptoId, within: obvContext.context) else {
                assertionFailure()
                return cancel(withReason: .couldNotFindOwnedIdentityInDatabase)
            }

            guard ownedIdentity.isActive else {
                assertionFailure()
                return cancel(withReason: .ownedIdentityIsInactive)
            }
            
            unprocessedMessageToSend = try ownedIdentity.createPersistedPollToSend(discussionIdentifier: discussionIdentifier, poll: poll)
            
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
    }
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        case coreDataError(error: Error)
        case couldNotFindOwnedIdentityInDatabase
        case ownedIdentityIsInactive
        
        var logType: OSLogType {
            switch self {
            case .coreDataError, .couldNotFindOwnedIdentityInDatabase, .ownedIdentityIsInactive:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error): return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindOwnedIdentityInDatabase: return "Could not obtain persisted owned identity in database"
            case .ownedIdentityIsInactive: return "Owned identity is inactive"
            }
        }
        
    }
}
