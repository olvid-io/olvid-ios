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


extension DisplayedContactGroup {
    
    var circledInitialsConfiguration: CircledInitialsConfiguration {
        if let group = groupV1 {
            assert(groupV2 == nil)
            return group.circledInitialsConfiguration
        } else if let group = groupV2 {
            assert(groupV1 == nil)
            return group.circledInitialsConfiguration
        } else {
            // Happens when the group gets deleted
            return CircledInitialsConfiguration.icon(.person3Fill)
        }
    }
    
    
    static func getFetchRequestWithNoResult() -> NSFetchRequest<DisplayedContactGroup> {
        let request: NSFetchRequest<DisplayedContactGroup> = DisplayedContactGroup.fetchRequest()
        request.predicate = NSPredicate(value: false)
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.normalizedSortKey.rawValue, ascending: true)]
        request.fetchLimit = 1
        return request
    }

    
    static func getFetchRequestForAllDisplayedContactGroup(ownedIdentity: ObvCryptoId, contactIdentity: ObvCryptoId) -> NSFetchRequest<DisplayedContactGroup> {
        let predicates = [
            Predicate.withOwnedIdentity(ownedIdentity),
            Predicate.withContactIdentity(contactIdentity),
        ]
        let request: NSFetchRequest<DisplayedContactGroup> = DisplayedContactGroup.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.normalizedSortKey.rawValue, ascending: true)]
        return request
    }

}
