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
import os.log
import ObvEngine
import MobileCoreServices


struct FyleMetadata: Codable {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: FyleMetadata.self))
    
    let fileName: String
    let sha256: Data
    let uti: String

    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case sha256 = "sha256"
        case type = "type" // MIME type
    }
    
    init(fileName: String, sha256: Data, uti: String) {
        self.fileName = fileName
        self.sha256 = sha256
        self.uti = uti
    }
    
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let mimeType = try values.decode(String.self, forKey: .type)
        self.fileName = try values.decode(String.self, forKey: .fileName)
        // The MIME type has precedence over the extension for determining the UTI
        if let utiFromMIMEType = ObvUTIUtils.utiOfMIMEType(mimeType) {
            self.uti = utiFromMIMEType
        } else if let utiFromExtension = ObvUTIUtils.utiOfFile(withExtension: (self.fileName as NSString).pathExtension) {
            self.uti = utiFromExtension
        } else {
            self.uti = "public.item"
        }
        self.sha256 = try values.decode(Data.self, forKey: .sha256)
    }
    
    func encode(to encoder: Encoder) throws {
        let mimeType: String
        if let _mimeType = ObvUTIUtils.preferredTagWithClass(inUTI: self.uti, inTagClass: .MIMEType) {
            mimeType = _mimeType
        } else {
            os_log("Could not find appropriate MIME type for uti %{public}@. We fallback on Data", log: log, type: .error, self.uti)
            mimeType = ObvUTIUtils.preferredTagWithClass(inUTI: String(kUTTypeData), inTagClass: .MIMEType) ?? "application/octet-stream"
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mimeType, forKey: .type)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(sha256, forKey: .sha256)
    }
    
    func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    
    static func decode(_ data: Data) throws -> FyleMetadata {
        let decoder = JSONDecoder()
        return try decoder.decode(FyleMetadata.self, from: data)
    }
    
}
