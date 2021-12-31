/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

extension SingleContactViewController {
    
    struct Strings {
        
        static let olvidCardTrusted = NSLocalizedString("Olvid Card - Trusted", comment: "Type title of a owned Olvid card")
        static let olvidCardPublished = NSLocalizedString("Olvid Card - New", comment: "Type title of a owned Olvid card")
        static let olvidCard = NSLocalizedString("Olvid Card", comment: "Type title of a owned Olvid card")
        
        static let contactsTVCTitle = { (contactIdentityDisplayName: String) in
            String.localizedStringWithFormat(NSLocalizedString("Introduce %@ to...", comment: "Title of the table listing all identities but the one to introduce"), contactIdentityDisplayName)
        }
                
        struct AlertRestartChannelEstablishment {
            static let title = NSLocalizedString("Restart channel establishment", comment: "Alert title")
            static let message = NSLocalizedString("Do you really wish to restart the channel establishment?", comment: "Alert message")
        }
        
        struct OlvidCardChooser {
            static let title = NSLocalizedString("New contact details", comment: "Title")
            static let body = NSLocalizedString("Your contact published a new version of their Olvid card. Both the old and new versions are shown below.\n\nClick to update yout contact's informations with the new version.", comment: "Body")
        }
        
        static let buttonRestartChannelTitle = NSLocalizedString("Restart Channel Establishment", comment: "button title")
        
        static let advancedShowContactInfosButtonTitle = NSLocalizedString("Show detailed infos", comment: "Button title")
    }
    
}
