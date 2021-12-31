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
import os.log
import CoreData
import ObvEngine
import OlvidUtils


final class CancelUploadOrDownloadOfPersistedMessageOperation: OperationWithSpecificReasonForCancel<CancelUploadOrDownloadOfPersistedMessageOperationReasonForCancel> {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    private let persistedMessageObjectID: NSManagedObjectID
    private let obvEngine: ObvEngine
    
    init(persistedMessageObjectID: NSManagedObjectID, obvEngine: ObvEngine) {
        self.persistedMessageObjectID = persistedMessageObjectID
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main() {
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in

            let messageToDelete: PersistedMessage
            do {
                guard let _messageToDelete = try PersistedMessage.get(with: persistedMessageObjectID, within: context) else {
                    return cancel(withReason: .couldNotFindPersistedMessageInDatabase)
                }
                guard !(_messageToDelete is PersistedMessageSystem) else {
                    os_log("We do not need to cancel the upload/download of a PersistedMessageSystem", log: log, type: .info)
                    return
                }
                messageToDelete = _messageToDelete
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            guard let ownedIdentity = messageToDelete.discussion.ownedIdentity else {
                return cancel(withReason: .persistedObvOwnedIdentityIsNil)
            }

            if let sendMessageToDelete = messageToDelete as? PersistedMessageSent {
                
                let messadeIdentifiersFromEngine = Set(sendMessageToDelete.unsortedRecipientsInfos.compactMap { $0.messageIdentifierFromEngine })
                
                var oneCancelPostOfMessageFailed = false
                for messageIdentifierFromEngine in messadeIdentifiersFromEngine {
                    do {
                        try obvEngine.cancelPostOfMessage(withIdentifier: messageIdentifierFromEngine, ownedCryptoId: ownedIdentity.cryptoId)
                    } catch {
                        oneCancelPostOfMessageFailed = true
                    }
                }
                if oneCancelPostOfMessageFailed {
                    return cancel(withReason: .couldNotCancelPostOfMessageForAtLeastOneRecipient)
                }
                
            } else if let receivedMessageToDelete = messageToDelete as? PersistedMessageReceived {
                                
                // If the message is a received message, we ask the engine to cancel any download of this message
                
                do {
                    try obvEngine.cancelDownloadOfMessage(withIdentifier: receivedMessageToDelete.messageIdentifierFromEngine, ownedCryptoId: ownedIdentity.cryptoId)
                } catch {
                    return cancel(withReason: .couldNotCancelDownloadOfMessage)
                }
                
            } else {

                return cancel(withReason: .unexpectedMessageType)
                
            }


        }
        
    }
    
}


enum CancelUploadOrDownloadOfPersistedMessageOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case couldNotFindPersistedMessageInDatabase
    case persistedObvOwnedIdentityIsNil
    case couldNotCancelPostOfMessageForAtLeastOneRecipient
    case couldNotCancelDownloadOfMessage
    case unexpectedMessageType
    case coreDataError(error: Error)
    
    var logType: OSLogType {
        switch self {
        case .couldNotFindPersistedMessageInDatabase,
             .couldNotCancelPostOfMessageForAtLeastOneRecipient,
             .couldNotCancelDownloadOfMessage:
            return .error
        case .persistedObvOwnedIdentityIsNil,
             .unexpectedMessageType,
             .coreDataError:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .couldNotFindPersistedMessageInDatabase:
            return "Could not find persisted message in database"
        case .persistedObvOwnedIdentityIsNil:
            return "The persisted owned identity cannot be determined given the message to delete"
        case .couldNotCancelPostOfMessageForAtLeastOneRecipient:
            return "Could not cancel the post of a message for at least one of its recipients"
        case .couldNotCancelDownloadOfMessage:
            return "Could not cancel the download of a message"
        case .unexpectedMessageType:
            return "Unexpected message type"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        }
    }
}
