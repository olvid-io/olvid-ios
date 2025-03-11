/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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


public enum ObvCapability: String, CaseIterable {
    case webrtcContinuousICE = "webrtc_continuous_ice"
    case groupsV2 = "groups_v2"
    case oneToOneContacts = "one_to_one_contacts"
}


extension Set<ObvCapability>: ObvCodable {
    
    public func obvEncode() -> ObvEncoder.ObvEncoded {
        self.map({ $0.rawValue.obvEncode() }).obvEncode()
    }

    public init?(_ obvEncoded: ObvEncoder.ObvEncoded) {
        guard let arrayOfEncoded = [ObvEncoded](obvEncoded) else { assertionFailure(); return nil }
        var capabilities = Set<ObvCapability>()
        for encoded in arrayOfEncoded {
            guard let rawCapability: String = try? encoded.obvDecode() else { assertionFailure(); continue }
            guard let capability = ObvCapability(rawValue: rawCapability) else { assertionFailure(); continue }
            capabilities.insert(capability)
        }
        self = capabilities
    }
            
}

extension ObvCapability: Identifiable {

    public var id: String {
        self.rawValue
    }
    
}
