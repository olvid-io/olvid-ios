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
import CoreData
import os.log
import ObvCrypto
import OlvidUtils
import ObvUICoreData
import ObvTypes


final class CreatePersistedMessageReceivedFromReceivedObvMessageOperation: ContextualOperationWithSpecificReasonForCancel<CreatePersistedMessageReceivedFromReceivedObvMessageOperation.ReasonForCancel>, OperationProvidingDiscussionPermanentID, OperationProvidingMessageReceivedPermanentID {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "CreatePersistedMessageReceivedFromReceivedObvMessageOperation")

    private let obvMessage: ObvMessage
    private let messageJSON: MessageJSON
    private let returnReceiptJSON: ReturnReceiptJSON?
    private let overridePreviousPersistedMessage: Bool

    init(obvMessage: ObvMessage, messageJSON: MessageJSON, overridePreviousPersistedMessage: Bool, returnReceiptJSON: ReturnReceiptJSON?) {
        self.obvMessage = obvMessage
        self.messageJSON = messageJSON
        self.returnReceiptJSON = returnReceiptJSON
        self.overridePreviousPersistedMessage = overridePreviousPersistedMessage
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

    
    private(set) var messageReceivedPermanentId: MessageReceivedPermanentID?
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        os_log("Executing a CreatePersistedMessageReceivedFromReceivedObvMessageOperation for obvMessage %{public}@", log: log, type: .debug, obvMessage.messageIdentifierFromEngine.debugDescription)
        
        do {
            
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: obvMessage.fromContactIdentity.ownedCryptoId, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindOwnedIdentity)
            }
            
            // Create or update the PersistedMessageReceived from that contact
            
            do {
                let _discussionPermanentID: DiscussionPermanentID
                let _messageReceivedPermanentId: MessageReceivedPermanentID?
                
                (_discussionPermanentID, _messageReceivedPermanentId) = try ownedIdentity.createOrOverridePersistedMessageReceived(
                    obvMessage: obvMessage,
                    messageJSON: messageJSON,
                    returnReceiptJSON: returnReceiptJSON,
                    overridePreviousPersistedMessage: overridePreviousPersistedMessage)
                self.messageReceivedPermanentId = _messageReceivedPermanentId
                self.result = .messageCreated(discussionPermanentID: _discussionPermanentID)

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
