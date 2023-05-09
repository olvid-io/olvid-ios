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
  

import OlvidUtils
import UIKit


extension NSDiffableDataSourceSnapshot {
    
    mutating func deleteItems(inSection section: SectionIdentifierType) {
        guard let indexOfDeletedSection = indexOfSection(section) else { return }
        if indexOfDeletedSection == numberOfSections-1 {
            // The deleted section is the last. Easy case.
            deleteSections([section])
            appendSections([section])
        } else {
            // Find the section 'S' after the deleted section, delete the section, and insert a new one just before 'S'
            guard let sectionAfterSectionToDelete = sectionIdentifiers[safe: (indexOfDeletedSection+1)] else { assertionFailure(); return }
            deleteSections([section])
            insertSections([section], beforeSection: sectionAfterSectionToDelete)
        }
    }

    
}
