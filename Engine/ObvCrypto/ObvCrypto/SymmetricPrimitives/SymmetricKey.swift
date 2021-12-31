/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

public protocol SymmetricKey: CryptographicKey {
    static var length: Int { get }
    var data: Data { get }
    init?(obvDictionaryOfInternalElements obvDict: ObvDictionary)
}

extension SymmetricKey {
    var correspondingObvEncodedByteId: ByteIdOfObvEncoded {
        return .symmetricKey
    }
}
