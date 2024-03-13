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
import ObvEngine
import ObvTypes
import OlvidUtils
import ObvUICoreData
import CoreData


/// Given its `input`, this operation determines a list `messagesToCancelFromEngine` of messages to cancel at the engine level. For a received message, this really means "delete it from the inbox". This operation does not actually request the deletion but leverages the ``CancelUploadOrDownloadOfPersistedMessagesOperation`` to do so.
final class DetermineEngineIdentifiersOfMessagesToCancelOperation: ContextualOperationWithSpecificReasonForCancel<DetermineEngineIdentifiersOfMessagesToCancelOperation.ReasonForCancel>, OperationProvidingListOfMessagesToCancelFromEngine {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: CancelUploadOrDownloadOfPersistedMessagesOperation.self))

    private let input: Input
    private let obvEngine: ObvEngine
    
    enum Input {
        case messages(persistedMessageObjectIDs: [NSManagedObjectID])
        case discussion(persistedDiscussionObjectID: NSManagedObjectID)
        case remoteDiscussionDeletionRequestFromContact(deleteDiscussionJSON: DeleteDiscussionJSON, obvMessage: ObvMessage)
        case remoteDiscussionDeletionRequestFromOtherOwnedDevice(deleteDiscussionJSON: DeleteDiscussionJSON, obvOwnedMessage: ObvOwnedMessage)
    }

    init(input: Input, obvEngine: ObvEngine) {
        self.input = input
        self.obvEngine = obvEngine
        super.init()
    }
    

    private(set) var messagesToCancelFromEngine = [CancelUploadOrDownloadOfPersistedMessagesOperation.MessageToCancelFromEngine]()
    
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            let persistedMessageObjectIDs: [NSManagedObjectID]
            
            switch input {
            case .messages(persistedMessageObjectIDs: let _persistedMessageObjectIDs):
                persistedMessageObjectIDs = _persistedMessageObjectIDs
            case .discussion(persistedDiscussionObjectID: let persistedDiscussionObjectID):
                let allProcessingMessageSent = try PersistedMessageSent.getAllProcessingWithinDiscussion(persistedDiscussionObjectID: persistedDiscussionObjectID, within: obvContext.context)
                persistedMessageObjectIDs = allProcessingMessageSent.map({ $0.objectID })
            case .remoteDiscussionDeletionRequestFromContact(deleteDiscussionJSON: let deleteDiscussionJSON, obvMessage: let obvMessage):
                guard let contact = try PersistedObvContactIdentity.get(persisted: obvMessage.fromContactIdentity, whereOneToOneStatusIs: .any, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindContact)
                }
                persistedMessageObjectIDs = try contact.getObjectIDsOfPersistedMessageSentStillProcessing(deleteDiscussionJSON: deleteDiscussionJSON).map({ $0.objectID })
            case .remoteDiscussionDeletionRequestFromOtherOwnedDevice(deleteDiscussionJSON: let deleteDiscussionJSON, obvOwnedMessage: let obvOwnedMessage):
                guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: obvOwnedMessage.ownedCryptoId, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindOwnedIdentity)
                }
                persistedMessageObjectIDs = try ownedIdentity.getObjectIDsOfPersistedMessageSentStillProcessing(deleteDiscussionJSON: deleteDiscussionJSON).map({ $0.objectID })
            }
            
            for persistedMessageObjectID in persistedMessageObjectIDs {
                
                guard let messageToDelete = try PersistedMessage.get(with: persistedMessageObjectID, within: obvContext.context) else {
                    continue
                }
                guard !(messageToDelete is PersistedMessageSystem) else {
                    os_log("We do not need to cancel the upload/download of a PersistedMessageSystem", log: log, type: .info)
                    continue
                }
                
                guard let discussion = messageToDelete.discussion else {
                    return cancel(withReason: .discussionIsNil)
                }
                
                guard let ownedIdentity = discussion.ownedIdentity else {
                    return cancel(withReason: .persistedObvOwnedIdentityIsNil)
                }
                
                if let sendMessageToDelete = messageToDelete as? PersistedMessageSent {
                    
                    let messadeIdentifiersFromEngine = Set(sendMessageToDelete.unsortedRecipientsInfos.compactMap { $0.messageIdentifierFromEngine })
                    
                    for messageIdentifierFromEngine in messadeIdentifiersFromEngine {
                        messagesToCancelFromEngine.append(.sent(ownedCryptoId: ownedIdentity.cryptoId, messageIdentifierFromEngine: messageIdentifierFromEngine))
                    }
                    
                } else if let receivedMessageToDelete = messageToDelete as? PersistedMessageReceived {
                    
                    // If the message is a received message, we ask the engine to cancel any download of this message
                    
                    messagesToCancelFromEngine.append(.received(ownedCryptoId: ownedIdentity.cryptoId, messageIdentifierFromEngine: receivedMessageToDelete.messageIdentifierFromEngine))
                    
                } else {
                    
                    return cancel(withReason: .unexpectedMessageType)
                    
                }
                
            }
            
        } catch {
            if let error = error as? ObvUICoreDataError {
                switch error {
                case .couldNotFindGroupV2InDatabase:
                    // No assert in this case, this can happen. See the comment in the description of MessagesKeptForLaterManager.
                    return
                default:
                    assertionFailure()
                    return cancel(withReason: .coreDataError(error: error))
                }
            } else {
                assertionFailure()
                return cancel(withReason: .coreDataError(error: error))
            }
        }
        
    }
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case discussionIsNil
        case persistedObvOwnedIdentityIsNil
        case unexpectedMessageType
        case coreDataError(error: Error)
        case contextIsNil
        case couldNotFindContact
        case couldNotFindOwnedIdentity

        var logType: OSLogType {
            switch self {
            case .persistedObvOwnedIdentityIsNil,
                 .discussionIsNil,
                 .unexpectedMessageType,
                 .coreDataError,
                 .contextIsNil:
                return .fault
            case .couldNotFindContact,
                    .couldNotFindOwnedIdentity:
                return .error
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
            case .couldNotFindContact:
                return "Could not find contact"
            case .couldNotFindOwnedIdentity:
                return "Could not find owned identity"
            case .discussionIsNil:
                return "Discussion is nil"
            }
        }
    }

    
}



protocol OperationProvidingListOfMessagesToCancelFromEngine: Operation {
    var messagesToCancelFromEngine: [CancelUploadOrDownloadOfPersistedMessagesOperation.MessageToCancelFromEngine] { get }
}



final class CancelUploadOrDownloadOfPersistedMessagesOperation: AsyncOperationWithSpecificReasonForCancel<CancelUploadOrDownloadOfPersistedMessagesOperation.ReasonForCancel> {
    
    enum MessageToCancelFromEngine {
        case sent(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data)
        case received(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data)
    }

    private let op: OperationProvidingListOfMessagesToCancelFromEngine
    private let obvEngine: ObvEngine
    
    init(op: OperationProvidingListOfMessagesToCancelFromEngine, obvEngine: ObvEngine) {
        self.op = op
        self.obvEngine = obvEngine
        super.init()
        self.addDependency(op)
    }
    
    override func main() async {
        
        guard op.isFinished && !op.isCancelled else {
            assertionFailure()
            return cancel(withReason: .operationProvidingListOfMessagesToCancelFromEngineIsNotFinishedOrIsCancelled)
        }
        
        for messageToCancelFromEngine in op.messagesToCancelFromEngine {
            
            switch messageToCancelFromEngine {
            case .sent(let ownedCryptoId, let messageIdentifierFromEngine):
                do {
                    try obvEngine.cancelPostOfMessage(withIdentifier: messageIdentifierFromEngine, ownedCryptoId: ownedCryptoId)
                } catch {
                    assertionFailure(error.localizedDescription)
                    continue
                }
            case .received(let ownedCryptoId, let messageIdentifierFromEngine):
                do {
                    try await obvEngine.cancelDownloadOfMessage(ownedCryptoId: ownedCryptoId, messageIdentifier: messageIdentifierFromEngine)
                } catch {
                    assertionFailure(error.localizedDescription)
                    continue
                }
            }
            
        }

        return finish()

    }
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case operationProvidingListOfMessagesToCancelFromEngineIsNotFinishedOrIsCancelled

        var logType: OSLogType {
            return .fault
        }
        
        var errorDescription: String? {
            switch self {
            case .operationProvidingListOfMessagesToCancelFromEngineIsNotFinishedOrIsCancelled:
                return "Operation providing list of messages to cancel from engine is not finished or is cancelled"
            }
        }
    }

}







//final class CancelUploadOrDownloadOfPersistedMessagesOperation: ContextualOperationWithSpecificReasonForCancel<CancelUploadOrDownloadOfPersistedMessageOperationReasonForCancel> {
//    
//    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: CancelUploadOrDownloadOfPersistedMessagesOperation.self))
//
//    private let input: Input
//    private let obvEngine: ObvEngine
//    
//    enum Input {
//        case messages(persistedMessageObjectIDs: [NSManagedObjectID])
//        case discussion(persistedDiscussionObjectID: NSManagedObjectID)
//        case remoteDiscussionDeletionRequestFromContact(deleteDiscussionJSON: DeleteDiscussionJSON, obvMessage: ObvMessage)
//        case remoteDiscussionDeletionRequestFromOtherOwnedDevice(deleteDiscussionJSON: DeleteDiscussionJSON, obvOwnedMessage: ObvOwnedMessage)
//    }
//
//    init(input: Input, obvEngine: ObvEngine) {
//        self.input = input
//        self.obvEngine = obvEngine
//        super.init()
//    }
//    
//    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
//        
//        do {
//            
//            let persistedMessageObjectIDs: [NSManagedObjectID]
//            
//            switch input {
//            case .messages(persistedMessageObjectIDs: let _persistedMessageObjectIDs):
//                persistedMessageObjectIDs = _persistedMessageObjectIDs
//            case .discussion(persistedDiscussionObjectID: let persistedDiscussionObjectID):
//                let allProcessingMessageSent = try PersistedMessageSent.getAllProcessingWithinDiscussion(persistedDiscussionObjectID: persistedDiscussionObjectID, within: obvContext.context)
//                persistedMessageObjectIDs = allProcessingMessageSent.map({ $0.objectID })
//            case .remoteDiscussionDeletionRequestFromContact(deleteDiscussionJSON: let deleteDiscussionJSON, obvMessage: let obvMessage):
//                guard let contact = try PersistedObvContactIdentity.get(persisted: obvMessage.fromContactIdentity, whereOneToOneStatusIs: .any, within: obvContext.context) else {
//                    return cancel(withReason: .couldNotFindContact)
//                }
//                persistedMessageObjectIDs = try contact.getObjectIDsOfPersistedMessageSentStillProcessing(deleteDiscussionJSON: deleteDiscussionJSON).map({ $0.objectID })
//            case .remoteDiscussionDeletionRequestFromOtherOwnedDevice(deleteDiscussionJSON: let deleteDiscussionJSON, obvOwnedMessage: let obvOwnedMessage):
//                guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: obvOwnedMessage.ownedCryptoId, within: obvContext.context) else {
//                    return cancel(withReason: .couldNotFindOwnedIdentity)
//                }
//                persistedMessageObjectIDs = try ownedIdentity.getObjectIDsOfPersistedMessageSentStillProcessing(deleteDiscussionJSON: deleteDiscussionJSON).map({ $0.objectID })
//            }
//            
//            for persistedMessageObjectID in persistedMessageObjectIDs {
//                
//                guard let messageToDelete = try PersistedMessage.get(with: persistedMessageObjectID, within: obvContext.context) else {
//                    continue
//                }
//                guard !(messageToDelete is PersistedMessageSystem) else {
//                    os_log("We do not need to cancel the upload/download of a PersistedMessageSystem", log: log, type: .info)
//                    continue
//                }
//                
//                guard let discussion = messageToDelete.discussion else {
//                    return cancel(withReason: .discussionIsNil)
//                }
//                
//                guard let ownedIdentity = discussion.ownedIdentity else {
//                    return cancel(withReason: .persistedObvOwnedIdentityIsNil)
//                }
//                
//                if let sendMessageToDelete = messageToDelete as? PersistedMessageSent {
//                    
//                    let messadeIdentifiersFromEngine = Set(sendMessageToDelete.unsortedRecipientsInfos.compactMap { $0.messageIdentifierFromEngine })
//                    
//                    for messageIdentifierFromEngine in messadeIdentifiersFromEngine {
//                        do {
//                            try obvEngine.cancelPostOfMessage(withIdentifier: messageIdentifierFromEngine, ownedCryptoId: ownedIdentity.cryptoId)
//                        } catch {
//                            assertionFailure(error.localizedDescription)
//                            continue
//                        }
//                    }
//                    
//                } else if let receivedMessageToDelete = messageToDelete as? PersistedMessageReceived {
//                    
//                    // If the message is a received message, we ask the engine to cancel any download of this message
//                    
//                    do {
//                        try obvEngine.cancelDownloadOfMessage(withIdentifier: receivedMessageToDelete.messageIdentifierFromEngine, ownedCryptoId: ownedIdentity.cryptoId)
//                    } catch {
//                        assertionFailure(error.localizedDescription)
//                        continue
//                    }
//                    
//                } else {
//                    
//                    return cancel(withReason: .unexpectedMessageType)
//                    
//                }
//                
//            }
//            
//        } catch {
//            if let error = error as? ObvUICoreDataError {
//                switch error {
//                case .couldNotFindGroupV2InDatabase:
//                    // No assert in this case, this can happen. See the comment in the description of MessagesKeptForLaterManager.
//                    return
//                default:
//                    assertionFailure()
//                    return cancel(withReason: .coreDataError(error: error))
//                }
//            } else {
//                assertionFailure()
//                return cancel(withReason: .coreDataError(error: error))
//            }
//        }
//        
//    }
//    
//}


//enum CancelUploadOrDownloadOfPersistedMessageOperationReasonForCancel: LocalizedErrorWithLogType {
//    
//    case discussionIsNil
//    case persistedObvOwnedIdentityIsNil
//    case unexpectedMessageType
//    case coreDataError(error: Error)
//    case contextIsNil
//    case couldNotFindContact
//    case couldNotFindOwnedIdentity
//
//    var logType: OSLogType {
//        switch self {
//        case .persistedObvOwnedIdentityIsNil,
//             .discussionIsNil,
//             .unexpectedMessageType,
//             .coreDataError,
//             .contextIsNil:
//            return .fault
//        case .couldNotFindContact,
//                .couldNotFindOwnedIdentity:
//            return .error
//        }
//    }
//    
//    var errorDescription: String? {
//        switch self {
//        case .persistedObvOwnedIdentityIsNil:
//            return "The persisted owned identity cannot be determined given the message to delete"
//        case .unexpectedMessageType:
//            return "Unexpected message type"
//        case .coreDataError(error: let error):
//            return "Core Data error: \(error.localizedDescription)"
//        case .contextIsNil:
//            return "Context is nil"
//        case .couldNotFindContact:
//            return "Could not find contact"
//        case .couldNotFindOwnedIdentity:
//            return "Could not find owned identity"
//        case .discussionIsNil:
//            return "Discussion is nil"
//        }
//    }
//}
