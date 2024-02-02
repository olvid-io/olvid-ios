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



final class CreatePersistedMessageSentFromReceivedObvOwnedMessageOperation: ContextualOperationWithSpecificReasonForCancel<CreatePersistedMessageSentFromReceivedObvOwnedMessageOperation.ReasonForCancel> {
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "CreatePersistedMessageSentFromReceivedObvOwnedMessageOperation")

    private let obvOwnedMessage: ObvOwnedMessage
    private let messageJSON: MessageJSON
    private let returnReceiptJSON: ReturnReceiptJSON?
    private let obvEngine: ObvEngine
    
    init(obvOwnedMessage: ObvOwnedMessage, messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON?, obvEngine: ObvEngine) {
        self.obvOwnedMessage = obvOwnedMessage
        self.messageJSON = messageJSON
        self.returnReceiptJSON = returnReceiptJSON
        self.obvEngine = obvEngine
        super.init()
    }

    
    enum Result {
        case couldNotFindGroupV2InDatabase(groupIdentifier: GroupV2Identifier)
        case sentMessageCreated
    }

    private(set) var result: Result?

    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        os_log("Executing a CreatePersistedMessageSentFromReceivedObvOwnedMessageOperation for obvOwnedMessage %{public}@", log: Self.log, type: .debug, obvOwnedMessage.messageIdentifierFromEngine.debugDescription)
        
        do {
            
            // Grab the persisted owned identity who sent the message on another owned device
            
            guard let persistedObvOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: obvOwnedMessage.ownedCryptoId, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindOwnedIdentityInDatabase)
            }
            
            // Create the PersistedMessageSent from that owned identity
            
            let attachmentFullyReceivedOrCancelledByServer: [ObvOwnedAttachment]
            
            do {
                attachmentFullyReceivedOrCancelledByServer = try persistedObvOwnedIdentity.createPersistedMessageSentFromOtherOwnedDevice(
                    obvOwnedMessage: obvOwnedMessage,
                    messageJSON: messageJSON,
                    returnReceiptJSON: returnReceiptJSON)
                result = .sentMessageCreated
            } catch {
                if let error = error as? ObvUICoreDataError {
                    switch error {
                    case .couldNotFindGroupV2InDatabase(groupIdentifier: let groupIdentifier):
                        result = .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
                        return
                    default:
                        assertionFailure()
                        return cancel(withReason: .persistedObvOwnedIdentityObvError(error: error))
                    }
                } else if let error = error as? PersistedMessageSent.ObvError {
                    assertionFailure()
                    return cancel(withReason: .persistedMessageSentObvError(error: error))
                } else {
                    assertionFailure("We should probably add the missing if/let case")
                    return cancel(withReason: .coreDataError(error: error))
                }
            }
            
            // We ask the engine to delete all the attachments that were fully received
            
            if !attachmentFullyReceivedOrCancelledByServer.isEmpty {
                let obvEngine = self.obvEngine
                do {
                    try obvContext.addContextDidSaveCompletionHandler { error in
                        for obvOwnedAttachment in attachmentFullyReceivedOrCancelledByServer {
                            do {
                                try obvEngine.deleteObvAttachment(
                                    attachmentNumber: obvOwnedAttachment.number,
                                    ofMessageWithIdentifier: obvOwnedAttachment.messageIdentifier,
                                    ownedCryptoId: obvOwnedAttachment.ownedCryptoId)
                            } catch {
                                os_log("Call to the engine method deleteObvAttachment did fail", log: Self.log, type: .fault)
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
        case coreDataError(error: Error)
        case couldNotFindOwnedIdentityInDatabase
        case persistedObvOwnedIdentityObvError(error: ObvUICoreDataError)
        case persistedMessageSentObvError(error: PersistedMessageSent.ObvError)

        var logType: OSLogType {
            switch self {
            case .couldNotFindOwnedIdentityInDatabase:
                return .error
            case .contextIsNil,
                 .coreDataError,
                 .persistedMessageSentObvError,
                 .persistedObvOwnedIdentityObvError:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .contextIsNil:
                return "The context is not set"
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindOwnedIdentityInDatabase:
                return "Could not find owned identity in database"
            case .persistedObvOwnedIdentityObvError(error: let error):
                return "PersistedObvOwnedIdentity error: \(error.localizedDescription)"
            case .persistedMessageSentObvError(error: let error):
                return "PersistedMessageSent error: \(error.localizedDescription)"
            }
        }
        
    }

}
