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
import ObvTypes
import os.log


// MARK: - Thread safe structure

extension PersistedObvOwnedIdentity {
    
    public struct Structure {
        
        public let objectPermanentID: ObvManagedObjectPermanentID<PersistedObvOwnedIdentity>
        public let cryptoId: ObvCryptoId
        public let fullDisplayName: String
        public let identityCoreDetails: ObvIdentityCoreDetails
        public let photoURL: URL?
        public let isHidden: Bool
        
        private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedObvOwnedIdentity.Structure")
        
    }
    
    public func toStruct() throws -> Structure {
        return Structure(objectPermanentID: self.objectPermanentID,
                         cryptoId: self.cryptoId,
                         fullDisplayName: self.fullDisplayName,
                         identityCoreDetails: self.identityCoreDetails,
                         photoURL: self.photoURL,
                         isHidden: self.isHidden)
    }
    
}


