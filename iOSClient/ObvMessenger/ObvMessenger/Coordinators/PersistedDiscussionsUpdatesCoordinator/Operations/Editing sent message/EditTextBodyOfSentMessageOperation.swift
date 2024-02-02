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
import ObvEngine
import OlvidUtils
import ObvUICoreData
import ObvTypes


final class EditTextBodyOfSentMessageOperation: ContextualOperationWithSpecificReasonForCancel<EditTextBodyOfSentMessageOperation.ReasonForCancel> {

    private let ownedCryptoId: ObvCryptoId
    private let persistedSentMessageObjectID: TypeSafeManagedObjectID<PersistedMessageSent>
    private let newTextBody: String?
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: EditTextBodyOfSentMessageOperation.self))

    init(ownedCryptoId: ObvCryptoId, persistedSentMessageObjectID: TypeSafeManagedObjectID<PersistedMessageSent>, newTextBody: String?) {
        self.ownedCryptoId = ownedCryptoId
        self.persistedSentMessageObjectID = persistedSentMessageObjectID
        if let newTextBody {
            self.newTextBody = newTextBody.isEmpty ? nil : newTextBody
        } else {
            self.newTextBody = nil
        }
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindOwnedIdentity)
            }
            
            let updatedMessage = try ownedIdentity.processLocalUpdateMessageRequestFromThisOwnedIdentity(persistedSentMessageObjectID: persistedSentMessageObjectID, newTextBody: newTextBody)
            
            // If the message appears as a reply-to in some other messages, we must refresh those messages in the view context
            // Similarly, if a draft is replying to this message, we must refresh the draft in the view context
            
            if let updatedMessage {
                do {
                    let repliesObjectIDs = updatedMessage.repliesObjectIDs.map({ $0.objectID })
                    let draftObjectIDs = try PersistedDraft.getObjectIDsOfAllDraftsReplyingTo(message: updatedMessage).map({ $0.objectID })
                    let objectIDsToRefresh = [updatedMessage.objectID] + repliesObjectIDs + draftObjectIDs
                    if !objectIDsToRefresh.isEmpty {
                        try? obvContext.addContextDidSaveCompletionHandler { error in
                            guard error == nil else { return }
                            DispatchQueue.main.async {
                                let objectsToRefresh = ObvStack.shared.viewContext.registeredObjects
                                    .filter({ objectIDsToRefresh.contains($0.objectID) })
                                objectsToRefresh.forEach { objectID in
                                    ObvStack.shared.viewContext.refresh(objectID, mergeChanges: true)
                                }
                            }
                        }
                    }
                } catch {
                    assertionFailure()
                    // In production, continue anyway
                }
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
 

    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case contextIsNil
        case couldNotFindOwnedIdentity

        var logType: OSLogType {
            switch self {
            case .coreDataError,
                 .couldNotFindOwnedIdentity,
                 .contextIsNil:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .contextIsNil:
                return "Context is nil"
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindOwnedIdentity:
                return "Could not find owned identity"
            }
        }

    }

}
