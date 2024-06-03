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



final class CreatePersistedMessageSentFromReceivedObvOwnedMessageOperation: ContextualOperationWithSpecificReasonForCancel<CreatePersistedMessageSentFromReceivedObvOwnedMessageOperation.ReasonForCancel> {
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "CreatePersistedMessageSentFromReceivedObvOwnedMessageOperation")

    private let obvOwnedMessage: ObvOwnedMessage
    private let messageJSON: MessageJSON
    private let returnReceiptJSON: ReturnReceiptJSON?
    
    init(obvOwnedMessage: ObvOwnedMessage, messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON?) {
        self.obvOwnedMessage = obvOwnedMessage
        self.messageJSON = messageJSON
        self.returnReceiptJSON = returnReceiptJSON
        super.init()
    }

    enum Result {
        case couldNotFindGroupV2InDatabase(groupIdentifier: GroupV2Identifier)
        case sentMessageCreated(messageSentPermanentId: MessageSentPermanentID)
        case remoteDeleteRequestSavedForLaterWasApplied
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
            
            do {
                
                let messageSentPermanentId = try persistedObvOwnedIdentity.createPersistedMessageSentFromOtherOwnedDevice(
                    obvOwnedMessage: obvOwnedMessage,
                    messageJSON: messageJSON,
                    returnReceiptJSON: returnReceiptJSON)
                if let messageSentPermanentId {
                    return result = .sentMessageCreated(messageSentPermanentId: messageSentPermanentId)
                } else {
                    return result = .remoteDeleteRequestSavedForLaterWasApplied
                }
                
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
                                    
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }

    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case couldNotFindOwnedIdentityInDatabase
        case persistedObvOwnedIdentityObvError(error: ObvUICoreDataError)
        case persistedMessageSentObvError(error: PersistedMessageSent.ObvError)

        var logType: OSLogType {
            switch self {
            case .couldNotFindOwnedIdentityInDatabase:
                return .error
            case .coreDataError,
                 .persistedMessageSentObvError,
                 .persistedObvOwnedIdentityObvError:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
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
