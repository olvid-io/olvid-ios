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

import Foundation

public struct CommonString {
    
    public struct Word {
        public static let Choose = NSLocalizedString("Choose", comment: "Choose word, capitalized")
        public static let Edited = NSLocalizedString("Edited", comment: "Edited word, capitalized")
        public static let Forward = NSLocalizedString("Forward", comment: "Forward word, capitalized")
        public static let Read = NSLocalizedString("Read", comment: "Read word, capitalized")
        public static let Wiped = NSLocalizedString("Wiped", comment: "Wiped word, capitalized")
    }
    
    public struct Title {
    }
    
    public static let deletedContact = NSLocalizedString("A (now deleted) contact", comment: "Can serve as a name in the sentence %@ accepted to join this group")
}

