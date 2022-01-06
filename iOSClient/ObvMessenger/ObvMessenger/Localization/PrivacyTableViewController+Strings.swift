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


extension PrivacyTableViewController {
    
    struct Strings {
        
        static let laEvaluatePolicyReason = NSLocalizedString("Authenticate", comment: "")
        
        struct loginWith {
            static let passcode = NSLocalizedString("Log in with passcode", comment: "Cell label")
            static let touchID = NSLocalizedString("Log in with Touch ID", comment: "Cell label")
            static let faceID = NSLocalizedString("Log in with Face ID", comment: "Cell label")
        }
        
        struct explanationLoginWith {
            static let passcode = NSLocalizedString("Explanation for Log in with passcode", comment: "Cell label")
            static let touchID = NSLocalizedString("Explanation for Log in with Touch ID", comment: "Cell label")
            static let faceID = NSLocalizedString("Explanation for Log in with Face ID", comment: "Cell label")
        }
                
        struct notificationContentPrivacyStyle {
            static let title = NSLocalizedString("Hide notifications content", comment: "Cell label")
            static let shortTitle = NSLocalizedString("Hide notifications", comment: "Cell label")
            struct explanation {
                static let whenNo = NSLocalizedString("Notifications will preview new messages and new invitations content.", comment: "Cell label")
                static let whenPartially = NSLocalizedString("Notifications will not preview any message content nor any invitation content. Instead, they will display the number of new messages as well as the number of new invitations.", comment: "Cell label")
                static let whenCompletely = NSLocalizedString("Notifications will not provide any information about messages nor invitations. A minimal static notification will show to indicate that Olvid requires your attention.", comment: "Cell label")
            }
        }
        
        static let screenLock = NSLocalizedString("Screen Lock", comment: "")
        
        static let changingSettingRequiresAuthentication = NSLocalizedString("Please authenticate in order to change this setting.", comment: "Cell label")
        
        struct passcodeNotSetAlert {
            static let message = NSLocalizedString("No passcode set on this iPhone.", comment: "Alert title")
        }
    }
    
}
