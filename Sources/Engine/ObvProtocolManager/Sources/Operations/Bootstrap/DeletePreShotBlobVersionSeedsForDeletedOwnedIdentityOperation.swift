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
import ObvTypes
import ObvMetaManager
import OlvidUtils


/// Deletes every `GroupV2PreShotBlobVersionSeedReceived` row associated with a deleted owned identity.
///
/// Triggered when the identity manager publishes `anOwnedIdentityWasDeleted` — the engine forwards the
/// event to the protocol manager so the protocol-side pre-shot store does not keep stranded seeds for a
/// profile that no longer exists on the identity side.
final class DeletePreShotBlobVersionSeedsForDeletedOwnedIdentityOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {

    private let ownedCryptoId: ObvCryptoId

    init(ownedCryptoId: ObvCryptoId) {
        self.ownedCryptoId = ownedCryptoId
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {

        do {
            try GroupV2PreShotBlobVersionSeedReceived.deleteAllPreShotBlobVersionSeedsReceived(
                ownedCryptoId: ownedCryptoId,
                within: obvContext.context)
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }

    }

}
