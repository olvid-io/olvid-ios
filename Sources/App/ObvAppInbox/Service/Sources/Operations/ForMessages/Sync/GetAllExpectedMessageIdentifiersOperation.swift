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
import ObvAppTypes


final class GetAllExpectedMessageIdentifiersOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private(set) var allExpectedMessageIdentifiers: [ObvMessageAppIdentifier]?
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        do {
            let expectingSentInOneToOne = try MessageIdentifierForLaterExpectingSentMessageInOneToOneDiscussion.getAllExpectedMessageAppIdentifier(within: obvContext.context)
            let expectingReceivedInOneToOne = try MessageIdentifierForLaterExpectingReceivedMessageInOneToOneDiscussion.getAllExpectedMessageAppIdentifier(within: obvContext.context)
            let expectingSentInGroupV1 = try MessageIdentifierForLaterExpectingSentMessageInGroupV1Discussion.getAllExpectedMessageAppIdentifier(within: obvContext.context)
            let expectingReceivedInGroupV1 = try MessageIdentifierForLaterExpectingReceivedMessageInGroupV1Discussion.getAllExpectedMessageAppIdentifier(within: obvContext.context)
            let expectingSentInGroupV2 = try MessageIdentifierForLaterExpectingSentMessageInGroupV2Discussion.getAllExpectedMessageAppIdentifier(within: obvContext.context)
            let expectingReceivedInGroupV2 = try MessageIdentifierForLaterExpectingReceivedMessageInGroupV2Discussion.getAllExpectedMessageAppIdentifier(within: obvContext.context)
            allExpectedMessageIdentifiers = expectingSentInOneToOne + expectingReceivedInOneToOne + expectingSentInGroupV1 + expectingReceivedInGroupV1 + expectingSentInGroupV2 + expectingReceivedInGroupV2
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
    }
    
}
