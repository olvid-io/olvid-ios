/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
@preconcurrency import CoreData


/// WARNING: Not tested yet
actor ObvContextualActor {
    
    private let contextualExecutor: ObvContextualExecutor
    
    init(readOnlyBackgroundContext: NSManagedObjectContext) {
        self.contextualExecutor = ObvContextualExecutor(readOnlyBackgroundContext: readOnlyBackgroundContext)
    }
    
    nonisolated var unownedExecutor: UnownedSerialExecutor {
      self.contextualExecutor.asUnownedSerialExecutor()
    }

}


private final class ObvContextualExecutor: SerialExecutor {
    
    let readOnlyBackgroundContext: NSManagedObjectContext

    init(readOnlyBackgroundContext: NSManagedObjectContext) {
        self.readOnlyBackgroundContext = readOnlyBackgroundContext
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }

    func enqueue(_ job: UnownedJob) {
        let unownedExecutor = asUnownedSerialExecutor()
        readOnlyBackgroundContext.perform {
            job.runSynchronously(on: unownedExecutor)
        }
    }
    
}
