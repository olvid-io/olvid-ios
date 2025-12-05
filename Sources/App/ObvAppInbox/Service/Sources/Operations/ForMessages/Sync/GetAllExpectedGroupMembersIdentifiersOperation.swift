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


final class GetAllExpectedGroupMembersIdentifiersOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private(set) var allExpectedDiscussionAndContactIdentifiers: [ObvGroupMemberIdentifier]?
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        do {
            let expectingGroupV1 = try MessageIdentifierForLaterExpectingContactInGroupV1.getAllExpectedMemberIdentifiers(within: obvContext.context)
            let expectingGroupV2 = try MessageIdentifierForLaterExpectingContactInGroupV2.getAllExpectedMemberIdentifiers(within: obvContext.context)
            allExpectedDiscussionAndContactIdentifiers = expectingGroupV1 + expectingGroupV2
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
    }
    
}
