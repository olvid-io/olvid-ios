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



final class CreatePersistedMessageSentFromReceivedObvOwnedMessageOperation: ContextualOperationWithSpecificReasonForCancel<CreatePersistedMessageSentFromReceivedObvOwnedMessageOperation.ReasonForCancel>, @unchecked Sendable {
    
    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "CreatePersistedMessageSentFromReceivedObvOwnedMessageOperation")

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
        case couldNotFindOneToOneContactInDatabase(contactCryptoId: ObvCryptoId)
        case couldNotFindContactInDatabase(contactCryptoId: ObvCryptoId)
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
                
                switch error {
                    
                case let error as ObvUICoreDataError:
                    
                    switch error {
                        
                    case .couldNotFindGroupV2InDatabase(groupIdentifier: let groupIdentifier):
                        result = .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
                        return
                        
                    case .couldNotFindOneToOneContactWithId(contactIdentifier: let contactIdentifier):
                        result = .couldNotFindOneToOneContactInDatabase(contactCryptoId: contactIdentifier.contactCryptoId)
                        return
                        
                    case .couldNotFindContactWithId(contactIdentifier: let contactIdentifier):
                        result = .couldNotFindContactInDatabase(contactCryptoId: contactIdentifier.contactCryptoId)
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
