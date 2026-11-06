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


/// Filters an export's progress reports so that an older report never overwrites a newer one.
///
/// Each report carries a generation, handed out in increasing order. Per key, the filter keeps the latest generation and whether it has
/// reported nil:
///
/// - a report from an older generation is dropped, fraction or nil;
/// - a report from a newer generation is accepted and becomes the latest;
/// - a report from the same generation is accepted, unless that generation has already reported nil.
struct ExportProgressReportFilter<Key: Hashable> {

    private struct Latest {
        let generation: Int
        let hasStopped: Bool
    }

    private var latestForKey = [Key: Latest]()

    /// Whether to pass the report on. An accepted report becomes the latest for its key.
    mutating func accepts(_ fractionCompleted: Double?, for key: Key, generation: Int) -> Bool {
        if let latest = latestForKey[key] {
            if generation < latest.generation { return false }
            if generation == latest.generation, latest.hasStopped { return false }
        }
        latestForKey[key] = Latest(generation: generation, hasStopped: fractionCompleted == nil)
        return true
    }

}
