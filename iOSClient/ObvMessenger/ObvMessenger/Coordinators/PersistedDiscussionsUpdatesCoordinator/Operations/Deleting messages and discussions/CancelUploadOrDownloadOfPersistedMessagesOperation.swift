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
import os.log
import CoreData
import ObvEngine
import OlvidUtils
import ObvUICoreData


final class CancelUploadOrDownloadOfPersistedMessagesOperation: ContextualOperationWithSpecificReasonForCancel<CancelUploadOrDownloadOfPersistedMessageOperationReasonForCancel> {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: CancelUploadOrDownloadOfPersistedMessagesOperation.self))

    private let input: Input
    private let obvEngine: ObvEngine
    
    enum Input {
        case messages(persistedMessageObjectIDs: [NSManagedObjectID])
        case discussion(persistedDiscussionObjectID: NSManagedObjectID)
    }

    init(persistedMessageObjectIDs: [NSManagedObjectID], obvEngine: ObvEngine) {
        self.input = .messages(persistedMessageObjectIDs: persistedMessageObjectIDs)
        self.obvEngine = obvEngine
        super.init()
    }
    
    init(persistedDiscussionObjectID: NSManagedObjectID, obvEngine: ObvEngine) {
        self.input = .discussion(persistedDiscussionObjectID: persistedDiscussionObjectID)
        self.obvEngine = obvEngine
        super.init()
    }

    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {
           
            do {
                
                let persistedMessageObjectIDs: [NSManagedObjectID]
                switch input {
                case .messages(persistedMessageObjectIDs: let _persistedMessageObjectIDs):
                    persistedMessageObjectIDs = _persistedMessageObjectIDs
                case .discussion(persistedDiscussionObjectID: let persistedDiscussionObjectID):
                    let allProcessingMessageSent = try PersistedMessageSent.getAllProcessingWithinDiscussion(persistedDiscussionObjectID: persistedDiscussionObjectID, within: obvContext.context)
                    persistedMessageObjectIDs = allProcessingMessageSent.map({ $0.objectID })
                }
                
                for persistedMessageObjectID in persistedMessageObjectIDs {
                    
                    guard let messageToDelete = try PersistedMessage.get(with: persistedMessageObjectID, within: obvContext.context) else {
                        continue
                    }
                    guard !(messageToDelete is PersistedMessageSystem) else {
                        os_log("We do not need to cancel the upload/download of a PersistedMessageSystem", log: log, type: .info)
                        continue
                    }
                    
                    guard let ownedIdentity = messageToDelete.discussion.ownedIdentity else {
                        return cancel(withReason: .persistedObvOwnedIdentityIsNil)
                    }
                    
                    if let sendMessageToDelete = messageToDelete as? PersistedMessageSent {
                        
                        let messadeIdentifiersFromEngine = Set(sendMessageToDelete.unsortedRecipientsInfos.compactMap { $0.messageIdentifierFromEngine })
                        
                        for messageIdentifierFromEngine in messadeIdentifiersFromEngine {
                            do {
                                try obvEngine.cancelPostOfMessage(withIdentifier: messageIdentifierFromEngine, ownedCryptoId: ownedIdentity.cryptoId)
                            } catch {
                                assertionFailure(error.localizedDescription)
                                continue
                            }
                        }
                        
                    } else if let receivedMessageToDelete = messageToDelete as? PersistedMessageReceived {
                        
                        // If the message is a received message, we ask the engine to cancel any download of this message
                        
                        do {
                            try obvEngine.cancelDownloadOfMessage(withIdentifier: receivedMessageToDelete.messageIdentifierFromEngine, ownedCryptoId: ownedIdentity.cryptoId)
                        } catch {
                            assertionFailure(error.localizedDescription)
                            continue
                        }
                        
                    } else {
                        
                        return cancel(withReason: .unexpectedMessageType)
                        
                    }
                    
                }
                
            } catch {
                assertionFailure(error.localizedDescription)
                return cancel(withReason: .coreDataError(error: error))
            }
                
        } // End obvContext.performAndWait
        
    }
    
}


enum CancelUploadOrDownloadOfPersistedMessageOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case persistedObvOwnedIdentityIsNil
    case unexpectedMessageType
    case coreDataError(error: Error)
    case contextIsNil
    
    var logType: OSLogType {
        switch self {
        case .persistedObvOwnedIdentityIsNil,
             .unexpectedMessageType,
             .coreDataError,
             .contextIsNil:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .persistedObvOwnedIdentityIsNil:
            return "The persisted owned identity cannot be determined given the message to delete"
        case .unexpectedMessageType:
            return "Unexpected message type"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .contextIsNil:
            return "Context is nil"
        }
    }
}
