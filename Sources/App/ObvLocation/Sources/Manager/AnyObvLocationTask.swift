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

enum ObvLocationTaskKind { }

protocol AnyObvLocationTask: Actor {
    
    var cancellable: ObvLocationCancellableTask? { get set }
    var uuid: UUID { get }
    var taskType: ObjectIdentifier { get }
    
    func receivedLocationManagerEvent(_ event: ObvLocationManagerEvent)
    func didCancel()
    func willStart()
    
}

extension AnyObvLocationTask {
    
    var taskType: ObjectIdentifier {
        ObjectIdentifier(Self.self)
    }
    
    func setCancellable(to cancellable: ObvLocationCancellableTask?) {
        self.cancellable = cancellable
    }
    
    func didCancel() { }
    func willStart() { }
    
}


protocol ObvLocationCancellableTask: Actor {
    
    // Mark this function async to ensure there is no concurrency access to it.
    func cancel(task: any AnyObvLocationTask) async
    
}
