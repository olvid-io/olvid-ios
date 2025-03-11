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
import CoreLocation

/// This task is used to link the object which manage the underlying events from `CLLocationManagerDelegate`.
actor ObvLocationTask: ObvLocationCancellableTask {
    
    // MARK: - Private Properties
    
    private var tasks = [(taskUUID: UUID, taskType: ObjectIdentifier, task:AnyObvLocationTask)]()
    private weak var locationManager: ObvLocationManager?
    
    func setObvLocationManager(to locationManager: ObvLocationManager) {
        self.locationManager = locationManager
    }

    // MARK: - Internal function
    
    /// Add a new task to the queued operations to bridge.
    ///
    /// - Parameter task: task to add.
    func add(task: AnyObvLocationTask) async {
        await task.setCancellable(to: self)
        let taskUUID = await task.uuid
        let taskType = await task.taskType
        tasks.append((taskUUID, taskType, task))
        await task.willStart()
    }
    
    /// Cancel the execution of a task.
    ///
    /// - Parameter task: task to cancel.
    func cancel(task: AnyObvLocationTask) async {
        await cancel(taskUUID: task.uuid)
    }
    
    /// Cancel the execution of a task with a given unique identifier.
    ///
    /// - Parameter uuid: unique identifier of the task to remove
    private func cancel(taskUUID uuid: UUID) {
        tasks.removeAll { (taskUUID, _, task) in
            if taskUUID == uuid {
                Task { await task.didCancel() }
                return true
            } else {
                return false
            }
        }
    }
    
    /// Cancel the task of the given class and optional validated condition.
    ///
    /// - Parameters:
    ///   - type: type of `AnyTask` conform task to remove.
    ///   - condition: optional condition to verify in order to cancel.
    func cancel(tasksTypes type: AnyObvLocationTask.Type, condition: ((AnyObvLocationTask) -> Bool)? = nil) {
        let typeToRemove = ObjectIdentifier(type)
        tasks.removeAll { (_, taskType, task) in
            let isCorrectType = (taskType == typeToRemove)
            let isConditionValid = (condition == nil ? true : condition!(task))
            let shouldRemove = (isCorrectType && isConditionValid)
            if shouldRemove {
                Task { await task.didCancel() }
            }
            return shouldRemove
        }
    }
    
    /// Dispatch the event to the tasks.
    ///
    /// - Parameter event: event to dispatch.
    func dispatchEvent(_ event: ObvLocationManagerEvent) async {
        
        // store cached location first, then dispatch event to all tasks.
        if case .receiveNewLocations(let locations) = event {
            await locationManager?.setLastLocation(to: locations.last)
        }

        for (_, _, task) in tasks {
            await task.receivedLocationManagerEvent(event)
        }
    }
    
}
