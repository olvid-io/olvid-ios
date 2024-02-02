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
import ObvSettings


extension ContactsSortOrder {
    
    func computeNormalizedSortAndSearchKey(customDisplayName: String?, firstName: String?, lastName: String?, position: String?, company: String?) -> String {

        var allComponents: [String?] = [customDisplayName]
        switch self {
        case .byFirstName:
            allComponents += [firstName, lastName]
        case .byLastName:
            allComponents += [lastName, firstName]
        }
        allComponents += [position, company]

        let components = allComponents.compactMap { $0 }
        return components.map({
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
        }).joined(separator: "_")
    }
    
}
