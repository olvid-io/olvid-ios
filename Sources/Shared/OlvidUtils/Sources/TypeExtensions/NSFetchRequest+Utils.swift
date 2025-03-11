/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
  

import CoreData
import Foundation


public extension NSFetchRequest {
    @objc func add(predicate: NSPredicate) -> NSFetchRequest? {
        guard let currentPredicate = self.predicate as? NSCompoundPredicate else { assertionFailure(); return nil; }
        var subpredicates = currentPredicate.subpredicates.compactMap({ $0 as? NSPredicate })
        guard subpredicates.count == currentPredicate.subpredicates.count else { assertionFailure(); return nil; }
        subpredicates.append(predicate)
        self.predicate = NSCompoundPredicate(type: currentPredicate.compoundPredicateType, subpredicates: subpredicates)
        return self
    }
    
    @objc func replace(sortDescriptor: NSSortDescriptor) -> NSFetchRequest? {
        sortDescriptors = [sortDescriptor]
        return self
    }
}
