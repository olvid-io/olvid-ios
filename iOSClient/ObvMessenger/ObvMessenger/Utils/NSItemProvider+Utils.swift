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
import UniformTypeIdentifiers


extension NSItemProvider {
    
    /// Simple wrapper as ``registeredContentTypes`` only exists in iOS 16
    var obvRegisteredContentTypes: [UTType] {
        if #available(iOS 16, *) {
            return self.registeredContentTypes
        } else {
            let types = self.registeredTypeIdentifiers.compactMap({ UTType($0) })
            assert(types.count == self.registeredTypeIdentifiers.count)
            return types
        }
    }
    
    
    func loadText() async throws -> String {
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            
            loadItem(forTypeIdentifier: UTType.text.identifier) { item, error in
                if let error {
                    assertionFailure()
                    continuation.resume(throwing: error)
                    return
                }
                guard let text = item as? String else {
                    assertionFailure()
                    continuation.resume(throwing: ObvError.cannotCastItemAsString)
                    return
                }
                continuation.resume(returning: text)
            }
            
        }
        
    }
    
    enum ObvError: Error {
        case cannotCastItemAsString
    }

}
