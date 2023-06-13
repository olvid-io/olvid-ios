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
import CoreData.NSManagedObjectContext

public extension NSManagedObjectContext {
    
    /// Helper method that wraps around `NSManagedObjectContext.performAndWait(_:)` if we're on iOS 15+
    func obvPerformAndWait<T>(_ block: () -> T) -> T {
        if #available(iOS 15, *) {
            return performAndWait(block)
        } else {
            var result: T!

            performAndWait { () -> Void in
                result = block()
            }

            return result
        }
    }

    /// Helper method that wraps around `NSManagedObjectContext.performAndWait(_:)` if we're on iOS 15+
    func obvPerformAndWait<T>(_ block: () throws -> T) throws -> T {
        if #available(iOS 15, *) {
            return try performAndWait(block)
        } else {
            var result: Result<T, Error>!

            performAndWait { () -> Void in
                result = .init(catching: block)
            }

            return try result.get()
        }
    }
}
