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
import CoreData

extension NSManagedObjectContext {
    
    func fetchRequestStream<Object: NSManagedObject>(for fetchRequest: NSFetchRequest<Object>) -> FetchRequestStream<Object> {
        FetchRequestStream(fetchRequest: fetchRequest, within: self)
    }
    
}


class FetchRequestStream<Object: NSManagedObject>: NSObject, NSFetchedResultsControllerDelegate {

    private var frc: NSFetchedResultsController<Object>?
    let stream: AsyncStream<[Object]>
    private var continuation: AsyncStream<[Object]>.Continuation
    
    init(fetchRequest: NSFetchRequest<Object>, within context: NSManagedObjectContext) {
        self.frc = NSFetchedResultsController(fetchRequest: fetchRequest,
                                              managedObjectContext: context,
                                              sectionNameKeyPath: nil,
                                              cacheName: nil)
        
        let (stream, continuation) = AsyncStream.makeStream(of: [Object].self)
        self.stream = stream
        self.continuation = continuation
        super.init()
        
        frc?.delegate = self
        
        do {
            try frc?.performFetch()
            let newState = frc?.fetchedObjects ?? []
            self.continuation.yield(newState)
        } catch {
            self.continuation.finish()
        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<any NSFetchRequestResult>) {
        guard let frc, frc == controller else { return }
        let newState = frc.fetchedObjects ?? []
        continuation.yield(newState)
    }
}
