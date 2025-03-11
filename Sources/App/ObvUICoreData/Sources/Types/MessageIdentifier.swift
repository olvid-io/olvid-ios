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
    case authorIdentifier(writerIdentifier: MessageWriterIdentifier)
}

public enum ReceivedMessageIdentifier {
    case objectID(objectID: NSManagedObjectID)
    case authorIdentifier(writerIdentifier: MessageWriterIdentifier)
}

public enum SystemMessageIdentifier {
    case objectID(objectID: NSManagedObjectID)
}

public struct MessageWriterIdentifier {
    public let senderSequenceNumber: Int
    public let senderThreadIdentifier: UUID
    public let senderIdentifier: Data // Bytes of the identity of the writer
}
