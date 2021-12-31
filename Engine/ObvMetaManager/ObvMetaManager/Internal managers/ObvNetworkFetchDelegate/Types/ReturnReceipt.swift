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
import ObvCrypto
import ObvTypes


/// This types allows to instantiate a return receipt at the level of the fetch manager, and to propagate this receipt up to the engine.
public struct ReturnReceipt {
    
    public let identity: ObvCryptoIdentity
    public let serverUid: UID
    public let nonce: Data
    public let encryptedPayload: EncryptedData
    public let timestamp: Date
    
    public init(identity: ObvCryptoIdentity, serverUid: UID, nonce: Data, encryptedPayload: EncryptedData, timestamp: Date) {
        self.identity = identity
        self.serverUid = serverUid
        self.nonce = nonce
        self.encryptedPayload = encryptedPayload
        self.timestamp = timestamp
    }

}
