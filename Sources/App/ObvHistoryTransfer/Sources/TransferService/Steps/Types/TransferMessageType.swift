/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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

enum TransferMessageType: UInt8 {
    case ack = 0
    case sourceDiscussionList = 1
    case sourceDiscussionRanges = 2
    case destinationExpectedSha256 = 3
    case destinationExpectedRanges = 4
    case sourceMessages = 5
    case destinationRequestSha256 = 6
    case destinationDoNotRequestSha256 = 7
    case sourceSha256 = 8
    case sourceDiscussionDone = 9
    case sourceTransferDone = 10
    
    init(_ data: Data) throws {
        guard data.count == 1, let byte = data.first else {
            assertionFailure()
            throw ObvError.couldNotParseTransferMessageType
        }
        guard let type = TransferMessageType(rawValue: byte) else {
            assertionFailure()
            throw ObvError.couldNotParseTransferMessageType
        }
        self = type
    }
}

extension TransferMessageType {
    
    enum ObvError: Error {
        case couldNotParseTransferMessageType
    }
    
}


extension TransferMessageType: CustomStringConvertible {
    
    var description: String {
        switch self {
        case .ack: return "ack"
        case .sourceDiscussionList: return "sourceDiscussionList"
        case .sourceDiscussionRanges: return "sourceDiscussionRanges"
        case .destinationExpectedSha256: return "destinationExpectedSha256"
        case .destinationExpectedRanges: return "destinationExpectedRanges"
        case .sourceMessages: return "sourceMessages"
        case .destinationRequestSha256: return "destinationRequestSha256"
        case .destinationDoNotRequestSha256: return "destinationDoNotRequestSha256"
        case .sourceSha256: return "sourceSha256"
        case .sourceDiscussionDone: return "sourceDiscussionDone"
        case .sourceTransferDone: return "sourceTransferDone"
        }
    }
    
}
