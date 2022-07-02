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
import OlvidUtils

final class MarkAsReadReceivedMessageOperation: ContextualOperationWithSpecificReasonForCancel<MarkAsReadReceivedMessageOperationReasonForCancel> {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: MarkAsReadReceivedMessageOperation.self))

    let persistedContactObjectID: NSManagedObjectID
    let messageIdentifierFromEngine: Data

    private(set) var persistedMessageReceivedObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>?

    init(persistedContactObjectID: NSManagedObjectID, messageIdentifierFromEngine: Data) {
        self.persistedContactObjectID = persistedContactObjectID
        self.messageIdentifierFromEngine = messageIdentifierFromEngine
        super.init()
    }

    override func main() {

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {
            do {
                guard let contactIdentity = try PersistedObvContactIdentity.get(objectID: persistedContactObjectID, within: obvContext.context) else {
                    assertionFailure()
                    return cancel(withReason: .couldNotFindContactIdentityInDatabase)
                }

                // Find message to mark as read
                guard let message = try PersistedMessageReceived.get(messageIdentifierFromEngine: messageIdentifierFromEngine, from: contactIdentity) else {
                    assertionFailure()
                    return cancel(withReason: .couldNotFindReceivedMessageInDatabase)
                }

                try message.markAsNotNew(now: Date())
                
                persistedMessageReceivedObjectID = message.typedObjectID

            } catch(let error) {
                assertionFailure()
                return cancel(withReason: .coreDataError(error: error))
            }
        }

    }
}

enum MarkAsReadReceivedMessageOperationReasonForCancel: LocalizedErrorWithLogType {

    case contextIsNil
    case coreDataError(error: Error)
    case couldNotFindContactIdentityInDatabase
    case couldNotFindReceivedMessageInDatabase

    var logType: OSLogType {
        switch self {
        case .contextIsNil:
            return .fault
        case .coreDataError:
            return .fault
        case .couldNotFindReceivedMessageInDatabase:
            return .error
        case .couldNotFindContactIdentityInDatabase:
            return .error
        }
    }

    var errorDescription: String? {
        switch self {
        case .contextIsNil: return "Context is nil"
        case .couldNotFindContactIdentityInDatabase: return "Could not obtain persisted contact identity in database"
        case .coreDataError(error: let error): return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindReceivedMessageInDatabase: return "Could not find received message in database"
        }
    }

}
