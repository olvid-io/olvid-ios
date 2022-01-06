/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import ObvCrypto

fileprivate let errorDomain = "MessengerMigrationV11ToV12"
fileprivate let debugPrintPrefix = "[\(errorDomain)][PersistedOneToOneDiscussionToPersistedOneToOneDiscussionMigrationPolicyV11ToV12]"


final class PersistedOneToOneDiscussionToPersistedOneToOneDiscussionMigrationPolicyV11ToV12: NSEntityMigrationPolicy {
    
    // This migration objective is to snitize discussions, making sure that sections are right.
    override func performCustomValidation(forMapping mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) performCustomValidation starts")
        defer {
            debugPrint("\(debugPrintPrefix) performCustomValidation ends")
        }

        try MigrationUtilsV11ToV12.sanityzeSectionsIdentifiersOfMessage(discussionEntityName: "PersistedOneToOneDiscussion", manager: manager, errorDomain: errorDomain)
        
    }
    
}
