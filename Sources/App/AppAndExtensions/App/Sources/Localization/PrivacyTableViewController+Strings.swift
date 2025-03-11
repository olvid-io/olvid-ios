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

        static let noGracePeriodExplanation = NSLocalizedString("NO_GRACE_PERIOD_EXPLANATION", comment: "")

        static let gracePeriodExplanation = { (duration: String) in
            return String.localizedStringWithFormat(NSLocalizedString("GRACE_PERIOD_EXPLANATION_%@", comment: ""), duration)
        }

        static let lockoutCleanEphemeralTitle = NSLocalizedString("LOCKOUT_CLEAN_EPHEMERAL_TITLE", comment: "")

        static let lockoutCleanEphemeralExplanation = NSLocalizedString("LOCKOUT_CLEAN_EPHEMERAL_EXPLANATION", comment: "")
    }
    
}
