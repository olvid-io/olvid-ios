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


public extension Dictionary {
    
    /// Creates a new dictionary from `self`, applying `keyMapping` to each key of `self.keys` and applying `valueMapping` to each value of `self.values`.
    ///
    /// Note that both `keyMapping` and `valueMapping` may return `nil`. When they do, the original dictionary entry is omitted.
    ///
    /// Usage example:
    /// ```
    /// let dict: [String: Int] = ["Alice": 0, "Bob": 1]
    /// let newDict: [Data: Double] = .init(dict,
    ///                                     keyMapping: { $0.data(using: .utf8) },
    ///                                     valueMapping: { Double($0) })
    /// ```
    init<K,V>(_ originalDictionary: Dictionary<K,V>, keyMapping: (K) -> Key?, valueMapping: (V) -> Value?) {
        let newKeysAndValues: [(Key,Value)] = originalDictionary.compactMap { (key, value) in
            guard let newKey = keyMapping(key) else { assertionFailure(); return nil }
            guard let newValue = valueMapping(value) else { assertionFailure(); return nil }
            return (newKey, newValue)
        }
        self.init(newKeysAndValues) { (first, _) in assertionFailure(); return first }
    }

    /// Creates a new dictionary from `self`, applying `keyMapping` to each key of `self.keys` and applying `valueMapping` to each value of `self.values`.
    ///
    /// Note that both `keyMapping` and `valueMapping` may return `nil`. When they do, the original dictionary entry is omitted.
    ///
    /// Usage example:
    /// ```
    /// let dict: [String: Int] = ["Alice": 0, "Bob": 1]
    /// let newDict: [Data: Double] = .init(dict,
    ///                                     keyMapping: { $0.data(using: .utf8) },
    ///                                     valueMapping: { Double($0) })
    /// ```
    init<K,V>(_ originalDictionary: Dictionary<K,V>, keyMapping: (K) throws -> Key?, valueMapping: (V) throws -> Value?) rethrows {
        let newKeysAndValues: [(Key,Value)] =  try originalDictionary.compactMap { (key, value) in
            guard let newKey = try keyMapping(key) else { assertionFailure(); return nil }
            guard let newValue = try valueMapping(value) else { assertionFailure(); return nil }
            return (newKey, newValue)
        }
        self.init(newKeysAndValues) { (first, _) in assertionFailure(); return first }
    }

}
