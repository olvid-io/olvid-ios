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


extension KeyedEncodingContainer {
    
    public mutating func encodeIfPresentAndNotEmpty<T>(_ value: T?, forKey key: KeyedEncodingContainer<K>.Key) throws where T: Encodable, T: Collection {
        guard let value = value else { return }
        try encodeIfNotEmpty(value, forKey: key)
    }

    
    public mutating func encodeIfNotEmpty<T>(_ value: T, forKey key: KeyedEncodingContainer<K>.Key) throws where T: Encodable, T: Collection {
        guard !value.isEmpty else { return }
        try encode(value, forKey: key)
    }

    
}
