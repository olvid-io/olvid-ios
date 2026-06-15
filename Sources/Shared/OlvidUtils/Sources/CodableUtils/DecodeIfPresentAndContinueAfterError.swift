/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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


/// A concrete container that provides a view into a decoder's storage, making
/// the encoded properties of a decodable type accessible by keys.
extension KeyedDecodingContainer {
    
    /// Decodes an array of `T` for the given key, silently skipping any elements that fail to decode.
    ///
    /// This is a fault-tolerant alternative to `decodeIfPresent(_:forKey:)` for array values.
    /// Where the standard method would throw on the first malformed element and abort decoding entirely,
    /// this method recovers and continues, collecting only the elements that decoded successfully.
    ///
    /// A typical use case is a message that carries an array of user mentions: a corrupted or
    /// unrecognised mention should not prevent the message itself from being received.
    ///
    /// - Parameters:
    ///   - type: The array type to decode (`[T].Type`).
    ///   - key: The key that the decoded array is associated with.
    /// - Returns: An array of successfully decoded elements, an empty array if the key is present
    ///   but every element failed to decode, or `nil` if the key is absent altogether.
    ///
    /// - Note: The method never throws. Errors encountered while decoding individual elements are
    ///   swallowed silently. Only the key lookup itself can fail, in which case `nil` is returned.
    ///
    /// - Important: Skipping an invalid element relies on `SkipDecodable`, a minimal `Decodable`
    ///   whose `init(from:)` always succeeds without reading anything. This advances the
    ///   `UnkeyedDecodingContainer`'s internal index past the bad element so iteration can continue.
    public func decodeIfPresentAndContinueAfterError<T>(_ type: [T].Type, forKey key: KeyedDecodingContainer<K>.Key) -> [T]? where T : Decodable {
        guard var container = try? nestedUnkeyedContainer(forKey: key) else { return nil }
        var validObjects: [T] = []
        while !container.isAtEnd {
            if let object = try? container.decode(T.self) {
                validObjects.append(object)
            } else {
                // Skip invalid mention by decoding it as a generic decodable to advance the container
                _ = try? container.decode(SkipDecodable.self)
            }
        }
        return validObjects
    }

}

private struct SkipDecodable: Decodable {
    init(from decoder: Decoder) throws {}
}
