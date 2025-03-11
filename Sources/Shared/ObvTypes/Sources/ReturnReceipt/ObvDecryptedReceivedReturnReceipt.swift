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
@preconcurrency import ObvCrypto


public struct ObvDecryptedReceivedReturnReceipt {

    public let contactCryptoId: ObvCryptoId
    public let status: ObvReturnReceiptStatus
    public let attachmentNumber: Int?
    private let encryptedReceivedReturnReceipt: ObvEncryptedReceivedReturnReceipt
    
    public var contactIdentifier: ObvContactIdentifier {
        .init(contactCryptoId: contactCryptoId, ownedCryptoId: encryptedReceivedReturnReceipt.ownedCryptoId)
    }
    
    public var nonce: Data {
        encryptedReceivedReturnReceipt.nonce
    }
    
    public var timestamp: Date {
        encryptedReceivedReturnReceipt.timestamp
    }
    
    public init(contactCryptoId: ObvCryptoId, status: ObvReturnReceiptStatus, attachmentNumber: Int?, encryptedReceivedReturnReceipt: ObvEncryptedReceivedReturnReceipt) {
        self.contactCryptoId = contactCryptoId
        self.status = status
        self.attachmentNumber = attachmentNumber
        self.encryptedReceivedReturnReceipt = encryptedReceivedReturnReceipt
    }
    
}
