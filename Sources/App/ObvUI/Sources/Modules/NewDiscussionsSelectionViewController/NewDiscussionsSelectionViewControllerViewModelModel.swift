/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import CoreData
import ObvTypes
import ObvUICoreData
import ObvSystemIcon

@available(iOS 16.0, *)
extension NewDiscussionsSelectionViewController {
    
    public struct ViewModel {
        
        let viewContext: NSManagedObjectContext
        let preselectedDiscussions: [TypeSafeManagedObjectID<PersistedDiscussion>]
        let ownedCryptoId: ObvCryptoId
        let attachSearchControllerToParent: Bool
        let buttonTitle: String
        let buttonSystemIcon: SystemIcon?
        let restrictToActiveDiscussions: Bool
                
        public init(viewContext: NSManagedObjectContext, preselectedDiscussions: [TypeSafeManagedObjectID<PersistedDiscussion>], ownedCryptoId: ObvCryptoId, restrictToActiveDiscussions: Bool, attachSearchControllerToParent: Bool, buttonTitle: String, buttonSystemIcon: SystemIcon? = nil) {
            self.viewContext = viewContext
            self.preselectedDiscussions = preselectedDiscussions
            self.ownedCryptoId = ownedCryptoId
            self.attachSearchControllerToParent = attachSearchControllerToParent
            self.buttonTitle = buttonTitle
            self.buttonSystemIcon = buttonSystemIcon
            self.restrictToActiveDiscussions = restrictToActiveDiscussions
        }
        
    }
    
}
