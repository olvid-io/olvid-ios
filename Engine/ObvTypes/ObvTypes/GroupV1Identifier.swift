/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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


/// 2023-09-23 Type introduced for sync snapshots. It should have been introduced earlier...
public struct GroupV1Identifier: Hashable, LosslessStringConvertible {

    public let groupUid: UID
    public let groupOwner: ObvCryptoId
    
    public init(groupUid: UID, groupOwner: ObvCryptoId) {
        self.groupUid = groupUid
        self.groupOwner = groupOwner
    }
    
    var rawData: Data {
        groupOwner.getIdentity() + groupUid.raw
    }
    
    init(rawData: Data) throws {
        guard rawData.count > UID.length else {
            throw ObvError.notEnoughData
        }
        let identity = rawData[0..<(rawData.count-UID.length)]
        self.groupOwner = try ObvCryptoId(identity: identity)
        guard let groupUid = UID(uid: rawData[(rawData.count-UID.length)..<rawData.count]) else {
            throw ObvError.couldNotRecoverGroupUid
        }
        self.groupUid = groupUid
    }
    
    enum ObvError: Error {
        case notEnoughData
        case couldNotRecoverGroupUid
    }
    
    // LosslessStringConvertible
    
    public var description: String {
        [groupOwner.getIdentity().base64EncodedString(), groupUid.raw.base64EncodedString()].joined(separator: "-")
    }
    
    public init?(_ description: String) {
        let values = description.split(separator: "-")
        guard values.count == 2 else { assertionFailure(); return nil }
        guard let groupOwnerIdentity = Data(base64Encoded: String(values[0])),
              let groupOwner = try? ObvCryptoId(identity: groupOwnerIdentity) else {
            assertionFailure()
            return nil
        }
        guard let rawUID = Data(base64Encoded: String(values[1])),
                let groupUid = UID(uid: rawUID) else {
            assertionFailure()
            return nil
        }
        self.init(groupUid: groupUid, groupOwner: groupOwner)
    }
    
}
