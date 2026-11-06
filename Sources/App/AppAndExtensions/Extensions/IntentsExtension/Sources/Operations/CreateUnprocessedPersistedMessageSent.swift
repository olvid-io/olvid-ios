/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvCrypto
import ObvUICoreData
import ObvAppTypes

final class CreateUnprocessedPersistedMessageSent: ContextualOperationWithSpecificReasonForCancel<CreateUnprocessedPersistedMessageSentOperationReasonForCancel>, @unchecked Sendable, UnprocessedPersistedMessageSentProvider {
    
    private let body: String?
    private let fyleJoinsProvider: (any FyleJoinsProvider)?
    private let discussionIdentifier: ObvDiscussionIdentifier

    private(set) var messageSentPermanentID: MessageSentPermanentID?

    init(body: String?, fyleJoinsProvider: (any FyleJoinsProvider)? = nil, discussionIdentifier: ObvDiscussionIdentifier) {
        self.body = body
        self.fyleJoinsProvider = fyleJoinsProvider
        self.discussionIdentifier = discussionIdentifier
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {

        let body = body ?? ""
        let fyleJoins = fyleJoinsProvider?.fyleJoins ?? []

        do {
            guard let discussion = try PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: discussionIdentifier, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindDiscussion)
            }

            let persistedMessageSent = try PersistedMessageSent.createPersistedMessageSentFromIntentExtension(
                body: body,
                fyleJoins: fyleJoins,
                discussion: discussion)
            
            do {
                try obvContext.context.obtainPermanentIDs(for: [persistedMessageSent])
            } catch {
                return cancel(withReason: .couldNotObtainPermanentIDForPersistedMessageSent)
            }
            
            self.messageSentPermanentID = try? persistedMessageSent.objectPermanentID
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }

}

enum CreateUnprocessedPersistedMessageSentOperationReasonForCancel: LocalizedErrorWithLogType {

    case couldNotFindDiscussion
    case coreDataError(error: Error)
    case couldNotObtainPermanentIDForPersistedMessageSent

    var logType: OSLogType { .fault }

    var errorDescription: String? {
        switch self {
        case .couldNotFindDiscussion: return "Cannot find discussion"
        case .coreDataError(error: let error): return "Core Data error: \(error.localizedDescription)"
        case .couldNotObtainPermanentIDForPersistedMessageSent: return "Could not obtain persisted permanent ID for PersistedMessageSent"
        }
    }

}
