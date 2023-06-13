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
import os.log


// MARK: - Thread safe struct

extension PersistedContactGroup {

    public struct Structure {
        
        public let groupUid: UID
        let groupName: String
        let category: Category
        public let displayPhotoURL: URL?
        public let contactIdentities: Set<PersistedObvContactIdentity.Structure>
        
        private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedContactGroup.Structure")

        public init(groupUid: UID, groupName: String, category: Category, displayPhotoURL: URL?, contactIdentities: Set<PersistedObvContactIdentity.Structure>) {
            self.groupUid = groupUid
            self.groupName = groupName
            self.category = category
            self.displayPhotoURL = displayPhotoURL
            self.contactIdentities = contactIdentities
        }
    }

    public func toStruct() throws -> Structure {
        let contactIdentities = Set(try self.contactIdentities.map { try $0.toStruct() })
        return Structure(groupUid: self.groupUid,
                         groupName: self.groupName,
                         category: self.category,
                         displayPhotoURL: self.displayPhotoURL,
                         contactIdentities: contactIdentities)
    }
    
}
