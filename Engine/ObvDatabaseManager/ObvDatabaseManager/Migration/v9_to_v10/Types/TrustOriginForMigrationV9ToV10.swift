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
import ObvEncoder

enum TrustOriginForMigrationV9ToV10 {
    case direct(timestamp: Date)
    case group(timestamp: Date, groupId: GroupIdentifierForMigrationV9ToV10)
    case introduction(timestamp: Date, mediator: ObvCryptoIdentity)
}

extension TrustOriginForMigrationV9ToV10: ObvCodable {

    public var byteId: UInt8 {
        switch self {
        case .direct:
            return 0x00
        case .group:
            return 0x01
        case .introduction:
            return 0x02
        }
    }

    public func encode() -> ObvEncoded {
        var values: [ObvCodable] = [self.byteId]
        switch self {
        case .direct(timestamp: let timestamp):
            values.append(timestamp)
        case .group(timestamp: let timestamp, groupId: let groupId):
            values.append(timestamp)
            values.append(groupId)
        case .introduction(timestamp: let timestamp, mediator: let mediator):
            values.append(timestamp)
            values.append(mediator)
        }
        let arrayOfEncodedValues = values.map { $0.encode() }
        return arrayOfEncodedValues.encode()
    }


    public init?(_ obvEncoded: ObvEncoded) {
        guard let arrayOfEncodedValues = [ObvEncoded](obvEncoded) else { return nil }
        guard let encodedByteId = arrayOfEncodedValues.first else { return nil }
        guard let byteId = UInt8(encodedByteId) else { return nil }
        switch byteId {
        case 0x00:
            guard arrayOfEncodedValues.count == 2 else { return nil }
            guard let timestamp = Date(arrayOfEncodedValues[1]) else { return nil }
            self = .direct(timestamp: timestamp)
        case 0x01:
            guard arrayOfEncodedValues.count == 3 else { return nil }
            guard let timestamp = Date(arrayOfEncodedValues[1]) else { return nil }
            guard let groupId = GroupIdentifierForMigrationV9ToV10(arrayOfEncodedValues[2]) else { return nil }
            self = .group(timestamp: timestamp, groupId: groupId)
        case 0x02:
            guard arrayOfEncodedValues.count == 3 else { return nil }
            guard let timestamp = Date(arrayOfEncodedValues[1]) else { return nil }
            guard let mediator = ObvCryptoIdentity(arrayOfEncodedValues[2]) else { return nil }
            self = .introduction(timestamp: timestamp, mediator: mediator)
        default:
            return nil
        }
    }

}
