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
import UniformTypeIdentifiers
import ObvSettings


public struct FyleMetadata: Codable {
    
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: String(describing: FyleMetadata.self))
    
    let fileName: String
    public let sha256: Data
    let contentType: UTType

    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case sha256 = "sha256"
        case type = "type" // MIME type
    }
    
    init(fileName: String, sha256: Data, contentType: UTType) {
        self.fileName = fileName
        self.sha256 = sha256
        self.contentType = contentType
    }
    
    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let mimeType = try values.decode(String.self, forKey: .type)
        self.fileName = try values.decode(String.self, forKey: .fileName)
        // The MIME type has precedence over the extension for determining the content type
        if let contentTypeFromMIMEType = UTType(mimeType: mimeType) {
            self.contentType = contentTypeFromMIMEType
        } else if let contentTypeFromExtension = UTType(filenameExtension: (self.fileName as NSString).pathExtension) {
            self.contentType = contentTypeFromExtension
        } else {
            self.contentType = .item
        }
        self.sha256 = try values.decode(Data.self, forKey: .sha256)
    }
    
    public func encode(to encoder: Encoder) throws {
        let mimeType: String
        if let _mimeType = contentType.preferredMIMEType {
            mimeType = _mimeType
        } else {
            os_log("Could not find appropriate MIME type for content type %{public}@. We fallback on Data", log: log, type: .error, self.contentType.debugDescription)
            mimeType = "application/octet-stream"
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mimeType, forKey: .type)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(sha256, forKey: .sha256)
    }
    
    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    
    public static func jsonDecode(_ data: Data) throws -> FyleMetadata {
        let decoder = JSONDecoder()
        return try decoder.decode(FyleMetadata.self, from: data)
    }
    
}
