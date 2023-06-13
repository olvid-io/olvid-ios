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


public struct GroupV2CoreDetails: Codable, Equatable {
    
    let groupName: String?
    let groupDescription: String?
    
    public init(groupName: String?, groupDescription: String?) {
        self.groupName = groupName?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).mapToNilIfZeroLength()
        self.groupDescription = groupDescription?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).mapToNilIfZeroLength()
    }
    
    enum CodingKeys: String, CodingKey {
        case groupName = "name"
        case groupDescription = "description"
    }

    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }

    static func jsonDecode(serializedGroupCoreDetails: Data) throws -> Self {
        let decoder = JSONDecoder()
        return try decoder.decode(Self.self, from: serializedGroupCoreDetails)
    }

}
