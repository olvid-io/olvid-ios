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
import CoreData
import ObvHistoryTransfer
import ObvTypes
import ObvAppTypes
import ObvUICoreData
import ObvSettings


/// This data source is used on the source device during a zip export, in order to extract the display name of each contact referenced in the zip.
final class ZipTransferTransportDelegateAppDataSource {
    
    private let backgroundContext: NSManagedObjectContext
    
    init(backgroundContext: NSManagedObjectContext) {
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.backgroundContext = backgroundContext
    }
        
}


extension ZipTransferTransportDelegateAppDataSource: ZipTransferTransportDelegateDataSource {
    
    func getDisplayNameOfContacts(ownedCryptoId: ObvTypes.ObvCryptoId, contactCryptoIds: Set<ObvTypes.ObvCryptoId>) async throws -> [ObvTypes.ObvCryptoId : String] {
        let backgroundContext = self.backgroundContext
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ObvTypes.ObvCryptoId : String], any Error>) in
            self.backgroundContext.perform {
                do {
                    var results = try PersistedObvContactIdentity.getContactDisplayNames(ownedCryptoId: ownedCryptoId, contactCryptoIds: contactCryptoIds, within: backgroundContext)
                    let ownedDisplayName: String? = try PersistedObvOwnedIdentity.getFullDisplayNameAndIsKeycloakManaged(ownedCryptoId: ownedCryptoId, within: backgroundContext).fullDisplayName
                    results[ownedCryptoId] = ownedDisplayName
                    return continuation.resume(returning: results)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
}
