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
import os.log


// MARK: - Thread safe struct

extension PersistedGroupV2 {
    
    public struct Structure {
        
        public let groupIdentifier: Data
        let displayName: String
        public let displayPhotoURL: URL?
        public let contactIdentities: Set<PersistedObvContactIdentity.Structure>
        
        private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedGroupV2.Structure")
        
        public init(groupIdentifier: Data, displayName: String, displayPhotoURL: URL?, contactIdentities: Set<PersistedObvContactIdentity.Structure>) {
            self.groupIdentifier = groupIdentifier
            self.displayName = displayName
            self.displayPhotoURL = displayPhotoURL
            self.contactIdentities = contactIdentities
        }
    }

    func toStruct() throws -> Structure {
        let contactIdentities = Set(try self.contactsAmongOtherPendingAndNonPendingMembers.map({ try $0.toStruct() }))
        return Structure(groupIdentifier: self.groupIdentifier,
                         displayName: self.displayName,
                         displayPhotoURL: self.displayPhotoURL,
                         contactIdentities: contactIdentities)
    }
    
}
