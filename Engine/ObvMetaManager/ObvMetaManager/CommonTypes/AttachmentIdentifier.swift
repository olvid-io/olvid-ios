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
import ObvEncoder

public struct AttachmentIdentifier: Equatable, Hashable {
    
    public let messageId: MessageIdentifier
    public let attachmentNumber: Int
    
    public init(messageId: MessageIdentifier, attachmentNumber: Int) {
        self.messageId = messageId
        self.attachmentNumber = attachmentNumber
    }
    
}

extension AttachmentIdentifier: CustomDebugStringConvertible {
    
    public var debugDescription: String {
        return "Attachment<\(messageId.debugDescription),\(attachmentNumber)>"
    }
    
}

extension AttachmentIdentifier: Codable {

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case attachmentNumber = "attachment_number"
    }

}

extension AttachmentIdentifier: RawRepresentable {

    public var rawValue: Data {
        let encoder = JSONEncoder()
        return try! encoder.encode(self)
    }

    public init?(rawValue: Data) {
        let decoder = JSONDecoder()
        guard let attachmentId = try? decoder.decode(AttachmentIdentifier.self, from: rawValue) else { return nil }
        self = attachmentId
    }

}

extension AttachmentIdentifier: LosslessStringConvertible {

    public var description: String {
        return String(data: self.rawValue, encoding: .utf8)!
    }
    
    public init?(_ description: String) {
        guard let rawValue = description.data(using: .utf8) else { assertionFailure(); return nil }
        self.init(rawValue: rawValue)
    }

}
