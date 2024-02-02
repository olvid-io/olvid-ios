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
import ObvCrypto
import OlvidUtils
import ObvUICoreData
import ObvTypes


final class CreatePersistedMessageReceivedFromReceivedObvMessageOperation: ContextualOperationWithSpecificReasonForCancel<CreatePersistedMessageReceivedFromReceivedObvMessageOperation.ReasonForCancel>, OperationProvidingDiscussionPermanentID {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "CreatePersistedMessageReceivedFromReceivedObvMessageOperation")

    private let obvMessage: ObvMessage
    private let messageJSON: MessageJSON
    private let returnReceiptJSON: ReturnReceiptJSON?
    private let overridePreviousPersistedMessage: Bool
    private let obvEngine: ObvEngine

    init(obvMessage: ObvMessage, messageJSON: MessageJSON, overridePreviousPersistedMessage: Bool, returnReceiptJSON: ReturnReceiptJSON?, obvEngine: ObvEngine) {
        self.obvMessage = obvMessage
        self.messageJSON = messageJSON
        self.returnReceiptJSON = returnReceiptJSON
        self.overridePreviousPersistedMessage = overridePreviousPersistedMessage
        self.obvEngine = obvEngine
        super.init()
    }

    enum Result {
        case couldNotFindGroupV2InDatabase(groupIdentifier: GroupV2Identifier)
        case messageCreated(discussionPermanentID: DiscussionPermanentID)
    }
    
    private(set) var result: Result?
    
    
    var discussionPermanentID: ObvUICoreData.DiscussionPermanentID? {
        switch result {
        case .couldNotFindGroupV2InDatabase, nil:
            return nil
        case .messageCreated(discussionPermanentID: let discussionPermanentID):
            return discussionPermanentID
        }
    }

    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        os_log("Executing a CreatePersistedMessageReceivedFromReceivedObvMessageOperation for obvMessage %{public}@", log: log, type: .debug, obvMessage.messageIdentifierFromEngine.debugDescription)
        
        do {
            
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: obvMessage.fromContactIdentity.ownedCryptoId, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindOwnedIdentity)
            }
            
            // Create or update the PersistedMessageReceived from that contact
            
            let attachmentsFullyReceivedOrCancelledByServer:  [ObvAttachment]
            
            do {
                
                let (discussionPermanentID, _attachmentsFullyReceivedOrCancelledByServer) = try ownedIdentity.createOrOverridePersistedMessageReceived(
                    obvMessage: obvMessage,
                    messageJSON: messageJSON,
                    returnReceiptJSON: returnReceiptJSON,
                    overridePreviousPersistedMessage: overridePreviousPersistedMessage)
                self.result = .messageCreated(discussionPermanentID: discussionPermanentID)
                attachmentsFullyReceivedOrCancelledByServer = _attachmentsFullyReceivedOrCancelledByServer

            } catch {
                if let error = error as? ObvUICoreDataError {
                    switch error {
                    case .couldNotFindGroupV2InDatabase(groupIdentifier: let groupIdentifier):
                        result = .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
                        return
                    default:
                        return cancel(withReason: .persistedObvContactIdentityObvError(error: error))
                    }
                } else if let error = error as? PersistedMessageReceived.ObvError {
                    return cancel(withReason: .persistedMessageReceivedObvError(error: error))
                } else {
                    assertionFailure("We should probably add the missing if/let case")
                    return cancel(withReason: .coreDataError(error: error))
                }
            }

            // We ask the engine to delete all the attachments that were fully received
            
            if !attachmentsFullyReceivedOrCancelledByServer.isEmpty {
                let obvEngine = self.obvEngine
                let log = self.log
                do {
                    try obvContext.addContextDidSaveCompletionHandler { error in
                        for obvAttachment in attachmentsFullyReceivedOrCancelledByServer {
                            do {
                                try obvEngine.deleteObvAttachment(attachmentNumber: obvAttachment.number, ofMessageWithIdentifier: obvAttachment.messageIdentifier, ownedCryptoId: obvAttachment.fromContactIdentity.ownedCryptoId)
                            } catch {
                                os_log("Call to the engine method deleteObvAttachment did fail", log: log, type: .fault)
                                assertionFailure() // Continue anyway
                            }
                        }
                    }
                } catch {
                    assertionFailure(error.localizedDescription)
                }
            }

        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }

    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case contextIsNil
        case couldNotFindPersistedObvContactIdentityInDatabase
        case coreDataError(error: Error)
        case persistedObvContactIdentityObvError(error: ObvUICoreDataError)
        case persistedMessageReceivedObvError(error: PersistedMessageReceived.ObvError)
        case couldNotFindOwnedIdentity
        
        var logType: OSLogType {
            switch self {
            case .couldNotFindPersistedObvContactIdentityInDatabase:
                return .error
            case .contextIsNil,
                    .coreDataError,
                    .persistedMessageReceivedObvError,
                    .couldNotFindOwnedIdentity,
                    .persistedObvContactIdentityObvError:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .contextIsNil:
                return "The context is not set"
            case .couldNotFindPersistedObvContactIdentityInDatabase:
                return "Could not find contact identity of received message in database"
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .persistedObvContactIdentityObvError(error: let error):
                return "PersistedObvContactIdentity error: \(error.localizedDescription)"
            case .persistedMessageReceivedObvError(error: let error):
                return "PersistedMessageReceived error: \(error.localizedDescription)"
            case .couldNotFindOwnedIdentity:
                return "Could not find owned identity"
            }
        }
        
    }

}
