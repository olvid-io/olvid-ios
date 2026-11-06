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
import ObvCrypto
import ObvTypes


/// One receipt we owe, ready to be encrypted and uploaded.
///
/// A managed object belongs to the queue of its context, and a send cycle spans a network round trip. So nothing but
/// values like this one leaves a `perform` block. This is `ObvReturnReceiptToSend` without the contact devices, which
/// are resolved at send time, plus the server that the batch is grouped by.
struct ReturnReceiptToUpload: Sendable {

    let identifier: ReturnReceiptIdentifier
    let key: Data
    /// The server of the **contact**, not of the owned identity. The two differ on self-hosted servers.
    let serverURL: URL
    let createdAt: Date

    var elements: ObvReturnReceiptElements {
        .init(nonce: identifier.nonce, key: key)
    }

    /// The value of a row, built inside the context it was fetched in.
    init(identifier: ReturnReceiptIdentifier, key: Data, serverURL: URL, createdAt: Date) {
        self.identifier = identifier
        self.key = key
        self.serverURL = serverURL
        self.createdAt = createdAt
    }

    /// The value of a receipt this process has just been handed, before its row exists.
    ///
    /// The only conversion of a receipt into what is stored and uploaded: the row is built from this value rather than
    /// from the receipt, so the server a batch is sent to and the column a drain fetches by cannot disagree.
    init(returnReceiptToSend: ObvReturnReceiptToSend, createdAt: Date) {
        self.identifier = .init(returnReceiptToSend: returnReceiptToSend)
        self.key = returnReceiptToSend.elements.key
        // The server of the contact, who receives the receipt, and not that of the owned identity. The two differ on
        // self-hosted servers, and a batch sent to the wrong server is lost.
        self.serverURL = returnReceiptToSend.contactIdentifier.contactCryptoId.serverURL
        self.createdAt = createdAt
    }

    /// The same receipt in the shape the engine's delegate is asked about.
    var returnReceiptToSend: ObvReturnReceiptToSend {
        .init(elements: elements,
              status: identifier.status,
              contactIdentifier: identifier.contactIdentifier,
              attachmentNumber: identifier.attachmentNumber)
    }

}
