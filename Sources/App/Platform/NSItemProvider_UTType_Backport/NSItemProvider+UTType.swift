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

@available(iOSApplicationExtension 14, *)
public extension NSItemProvider {
    /// Convenience method that calls `NSItemProvider.hasItemConformingToTypeIdentifier(_:)` with `type`'s `identifier`
    /// - Parameter type: The type to verify
    /// - Returns: Returns YES if the item provider has at least one item that conforms to the supplied type identifier.
    func hasItemConformingToTypeIdentifier(_ type: UTType) -> Bool {
        return hasItemConformingToTypeIdentifier(type.identifier)
    }
}
