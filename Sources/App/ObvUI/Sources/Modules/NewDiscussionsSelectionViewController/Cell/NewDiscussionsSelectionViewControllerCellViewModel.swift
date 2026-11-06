/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvUICoreData
import ObvUIObvCircledInitials


extension NewDiscussionsSelectionViewController.Cell {
 
    public struct ViewModel: Hashable, Equatable {
        let circledInitialsConfig: CircledInitialsConfiguration?
        let title: String
        let isArchived: Bool
    }

}


extension NewDiscussionsSelectionViewController.Cell.ViewModel {
    
    static func createFromPersistedDiscussion(with discussionId: TypeSafeManagedObjectID<PersistedDiscussion>, within viewContext: NSManagedObjectContext) -> Self? {
        guard let discussion = try? PersistedDiscussion.get(objectID: discussionId.objectID, within: viewContext) else { assertionFailure(); return nil }
        return Self.init(circledInitialsConfig: discussion.circledInitialsConfiguration,
                         title: discussion.title,
                         isArchived: discussion.isArchived)        
    }
    
}
