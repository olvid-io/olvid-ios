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

import CoreData
import Combine

extension NSManagedObjectContext {
    
    /// This method defined on an ``NSManagedObjectContext`` is a syntactic sugar that returns a ``NSFetchRequestPublisher`` for the context, defined by the ``NSFetchRequest`` on that object.
    func fetchRequestPublisher<Object: NSManagedObject>(for fetchRequest: NSFetchRequest<Object>) -> NSFetchRequestPublisher<Object> {
        NSFetchRequestPublisher(fetchRequest: fetchRequest, context: self)
    }
    
}


/// This publisher makes it easy to use Combine with a ``NSFetchedResultsController``.
///
/// Each value produced by this publisher is an array of ``NSManagedObject`` as specified by the ``NSFetchRequest``. The values are produced each time the internal ``NSFetchedResultsController`` is updated given the ``NSManagedObjectContext``.
struct NSFetchRequestPublisher<Object: NSManagedObject>: Publisher {
    typealias Output = [Object]
    typealias Failure = Error
    
    private let fetchRequest: NSFetchRequest<Object>
    private let context: NSManagedObjectContext
    
    fileprivate init(fetchRequest: NSFetchRequest<Object>, context: NSManagedObjectContext) {
        self.fetchRequest = fetchRequest
        self.context = context
    }
    
    /// Attaches the specified subscriber to this ``NSFetchRequestPublisher`.
    func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
        let inner = NSFetchRequestSubscription(downstream: subscriber, fetchRequest: fetchRequest, context: context)
        subscriber.receive(subscription: inner)
    }
    
}


extension NSFetchRequestPublisher {
    
    /// Controls  the flow of data from a ``NSFetchRequestPublisher`` to its subscribers.
    private final class NSFetchRequestSubscription<Downstream: Subscriber>: NSObject, Subscription, NSFetchedResultsControllerDelegate where Downstream.Input == [Object], Downstream.Failure == Error {
        
        private let downstream: Downstream
        private var frc: NSFetchedResultsController<Object>? // Nil iff `cancel()` was called
        private var lastSentState: [Object] = []
        private var demand: Subscribers.Demand = .none

        init(downstream: Downstream, fetchRequest: NSFetchRequest<Object>, context: NSManagedObjectContext) {
            self.downstream = downstream
            
            self.frc = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                  managedObjectContext: context,
                                                  sectionNameKeyPath: nil,
                                                  cacheName: nil)
            
            super.init()
            
            frc?.delegate = self
            
            do {
                try frc?.performFetch()
                let newState = frc?.fetchedObjects ?? []
                fullFill(with: newState)
            } catch {
                downstream.receive(completion: .failure(error))
            }
        }
         
        
        func request(_ demand: Subscribers.Demand) {
            self.demand += demand
            fullFill(with: lastSentState)
        }
        
        
        func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
            guard let frc, frc == controller else { return }
            let newState = frc.fetchedObjects ?? []
            fullFill(with: newState)
        }
        
        
        private func fullFill(with newState: [Object]) {
            lastSentState = newState
            if demand > 0 {
                let newDemand = downstream.receive(newState)
                
                demand += newDemand
                demand -= 1
            }
        }
        
        
        func cancel() {
            frc?.delegate = nil
            frc = nil
        }
    }
}


extension Publisher where Self.Failure == Never {
public func assignNoRetain<Root>(to keyPath: ReferenceWritableKeyPath<Root, Self.Output>, on object: Root) -> AnyCancellable where Root: AnyObject {
    sink { [weak object] (value) in
        object?[keyPath: keyPath] = value
    }
  }
}
