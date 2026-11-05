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
import ObvEncoder


/// What a return receipt carries, once decrypted: who received a message, and what they did with it.
///
/// Both ends use this type, so the encoding is in one place: a receipt we owe is encrypted from one of these, and a
/// receipt a contact sends about a message of ours is decrypted into one.
///
/// This is a wire format, implemented by Android and by the desktop too, so these bytes cannot change.
/// `ObvReturnReceiptPayloadTests` freezes them.
public struct ObvReturnReceiptPayload: ObvCodable, Sendable {

    /// The identity that received the message: our owned identity in a receipt we write, the contact's in a receipt
    /// we read.
    public let author: ObvCryptoId

    public let status: ObvReturnReceiptStatus

    /// Nil when the receipt is about the message rather than about one of its attachments. The encoding then has two
    /// elements instead of three.
    public let attachmentNumber: Int?

    public init(author: ObvCryptoId, status: ObvReturnReceiptStatus, attachmentNumber: Int?) {
        self.author = author
        self.status = status
        self.attachmentNumber = attachmentNumber
    }


    public func obvEncode() -> ObvEncoded {
        // The identity is encoded as its bytes rather than through `ObvCryptoId`'s own conformance, so the wire
        // format does not move if that conformance does.
        var elements: [ObvEncodable] = [author.getIdentity(), status]
        if let attachmentNumber {
            elements += [attachmentNumber]
        }
        return elements.obvEncode()
    }


    public init?(_ obvEncoded: ObvEncoded) {
        guard let elements = [ObvEncoded](obvEncoded) else { return nil }
        guard [2, 3].contains(elements.count) else { return nil }
        guard let identity = Data(elements[0]), let author = try? ObvCryptoId(identity: identity) else { return nil }
        guard let status = ObvReturnReceiptStatus(elements[1]) else { return nil }
        var attachmentNumber: Int?
        if elements.count == 3 {
            guard let number = Int(elements[2]) else { return nil }
            attachmentNumber = number
        }
        self.init(author: author, status: status, attachmentNumber: attachmentNumber)
    }

}
