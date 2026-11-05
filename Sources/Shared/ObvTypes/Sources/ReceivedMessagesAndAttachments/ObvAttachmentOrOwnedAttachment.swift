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


/// An attachment this device downloads, whether it was sent by a contact or by the owned identity from another of her devices.
///
/// The counterpart of ``ObvMessageOrObvOwnedMessage`` one level down. The two cases differ in where the app records them — a
/// `ReceivedFyleMessageJoinWithStatus` against a `SentFyleMessageJoinWithStatus` — and in almost nothing else: both arrive through the same inbox, are fetched
/// by the same chunk machinery, are resumed and paused through the same engine calls, and fail in the same ways. Anything that acts on an attachment *as a
/// download* can take this and stay indifferent to which it has.
public enum ObvAttachmentOrOwnedAttachment: Equatable, Hashable {

    case obvAttachment(ObvAttachment)
    case obvOwnedAttachment(ObvOwnedAttachment)

    public var attachmentId: ObvAttachmentIdentifier {
        switch self {
        case .obvAttachment(let obvAttachment):
            obvAttachment.attachmentId
        case .obvOwnedAttachment(let obvOwnedAttachment):
            obvOwnedAttachment.attachmentId
        }
    }

    public var status: ObvAttachment.Status {
        switch self {
        case .obvAttachment(let obvAttachment):
            obvAttachment.status
        case .obvOwnedAttachment(let obvOwnedAttachment):
            obvOwnedAttachment.status
        }
    }

    /// The identity this attachment belongs to. For a received attachment that is the owned identity the sender is a contact *of*, not the sender.
    public var ownedCryptoId: ObvCryptoId {
        switch self {
        case .obvAttachment(let obvAttachment):
            obvAttachment.fromContactIdentity.ownedCryptoId
        case .obvOwnedAttachment(let obvOwnedAttachment):
            obvOwnedAttachment.ownedCryptoId
        }
    }

    public var number: Int {
        switch self {
        case .obvAttachment(let obvAttachment):
            obvAttachment.number
        case .obvOwnedAttachment(let obvOwnedAttachment):
            obvOwnedAttachment.number
        }
    }

    public var messageIdentifier: Data {
        switch self {
        case .obvAttachment(let obvAttachment):
            obvAttachment.messageIdentifier
        case .obvOwnedAttachment(let obvOwnedAttachment):
            obvOwnedAttachment.messageIdentifier
        }
    }

}
