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
import ObvAppTypes

extension ObvCrypto.UID {

    static func deterministicUID(messageAppIdentifier: ObvMessageAppIdentifier) throws -> UID {

        var dataToHash = Data()
        dataToHash.append(messageAppIdentifier.obvEncode().rawData)
        let sha = ObvCryptoSuite.sharedInstance.hashFunctionSha256()
        let hash = sha.hash(dataToHash)

        guard let uid = UID(uid: hash) else {
            assertionFailure()
            throw ObvUICoreDataError.couldNotComputeDeterministicUID
        }

        return uid

    }

}
