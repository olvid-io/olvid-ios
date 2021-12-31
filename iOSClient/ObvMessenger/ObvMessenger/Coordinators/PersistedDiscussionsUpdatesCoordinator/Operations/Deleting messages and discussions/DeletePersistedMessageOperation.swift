/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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


final class DeletePersistedMessageOperation: ContextualOperationWithSpecificReasonForCancel<DeletePersistedMessageOperationReasonForCancel> {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    private let persistedMessageObjectID: NSManagedObjectID
    
    init(persistedMessageObjectID: NSManagedObjectID) {
        self.persistedMessageObjectID = persistedMessageObjectID
        super.init()
    }
 
    
    override func main() {
                
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {

            let infos: (discussionUriRepresentation: TypeSafeURL<PersistedDiscussion>, messageUriRepresentation: TypeSafeURL<PersistedMessage>)
            
            do {
                guard let messageToDelete = try PersistedMessage.get(with: persistedMessageObjectID, within: obvContext.context) else { return }
                infos = (messageToDelete.discussion.typedObjectID.uriRepresentation(), messageToDelete.typedObjectID.uriRepresentation())
                try messageToDelete.delete()
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            do {
                try obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else { return }
                    ObvMessengerInternalNotification.persistedMessagesWereDeleted(discussionUriRepresentation: infos.discussionUriRepresentation, messageUriRepresentations: Set([infos.messageUriRepresentation]))
                        .postOnDispatchQueue()
                }
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
                        
        }
        
    }
    
}


enum DeletePersistedMessageOperationReasonForCancel: LocalizedErrorWithLogType {

    case coreDataError(error: Error)
    case contextIsNil
    
    var logType: OSLogType {
        switch self {
        case .coreDataError, .contextIsNil:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        }
    }
    
}
