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
import OlvidUtils


/// Operation executed during bootstrap. It deletes `GroupV2PreShotBlobVersionSeedReceived` rows older than two months.
///
/// A pre-shot row records a `blobVersionSeed` an admin sent us out-of-band so we can decrypt the next blob
/// version without waiting for the in-band key distribution. Once consumed, a row is *not* proactively
/// deleted: a receiver may legitimately hold pre-shots for several future blob versions at the same time
/// (concurrent admin updates can pipeline), and we don't want to drop a still-useful seed. A TTL sweep is
/// the conservative cleanup mechanism — anything older than 60 days is safely past any plausible
/// blob-delivery window.
final class DeleteOldGroupV2PreShotBlobVersionSeedsOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {

    private static let ttl = TimeInterval(days: 60)

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {

        do {
            let cutoff = Date(timeIntervalSinceNow: -Self.ttl)
            try GroupV2PreShotBlobVersionSeedReceived.batchDeletePreShotBlobVersionSeedsReceived(insertedBefore: cutoff, within: obvContext.context)
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }

    }

}
