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
import CryptoKit

public extension URL {
    
    func getFileSize() -> Int? {
        guard FileManager.default.fileExists(atPath: self.path) else { return nil }
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: self.path) else { return nil }
        return fileAttributes[FileAttributeKey.size] as? Int
    }
 
    func toFileNameForArchiving() -> String? {
        let digest = SHA256.hash(data: self.dataRepresentation)
        let digestString = digest.map { String(format: "%02hhx", $0) }.joined()
        return [digestString, "obvarchive"].joined(separator: ".")
    }
    
    
    var isArchive: Bool {
        return self.pathExtension == "obvarchive"
    }
    
    var toHttpsURL: URL? {
        let safeURL: URL
        if var urlComponents = URLComponents(url: self, resolvingAgainstBaseURL: true) {
            switch urlComponents.scheme?.lowercased() {
            case "https":
                safeURL = self
            case "http":
                urlComponents.scheme = "https"
                guard let constructedURL = urlComponents.url else { assertionFailure(); return nil }
                safeURL = constructedURL
            case nil:
                guard let constructedURL = URL(string: ["https://", self.path].joined()) else { assertionFailure(); return nil }
                safeURL = constructedURL
            default:
                assertionFailure()
                return nil
            }
        } else {
            assertionFailure()
            return nil
        }
        return safeURL
    }
    
}
