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
import ObvAppCoreConstants
import ObvAppTypes


final class CreatePersistedMessageReceivedFromReceivedObvMessageOperation: ContextualOperationWithSpecificReasonForCancel<CreatePersistedMessageReceivedFromReceivedObvMessageOperation.ReasonForCancel>, @unchecked Sendable, OperationProvidingDiscussionPermanentID, OperationProvidingMessageReceivedPermanentID {

    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "CreatePersistedMessageReceivedFromReceivedObvMessageOperation")

    private let obvMessage: ObvMessage
    private let messageJSON: MessageJSON
    private let returnReceiptJSON: ReturnReceiptJSON?
    private let source: ObvMessageSource

    init(obvMessage: ObvMessage, messageJSON: MessageJSON, source: ObvMessageSource, returnReceiptJSON: ReturnReceiptJSON?) {
        self.obvMessage = obvMessage
        self.messageJSON = messageJSON
        self.returnReceiptJSON = returnReceiptJSON
        self.source = source
        super.init()
    }

    enum Result {
        case couldNotFindGroupV2InDatabase(groupIdentifier: GroupV2Identifier)
        case couldNotFindContactInDatabase(contactCryptoId: ObvCryptoId)
        case couldNotFindOneToOneContactInDatabase(contactCryptoId: ObvCryptoId)
        case messageCreated(discussionPermanentID: DiscussionPermanentID)
        case contactIsNotPartOfTheGroup(groupIdentifier: GroupV2Identifier, contactCryptoId: ObvCryptoId)
        case messageIsPriorToLastRemoteDeletionRequest
        case cannotCreateReceivedMessageThatAlreadyExpired
    }
    
    private(set) var result: Result?
    
    
    var discussionPermanentID: ObvUICoreData.DiscussionPermanentID? {
        switch result {
        case .messageIsPriorToLastRemoteDeletionRequest, .couldNotFindGroupV2InDatabase, .couldNotFindContactInDatabase, .couldNotFindOneToOneContactInDatabase, .contactIsNotPartOfTheGroup, .cannotCreateReceivedMessageThatAlreadyExpired, nil:
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
                return cancel(withReason: .couldNotFindOwnedIdentityInDatabase)
            }
            
            // Create or update the PersistedMessageReceived from that contact
            
            do {
                
                let result = try ownedIdentity.createOrOverridePersistedMessageReceived(
                    obvMessage: obvMessage,
                    messageJSON: messageJSON,
                    returnReceiptJSON: returnReceiptJSON,
                    source: source)
                
                self.messageReceivedPermanentId = result.messageReceivedPermanentId
                self.result = .messageCreated(discussionPermanentID: result.discussionPermanentID)

            } catch {
                
                switch error {
                    
                case let error as ObvUICoreDataError:
                    
                    switch error {
                        
                    case .cannotCreateReceivedMessageThatAlreadyExpired:
                        result = .cannotCreateReceivedMessageThatAlreadyExpired
                        return
                        
                    case .messageIsPriorToLastRemoteDeletionRequest:
                        result = .messageIsPriorToLastRemoteDeletionRequest
                        return
                        
                    case .couldNotFindGroupV2InDatabase(groupIdentifier: let groupIdentifier):
                        result = .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
                        return

                    case .couldNotFindContactWithId(contactIdentifier: let contactIdentifier):
                        result = .couldNotFindContactInDatabase(contactCryptoId: contactIdentifier.contactCryptoId)
                        return
                        
                    case .couldNotFindOneToOneContactWithId(contactIdentifier: let contactIdentifier):
                        result = .couldNotFindOneToOneContactInDatabase(contactCryptoId: contactIdentifier.contactCryptoId)
                        return
                        
                    case .contactIsNotPartOfTheGroup(groupIdentifier: let groupIdentifier, contactIdentifier: let contactIdentifier):
                        result = .contactIsNotPartOfTheGroup(groupIdentifier: groupIdentifier, contactCryptoId: contactIdentifier.contactCryptoId)
                        return

                    default:
                        assertionFailure("We should make sure the type thrown doesn't deserve a special treatment, potentially allowing the message to wait like it does for the, e.g., couldNotFindGroupV2InDatabase error")
                        return cancel(withReason: .obvUICoreDataError(error: error))

                    }
                    
                default:
                    
                    assertionFailure("This is unexpected, as the ObvUICoreData module should only throw errors of the ObvUICoreDataError type")
                    return cancel(withReason: .coreDataError(error: error))

                }

            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }

    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case couldNotFindOwnedIdentityInDatabase
        case obvUICoreDataError(error: ObvUICoreDataError)
        case coreDataError(error: Error)

        var logType: OSLogType {
            switch self {
            case .couldNotFindOwnedIdentityInDatabase:
                return .error
            case .obvUICoreDataError, .coreDataError:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .couldNotFindOwnedIdentityInDatabase:
                return "Could not find owned identity in database"
            case .obvUICoreDataError(error: let error):
                return "ObvUICoreDataError error: \(error.localizedDescription)"
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            }
        }
        
    }

}
