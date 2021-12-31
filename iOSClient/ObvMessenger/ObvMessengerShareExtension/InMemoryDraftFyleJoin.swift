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
import CoreData

final class InMemoryDraftFyleJoin: DraftFyleJoin {
    
    var fyle: Fyle?
    let fileName: String
    let uti: String
    let index: Int
    let fyleObjectID: NSManagedObjectID
    
    init(fyle: Fyle, fileName: String, uti: String, index: Int) {
        assert(fyle.managedObjectContext == ObvStack.shared.viewContext)
        assert(Thread.current.isMainThread)
        self.fyle = fyle
        self.fyleObjectID = fyle.objectID
        self.fileName = fileName
        self.uti = uti
        self.index = index
    }
    
    /// Expected to be executed on the context thread passed as a parameter
    func changeContext(to context: NSManagedObjectContext) {
        guard let _fyle = try? Fyle.get(objectID: fyleObjectID, within: context) else { assertionFailure(); return }
        self.fyle = _fyle
    }
}
