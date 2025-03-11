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

/// Since this class has an internal synchronization mechanism, we can mark it as `@unchecked Sendable`
final public class RunningLogError: Error, LocalizedError, @unchecked Sendable {
    
    private let internalQueue = DispatchQueue(label: "RunningLogError internal queue")
    
    struct Event {
        let date = Date()
        let message: String
        
        init(message: String) {
            self.message = message
        }
    }

    private var events = [Event]()
    
    public init() {}
    
    public func addEvent(message: String) {
        internalQueue.async { [weak self] in
            let event = Event(message: message)
            self?.events.append(event)
        }
    }
    
    public func removeAllEvents() {
        internalQueue.async { [weak self] in
            self?.events.removeAll()
        }
    }

    public var errorDescription: String? {
        var result: String? = nil
        internalQueue.sync {
            result = events.map({ "\($0.date.description) - \($0.message)" }).joined(separator: "\n")
        }
        return result
    }
}
