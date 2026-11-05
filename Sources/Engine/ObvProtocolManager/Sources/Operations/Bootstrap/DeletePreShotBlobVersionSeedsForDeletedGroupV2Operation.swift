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


/// Deletes every `GroupV2PreShotBlobVersionSeedReceived` row associated with a `(ownedCryptoId, groupIdentifier)`.
///
/// Triggered when the identity manager publishes `ObvIdentityNotificationNew.groupV2WasDeleted` — the
/// engine forwards the event to the protocol manager so the protocol-side pre-shot store does not keep
/// stranded seeds for a group that no longer exists on the identity side.
final class DeletePreShotBlobVersionSeedsForDeletedGroupV2Operation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {

    private let ownedCryptoId: ObvCryptoId
    private let groupIdentifier: GroupV2.Identifier

    init(ownedCryptoId: ObvCryptoId, groupIdentifier: GroupV2.Identifier) {
        self.ownedCryptoId = ownedCryptoId
        self.groupIdentifier = groupIdentifier
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {

        do {
            try GroupV2PreShotBlobVersionSeedReceived.deleteAllPreShotBlobVersionSeedsReceived(
                ownedCryptoId: ownedCryptoId,
                groupIdentifier: groupIdentifier,
                within: obvContext.context)
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }

    }

}
