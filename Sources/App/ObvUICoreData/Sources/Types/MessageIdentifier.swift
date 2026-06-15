/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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


/// Warning: This is a legacy type that should not be used in new code. Consider `ObvMessageAppIdentifier` instead.
public enum MessageIdentifier {
    case sent(id: SentMessageIdentifier)
    case received(id: ReceivedMessageIdentifier)
    case system(id: SystemMessageIdentifier)
    
    public var objectID: NSManagedObjectID? {
        switch self {
        case .sent(let id):
            switch id {
            case .objectID(let objectID):
                return objectID
            default:
                return nil
            }
        case .received(let id):
            switch id {
            case .objectID(let objectID):
                return objectID
            default:
                return nil
            }
        case .system(let id):
            switch id {
            case .objectID(let objectID):
                return objectID
            }
        }
    }
    
}

public enum SentMessageIdentifier {
    case objectID(objectID: NSManagedObjectID)
    case authorIdentifier(writerIdentifier: MessageIdentifierInDiscussion)
}

public enum ReceivedMessageIdentifier {
    case objectID(objectID: NSManagedObjectID)
    case authorIdentifier(writerIdentifier: MessageIdentifierInDiscussion)
}

public enum SystemMessageIdentifier {
    case objectID(objectID: NSManagedObjectID)
}

/// Identifier that uniquely determines a message in a given discussion.
public struct MessageIdentifierInDiscussion {
    public let senderSequenceNumber: Int
    public let senderThreadIdentifier: UUID
    public let senderIdentifier: Data // Bytes of the identity of the writer
}
