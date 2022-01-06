/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import os.log
import ObvEngine
import OlvidUtils

final class SendGlobalDeleteDiscussionJSONOperation: OperationWithSpecificReasonForCancel<SendGlobalDeleteDiscussionJSONOperationReasonForCancel> {

    private let persistedDiscussionObjectID: NSManagedObjectID
    private let obvEngine: ObvEngine
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    init(persistedDiscussionObjectID: NSManagedObjectID, obvEngine: ObvEngine) {
        self.persistedDiscussionObjectID = persistedDiscussionObjectID
        self.obvEngine = obvEngine
        super.init()
    }

    override func main() {

        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            
            // We create the PersistedItemJSON instance to send

            let discussion: PersistedDiscussion
            do {
                guard let _discussion = try PersistedDiscussion.get(objectID: persistedDiscussionObjectID, within: context) else {
                    return cancel(withReason: .couldNotFindDiscussion)
                }
                discussion = _discussion
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            let deleteDiscussionJSON: DeleteDiscussionJSON
            do {
                deleteDiscussionJSON = try DeleteDiscussionJSON(persistedDiscussionToDelete: discussion)
            } catch {
                return cancel(withReason: .couldNotConstructDeleteDiscussionJSON(error: error))
            }
            let itemJSON = PersistedItemJSON(deleteDiscussionJSON: deleteDiscussionJSON)

            // Find all the contacts to which this item should be sent.
            
            let contactCryptoIds: Set<ObvCryptoId>
            let ownCryptoId: ObvCryptoId
            do {
                (ownCryptoId, contactCryptoIds) = try discussion.getAllActiveParticipants()
            } catch {
                return cancel(withReason: .couldNotGetCryptoIdOfDiscussionParticipants(error: error))
            }

            // Create a payload of the PersistedItemJSON we just created and send it.
            // We do not keep track of the message identifiers from engine.
            
            let payload: Data
            do {
                payload = try itemJSON.encode()
            } catch {
                return cancel(withReason: .failedToEncodePersistedItemJSON)
            }
            
            do {
                _ = try obvEngine.post(messagePayload: payload,
                                       extendedPayload: nil,
                                       withUserContent: false,
                                       isVoipMessageForStartingCall: false,
                                       attachmentsToSend: [],
                                       toContactIdentitiesWithCryptoId: contactCryptoIds,
                                       ofOwnedIdentityWithCryptoId: ownCryptoId)
            } catch {
                return cancel(withReason: .couldNotPostMessageWithinEngine)
            }

        }
        
    }
    
}


enum SendGlobalDeleteDiscussionJSONOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case couldNotFindDiscussion
    case couldNotConstructDeleteDiscussionJSON(error: Error)
    case couldNotGetCryptoIdOfDiscussionParticipants(error: Error)
    case failedToEncodePersistedItemJSON
    case couldNotPostMessageWithinEngine
    
    var logType: OSLogType {
        switch self {
        case .coreDataError,
             .couldNotFindDiscussion,
             .couldNotGetCryptoIdOfDiscussionParticipants,
             .failedToEncodePersistedItemJSON,
             .couldNotPostMessageWithinEngine,
             .couldNotConstructDeleteDiscussionJSON:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindDiscussion:
            return "Could not find discussion"
        case .couldNotConstructDeleteDiscussionJSON(error: let error):
            return "Could not construct the DeleteDiscussionJSON instance: \(error.localizedDescription)"
        case .couldNotGetCryptoIdOfDiscussionParticipants(error: let error):
            return "Could not get the cryptoId of the discussion participants: \(error.localizedDescription)"
        case .failedToEncodePersistedItemJSON:
            return "We failed to encode the persisted item JSON"
        case .couldNotPostMessageWithinEngine:
            return "We failed to post the serialized DeleteMessagesJSON within the engine"
        }
    }

}
