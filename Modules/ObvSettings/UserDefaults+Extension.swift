/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

public extension UserDefaults {
    
    /// Returns the integer value associated with the specified key.
    ///
    /// - Parameter defaultName: A key in the current user‘s defaults database.
    /// - Returns: The Integer value associated with the specified key. If the specified key doesn‘t exist, this method returns `nil`.
    func integerOrNil(forKey defaultName: String) -> Int? {
        guard object(forKey: defaultName) != nil else { return nil }
        return integer(forKey: defaultName)
    }
    
    /// Returns the Boolean value associated with the specified key.
    ///
    /// - Parameter defaultName: A key in the current user‘s defaults database.
    /// - Returns: The Boolean value associated with the specified key. If the specified key doesn‘t exist, this method returns `nil`.
    func boolOrNil(forKey defaultName: String) -> Bool? {
        guard object(forKey: defaultName) != nil else { return nil }
        return bool(forKey: defaultName)
    }


    /// Returns the Double value associated with the specified key.
    ///
    /// - Parameter defaultName: A key in the current user‘s defaults database.
    /// - Returns: The Double value associated with the specified key. If the specified key doesn‘t exist, this method returns `nil`.
    func doubleOrNil(forKey defaultName: String) -> Double? {
        guard object(forKey: defaultName) != nil else { return nil }
        return double(forKey: defaultName)
    }


    /// Returns the Date value associated with the specified key.
    ///
    /// - Parameter defaultName: A key in the current user‘s defaults database.
    /// - Returns: The Date value associated with the specified key. If the specified key doesn‘t exist, this method returns `nil`.
    func dateOrNil(forKey defaultName: String) -> Date? {
        guard object(forKey: defaultName) != nil else { return nil }
        return object(forKey: defaultName) as? Date
    }

    /// Returns the String value associated with the specified key.
    ///
    /// - Parameter defaultName: A key in the current user‘s defaults database.
    /// - Returns: The String value associated with the specified key. If the specified key doesn‘t exist, this method returns `nil`.
    func stringOrNil(forKey defaultName: String) -> String? {
        guard object(forKey: defaultName) != nil else { return nil }
        return string(forKey: defaultName)
    }
}
