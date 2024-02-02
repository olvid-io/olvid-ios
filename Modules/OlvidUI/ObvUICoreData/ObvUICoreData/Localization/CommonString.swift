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
    
    private static let bundle = Bundle(for: LocalizableClassForObvUICoreDataBundle.self)
    
    public struct Word {
        public static let Choose = NSLocalizedString("Choose", bundle: CommonString.bundle, comment: "Choose word, capitalized")
        public static let Edited = NSLocalizedString("Edited", bundle: CommonString.bundle, comment: "Edited word, capitalized")
        public static let Forward = NSLocalizedString("Forward", bundle: CommonString.bundle, comment: "Forward word, capitalized")
        public static let Read = NSLocalizedString("Read", bundle: CommonString.bundle, comment: "Read word, capitalized")
        public static let Wiped = NSLocalizedString("Wiped", bundle: CommonString.bundle, comment: "Wiped word, capitalized")
        public static let You = NSLocalizedString("You", bundle: CommonString.bundle, comment: "You word, capitalized")
        public static let Close = NSLocalizedString("Close", bundle: CommonString.bundle, comment: "Close word, capitalized")
    }

    public struct Title {
    }
    
    public static let deletedContact = String(format: "A (now deleted) contact")
}

