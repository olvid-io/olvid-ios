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
import os.log
import CoreData
import OlvidUtils
import ObvCrypto
import ObvUICoreData


final class CreateUnprocessedPersistedMessageSentFromBodyOperation: ContextualOperationWithSpecificReasonForCancel<CreateUnprocessedPersistedMessageSentFromBodyOperationReasonForCancel>, UnprocessedPersistedMessageSentProvider {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: CreateUnprocessedReplyToPersistedMessageSentFromBodyOperation.self))

    let textBody: String
    let discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>

    private(set) var messageSentPermanentID: MessageSentPermanentID?

    init(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, textBody: String) {
        self.textBody = textBody
        self.discussionPermanentID = discussionPermanentID
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            guard let discussion = try PersistedDiscussion.getManagedObject(withPermanentID: discussionPermanentID, within: obvContext.context) else {
                assertionFailure()
                return cancel(withReason: .couldNotFindDiscussionInDatabase)
            }
            
            let persistedMessageSent = try PersistedMessageSent.createPersistedMessageSentWhenReplyingFromTheNotificationExtensionNotification(
                body: textBody,
                discussion: discussion,
                effectiveReplyTo: nil)
            
            do {
                try obvContext.context.obtainPermanentIDs(for: [persistedMessageSent])
            } catch {
                return cancel(withReason: .couldNotObtainPermanentIDForPersistedMessageSent)
            }
            
            self.messageSentPermanentID = persistedMessageSent.objectPermanentID
            
        } catch(let error) {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }

}

enum CreateUnprocessedPersistedMessageSentFromBodyOperationReasonForCancel: LocalizedErrorWithLogType {

    case contextIsNil
    case coreDataError(error: Error)
    case couldNotFindDiscussionInDatabase
    case couldNotObtainPermanentIDForPersistedMessageSent

    var logType: OSLogType {
        switch self {
        case .contextIsNil:
            return .fault
        case .coreDataError:
            return .fault
        case .couldNotFindDiscussionInDatabase:
            return .error
        case .couldNotObtainPermanentIDForPersistedMessageSent:
            return .error
        }
    }

    var errorDescription: String? {
        switch self {
        case .contextIsNil: return "Context is nil"
        case .couldNotFindDiscussionInDatabase: return "Could not obtain persisted discussion identity in database"
        case .coreDataError(error: let error): return "Core Data error: \(error.localizedDescription)"
        case .couldNotObtainPermanentIDForPersistedMessageSent: return "Could not obtain persisted permanent ID for PersistedMessageSent"
        }
    }

}
