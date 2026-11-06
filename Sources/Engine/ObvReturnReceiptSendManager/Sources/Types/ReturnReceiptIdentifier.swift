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
import ObvTypes


/// Names one row of `PersistedReturnReceiptToSend`. These are the columns of the uniqueness constraint.
///
/// Rows are deleted by identifier, never by `NSManagedObjectID`. Two reasons. The id of a row just inserted is
/// temporary until the save. And when the constraint merges the inserts of two processes, one process can hold the id
/// of the object that the merge dropped, whereas two identifiers built from the same receipt are always equal, so
/// both processes name the row that survived.
struct ReturnReceiptIdentifier: Hashable, Sendable {

    let contactIdentifier: ObvContactIdentifier
    let nonce: Data
    let status: ObvReturnReceiptStatus
    /// Nil for a receipt about the message itself, rather than about one of its attachments.
    let attachmentNumber: Int?

    init(contactIdentifier: ObvContactIdentifier, nonce: Data, status: ObvReturnReceiptStatus, attachmentNumber: Int?) {
        self.contactIdentifier = contactIdentifier
        self.nonce = nonce
        self.status = status
        self.attachmentNumber = attachmentNumber
    }

    init(returnReceiptToSend: ObvReturnReceiptToSend) {
        self.init(contactIdentifier: returnReceiptToSend.contactIdentifier,
                  nonce: returnReceiptToSend.elements.nonce,
                  status: returnReceiptToSend.status,
                  attachmentNumber: returnReceiptToSend.attachmentNumber)
    }

}
