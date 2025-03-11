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
import os.log
import CoreData
import OlvidUtils
import ObvCrypto
import ObvUICoreData
import ObvAppCoreConstants
import ObvAppTypes


final class CreateUnprocessedPersistedMessageSentFromBodyOperation: ContextualOperationWithSpecificReasonForCancel<CreateUnprocessedPersistedMessageSentFromBodyOperation.ReasonForCancel>, @unchecked Sendable, UnprocessedPersistedMessageSentProvider {

    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: CreateUnprocessedReplyToPersistedMessageSentFromBodyOperation.self))

    let textBody: String
    let discussionIdentifier: ObvDiscussionIdentifier

    private(set) var messageSentPermanentID: MessageSentPermanentID?

    init(discussionIdentifier: ObvDiscussionIdentifier, textBody: String) {
        self.textBody = textBody
        self.discussionIdentifier = discussionIdentifier
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            let ownedCryptoId = discussionIdentifier.ownedCryptoId
            let discussionId = discussionIdentifier.toDiscussionIdentifier()
            guard let discussion = try PersistedDiscussion.getPersistedDiscussion(ownedCryptoId: ownedCryptoId, discussionId: discussionId, within: obvContext.context) else {
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
            
            self.messageSentPermanentID = try? persistedMessageSent.objectPermanentID
            
        } catch(let error) {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }

    
    enum ReasonForCancel: LocalizedErrorWithLogType {

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

}
