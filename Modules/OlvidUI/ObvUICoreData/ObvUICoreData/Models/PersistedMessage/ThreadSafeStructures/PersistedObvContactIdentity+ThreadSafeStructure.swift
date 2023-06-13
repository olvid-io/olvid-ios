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
import ObvTypes
import os.log


// MARK: - Thread safe struct

extension PersistedObvContactIdentity {
    
    public struct Structure: Hashable, Equatable {
        
        public let objectPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>
        public let cryptoId: ObvCryptoId
        public let fullDisplayName: String
        public let customOrFullDisplayName: String
        public let displayPhotoURL: URL?
        public let personNameComponents: PersonNameComponents
        public let ownedIdentity: PersistedObvOwnedIdentity.Structure
        
        private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedObvContactIdentity.Structure")

        // Hashable and equatable
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(objectPermanentID)
        }
        
        public static func == (lhs: Structure, rhs: Structure) -> Bool {
            lhs.objectPermanentID == rhs.objectPermanentID
        }
        
        public init(objectPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>, cryptoId: ObvCryptoId, fullDisplayName: String, customOrFullDisplayName: String, displayPhotoURL: URL?, personNameComponents: PersonNameComponents, ownedIdentity: PersistedObvOwnedIdentity.Structure) {
            self.objectPermanentID = objectPermanentID
            self.cryptoId = cryptoId
            self.fullDisplayName = fullDisplayName
            self.customOrFullDisplayName = customOrFullDisplayName
            self.displayPhotoURL = displayPhotoURL
            self.personNameComponents = personNameComponents
            self.ownedIdentity = ownedIdentity
        }
    }

    
    public func toStruct() throws -> Structure {
        guard let ownedIdentity = self.ownedIdentity else {
            throw Self.makeError(message: "Could not extract required relationships")
        }
        guard let personNameComponents else {
            assertionFailure()
            throw Self.makeError(message: "Could not get person name components")
        }
        return Structure(objectPermanentID: self.objectPermanentID,
                         cryptoId: self.cryptoId,
                         fullDisplayName: self.fullDisplayName,
                         customOrFullDisplayName: self.customOrFullDisplayName,
                         displayPhotoURL: self.displayPhotoURL,
                         personNameComponents: personNameComponents,
                         ownedIdentity: try ownedIdentity.toStruct())
    }
}
