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
import os.log
import CoreData
import OlvidUtils
import ObvUICoreData
import ObvTypes


final class MarkAsReadReceivedMessageOperation: ContextualOperationWithSpecificReasonForCancel<MarkAsReadReceivedMessageOperation.ReasonForCancel>, OperationProvidingDiscussionReadJSON {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: MarkAsReadReceivedMessageOperation.self))

    let contactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>
    let messageIdentifierFromEngine: Data

    private(set) var persistedMessageReceivedObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>?

    init(contactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>, messageIdentifierFromEngine: Data) {
        self.contactPermanentID = contactPermanentID
        self.messageIdentifierFromEngine = messageIdentifierFromEngine
        super.init()
    }

    private(set) var ownedCryptoId: ObvCryptoId?
    private(set) var ownedIdentityHasAnotherReachableDevice = false
    private(set) var discussionReadJSONToSend: DiscussionReadJSON?

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let contactIdentity = try PersistedObvContactIdentity.getManagedObject(withPermanentID: contactPermanentID, within: obvContext.context) else {
                assertionFailure()
                return cancel(withReason: .couldNotFindContactIdentityInDatabase)
            }

            guard let (discussionId, receivedMessageId): (DiscussionIdentifier, ReceivedMessageIdentifier) = try contactIdentity.getReceivedMessageIdentifiers(messageIdentifierFromEngine: messageIdentifierFromEngine) else {
                assertionFailure()
                return cancel(withReason: .couldNotFindReceivedMessageInDatabase)
            }

            guard let ownedIdentity = contactIdentity.ownedIdentity else {
                assertionFailure()
                return cancel(withReason: .couldNotFindOwnedIdentity)
            }
            
            self.ownedCryptoId = ownedIdentity.cryptoId
            self.ownedIdentityHasAnotherReachableDevice = ownedIdentity.hasAnotherDeviceWhichIsReachable
            
            let dateWhenMessageTurnedNotNew = Date()
            let lastReadMessageServerTimestamp = try ownedIdentity.markReceivedMessageAsNotNew(discussionId: discussionId, receivedMessageId: receivedMessageId, dateWhenMessageTurnedNotNew: dateWhenMessageTurnedNotNew)
            
            do {
                if let lastReadMessageServerTimestamp {
                    discussionReadJSONToSend = try ownedIdentity.getDiscussionReadJSON(discussionId: discussionId, lastReadMessageServerTimestamp: lastReadMessageServerTimestamp)
                }
            } catch {
                assertionFailure(error.localizedDescription) // Continue anyway
            }

            
            do {
                persistedMessageReceivedObjectID = try ownedIdentity.getReceivedMessageTypedObjectID(discussionId: discussionId, receivedMessageId: receivedMessageId)
            } catch {
                assertionFailure(error.localizedDescription) // Continue anyway
            }
            
        } catch(let error) {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {

        case coreDataError(error: Error)
        case couldNotFindContactIdentityInDatabase
        case couldNotFindReceivedMessageInDatabase
        case couldNotFindOwnedIdentity

        var logType: OSLogType {
            switch self {
            case .couldNotFindOwnedIdentity, .coreDataError:
                return .fault
            case .couldNotFindReceivedMessageInDatabase, .couldNotFindContactIdentityInDatabase:
                return .error
            }
        }

        var errorDescription: String? {
            switch self {
            case .couldNotFindContactIdentityInDatabase: return "Could not obtain persisted contact identity in database"
            case .coreDataError(error: let error): return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindReceivedMessageInDatabase: return "Could not find received message in database"
            case .couldNotFindOwnedIdentity: return "Could not find owned identity"
            }
        }

    }

}
