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
import OSLog
import OlvidUtils
import ObvUICoreData
import ObvTypes


/// Collects the `.read` `ObvReturnReceiptToSend` values for a set of `PersistedMessageReceived`
/// objects, mutating each row by flipping its `isReadReceiptSentOrNotToBeSent` flag (the producer
/// is idempotent on the flag). Used after a batch "mark discussion as read" — those batch updates
/// don't fire `didSave`, so the receipt producer must be invoked explicitly here. The composed
/// operation saves the context, so the flag flips persist and the receipts can't be re-emitted
/// on a later pass.
///
/// The caller queues this operation on the coordinator queue and then forwards
/// ``readReceiptsToSend`` to the engine.
final class CollectReadReceiptsToSendForReceivedMessagesOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {

    private let receivedMessageObjectIDs: [TypeSafeManagedObjectID<PersistedMessageReceived>]

    init(receivedMessageObjectIDs: [TypeSafeManagedObjectID<PersistedMessageReceived>]) {
        self.receivedMessageObjectIDs = receivedMessageObjectIDs
        super.init()
    }

    private(set) var readReceiptsToSend: [ObvReturnReceiptToSend] = []

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {

        do {
            for typedObjectID in receivedMessageObjectIDs {
                guard let message = try PersistedMessageReceived.get(with: typedObjectID, within: obvContext.context) else { continue }
                if let receipt = message.produceReadReceiptToSendIfAppropriate() {
                    readReceiptsToSend.append(receipt)
                }
            }
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }

    }

}
