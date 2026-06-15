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

public struct JsonAttachment: Sendable {
    let sha256: Data
    let number: Int
    let size: Int
    let mimeType: String
    let filename: String
    
    public init(sha256: Data,
                number: Int,
                size: Int,
                mimeType: String,
                filename: String) {
        self.sha256 = sha256
        self.number = number
        self.size = size
        self.mimeType = mimeType
        self.filename = filename
    }
    
}


extension JsonAttachment: Codable {
    
    enum CodingKeys: String, CodingKey {
        case sha256 = "sha256"
        case number = "number"
        case size = "size"
        case mimeType = "mimeType"
        case filename = "filename"
    }
    
}
