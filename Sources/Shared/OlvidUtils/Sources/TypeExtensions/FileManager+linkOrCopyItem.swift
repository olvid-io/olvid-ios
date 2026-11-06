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


public extension FileManager {

    /// Hardlinks the file at `source` to `destination`, falling back to a copy when hardlinking is not
    /// possible (for example because the two URLs live on different volumes).
    ///
    /// The two paths refer to the same underlying bytes after a successful hardlink, so deleting either
    /// name does not delete the data while the other name still references it. This is the property that
    /// makes the call useful for "adoption" patterns: a producer hands a file to a consumer, the consumer
    /// hardlinks into its own storage, and the producer is then free to delete its own name immediately
    /// without affecting the consumer.
    func linkOrCopyItem(at source: URL, to destination: URL) throws {
        do {
            try linkItem(at: source, to: destination)
        } catch {
            try copyItem(at: source, to: destination)
        }
    }

}
