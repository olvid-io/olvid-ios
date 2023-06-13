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
import ObvTypes

public enum DisplayNameStyle {

    case firstNameThenLastName
    case positionAtCompany
    case full
    case short
}

public extension ObvIdentityCoreDetails {

    func getDisplayNameWithStyle(_ style: DisplayNameStyle) -> String {
        switch style {
        case .firstNameThenLastName:
            let _firstName = firstName ?? ""
            let _lastName = lastName ?? ""
            return [_firstName, _lastName].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        case .positionAtCompany:
            return positionAtCompany()

        case .full:
            let firstNameThenLastName = getDisplayNameWithStyle(.firstNameThenLastName)
            if let positionAtCompany = getDisplayNameWithStyle(.positionAtCompany).mapToNilIfZeroLength() {
                return [firstNameThenLastName, "(\(positionAtCompany))"].joined(separator: " ")
            } else {
                return firstNameThenLastName
            }

        case .short:
            return firstName ?? lastName ?? ""
        }
    }
}
