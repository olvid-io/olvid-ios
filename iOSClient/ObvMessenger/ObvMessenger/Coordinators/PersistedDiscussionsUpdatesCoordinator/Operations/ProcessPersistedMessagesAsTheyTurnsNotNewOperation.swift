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
import CoreData
import os.log
import OlvidUtils
import ObvUICoreData
import ObvTypes

/// When a discussion displays a new message, we consider it to be "not new" anymore. In the case of a `PersistedMessageReceived` instance, we mark the message as `unread` if it it marked as `readOnce`, and we mark it as `read` otherwise.
final class ProcessPersistedMessagesAsTheyTurnsNotNewOperation: ContextualOperationWithSpecificReasonForCancel<ProcessPersistedMessagesAsTheyTurnsNotNewOperationReasonForCancel>, OperationProvidingDiscussionReadJSON {
    
    private let _ownedCryptoId: ObvCryptoId
    private let discussionId: DiscussionIdentifier
    private let messageIds: [MessageIdentifier]
    
    init(ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageIds: [MessageIdentifier]) {
        self._ownedCryptoId = ownedCryptoId
        self.discussionId = discussionId
        self.messageIds = messageIds
        super.init()
    }
    
    var ownedCryptoId: ObvCryptoId? { _ownedCryptoId }
    private(set) var discussionReadJSONToSend: DiscussionReadJSON?

    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {

            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: _ownedCryptoId, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindOwnedIdentity)
            }
            
            let dateWhenMessageTurnedNotNew = Date()

            let lastReadMessageServerTimestamp = try ownedIdentity.markAllMessagesAsNotNew(discussionId: discussionId, messageIds: messageIds, dateWhenMessageTurnedNotNew: dateWhenMessageTurnedNotNew)

            do {
                let isDiscussionActive = try ownedIdentity.isDiscussionActive(discussionId: discussionId)
                if let lastReadMessageServerTimestamp, isDiscussionActive {
                    discussionReadJSONToSend = try ownedIdentity.getDiscussionReadJSON(discussionId: discussionId, lastReadMessageServerTimestamp: lastReadMessageServerTimestamp)
                }
            } catch {
                assertionFailure(error.localizedDescription) // Continue anyway
            }

            if obvContext.context.hasChanges {
                do {
                    let discussionObjectID = try ownedIdentity.getDiscussionObjectID(discussionId: discussionId)
                    try obvContext.addContextDidSaveCompletionHandler({ error in
                        guard error == nil else { return }
                        // The following allows to make sure we properly refresh the discussion in the view context
                        // In particular, this will trigger a proper computation of the new message badges
                        viewContext.perform {
                            guard let discussion = viewContext.registeredObject(for: discussionObjectID) else { return }
                            ObvStack.shared.viewContext.refresh(discussion, mergeChanges: false)
                        }
                    })
                } catch {
                    assertionFailure(error.localizedDescription) // Continue anyway
                }
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }

    }
    
}


enum ProcessPersistedMessagesAsTheyTurnsNotNewOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case couldNotFindOwnedIdentity
    case coreDataError(error: Error)
    case couldNotMarkMessageReceivedAsNotNew
    
    var logType: OSLogType {
        switch self {
        case .coreDataError, .couldNotMarkMessageReceivedAsNotNew, .couldNotFindOwnedIdentity:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .couldNotFindOwnedIdentity:
            return "Could not find owned identity"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotMarkMessageReceivedAsNotNew:
            return "Could not mark message received as not new"
        }
    }
    
}
