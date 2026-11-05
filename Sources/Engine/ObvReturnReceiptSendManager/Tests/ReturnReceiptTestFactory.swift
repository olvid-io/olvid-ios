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
import ObvEncoder
import ObvTypes
@testable import ObvReturnReceiptSendManager


/// Builds the receipts the tests insert. The identities are real ones, generated here, because the server of a
/// contact is read from the bytes of its identity.
enum ReturnReceiptTestFactory {

    private static let prng = ObvCryptoSuite.sharedInstance.prngService()

    static func cryptoId(onServer serverURL: URL) -> ObvCryptoId {
        let owned = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng)
        return ObvCryptoId(cryptoIdentity: owned.getObvCryptoIdentity())
    }

    static func contactIdentifier(contactServerURL: URL, ownedServerURL: URL) -> ObvContactIdentifier {
        .init(contactCryptoId: cryptoId(onServer: contactServerURL), ownedCryptoId: cryptoId(onServer: ownedServerURL))
    }

    static func nonce() -> Data {
        Data(prng.genBytes(count: 16))
    }

    static func deviceUID() -> UID {
        UID(uid: prng.genBytes(count: UID.length))!
    }

    static func seed() -> Seed {
        prng.genSeed()
    }

    /// A real serialized authenticated-encryption key, as `ObvReturnReceiptElements` carries.
    ///
    /// Real, rather than any old bytes, because the uploader decodes it before encrypting with it. A key that cannot
    /// be decoded is a case a test asks for by name.
    static func key() -> Data {
        ObvCryptoSuite.sharedInstance.authenticatedEncryption().generateKey(with: prng).obvEncode().rawData
    }

    static func receipt(contactIdentifier: ObvContactIdentifier, nonce: Data, status: ObvReturnReceiptStatus = .delivered, attachmentNumber: Int? = nil, key: Data? = nil) -> ObvReturnReceiptToSend {
        .init(elements: .init(nonce: nonce, key: key ?? Self.key()),
              status: status,
              contactIdentifier: contactIdentifier,
              attachmentNumber: attachmentNumber)
    }


    /// A receipt with everything the uploader needs: the contact's devices and the seed, which the manager gathers
    /// when the receipt is about to leave.
    ///
    /// - Parameter contactDeviceUIDs: one device by default. A receipt with no device can never be sent, which is a
    ///   case a test asks for explicitly.
    static func receiptReadyToUpload(contactIdentifier: ObvContactIdentifier, nonce: Data, status: ObvReturnReceiptStatus = .delivered, attachmentNumber: Int? = nil, key: Data? = nil, contactDeviceUIDs: Set<UID>? = nil, createdAt: Date = Date.now) -> ReturnReceiptReadyToUpload {
        let returnReceiptToSend = receipt(contactIdentifier: contactIdentifier, nonce: nonce, status: status, attachmentNumber: attachmentNumber, key: key)
        return .init(returnReceipt: .init(returnReceiptToSend: returnReceiptToSend, createdAt: createdAt),
                     contactDeviceUIDs: contactDeviceUIDs ?? [deviceUID()],
                     seed: seed())
    }

}
