/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvTypes
import ObvAppInboxDatabase


final class DeleteMessageIdentifiersForLaterOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    enum Input {
        case messageId(ObvMessageIdentifier)
        /// A page of identifiers. This is not the same thing as `ownedCryptoId` with a filter: that case takes every row of the
        /// profile, whereas this takes only the rows named.
        case messageIds([ObvMessageIdentifier])
        case ownedCryptoId(ObvCryptoId)
    }
    
    private let input: Input

    /// How many rows were deleted, for the `messageIds` input alone; nil for the other two, which no caller counts. A page that
    /// deleted nothing is a page the caller would be handed again, which is why that one input reports it.
    private(set) var numberOfRowsDeleted: Int?

    init(input: Input) {
        self.input = input
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        do {
            switch input {
            case .messageId(let messageId):
                try MessageIdentifierForLater.batchDeleteMessageIdentifierForLater(messageId: messageId, within: obvContext.context)
            case .messageIds(let messageIds):
                numberOfRowsDeleted = try MessageIdentifierForLater.batchDeleteMessageIdentifierForLater(messageIds: messageIds, within: obvContext.context)
            case .ownedCryptoId(let ownedCryptoId):
                try MessageIdentifierForLater.batchDeleteMessageIdentifierForLater(ownedCryptoId: ownedCryptoId, within: obvContext.context)
            }
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
    }
    
}
