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

extension BadConfigurationViewController {
    
    struct Strings {
        
        static let title = NSLocalizedString("Misconfiguration", comment: "View Controller title")
        
        static let problemTitle = NSLocalizedString("Problem", comment: "Title")
        static let solutionTitle = NSLocalizedString("Solution", comment: "Title")

        struct badBackgroundRefreshStatus {
            static let title = NSLocalizedString("Background App Refresh is disabled", comment: "Title")
            static let explanation = NSLocalizedString("Olvid requires the Background App Refresh to be turned on. Unfortunately it appears to be off. If you wish to use Olvid, please turn it back on.\n\nThe reason why this is required lies in the fact that Olvid regularly executes complex, multipass, cryptographic protocols in order to achieve a security level no other app can compete with. These protocols happen in the background and could not work if you had to manually launch Olvid each time a cryptographic computation has to be performed.", comment: "Long explanation")
            static let buttonTitle = NSLocalizedString("Open Settings", comment: "Button title")
            static let solution = NSLocalizedString("Please open settings and enable Background App Refresh. Hint: If the button is grayed out, you may have turned off the general setting which can be found within:\n\n Settings > General > Background App Refresh", comment: "Long solution")
        }
        
    }
    
}
