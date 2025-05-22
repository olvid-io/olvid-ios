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
import ObvEncoder


public protocol ObvSyncSnapshotNode: Codable, Hashable, Identifiable, Sendable {

    /// Computes a list of differences between the current snapshot and the other snapshot.
    //func computeDiff(withOther syncSnapshotNode: Self) -> Set<ObvSyncDiff>

}


public extension ObvSyncSnapshotNode {
    
    static func generateIdentifier() -> String {
        ObvSyncSnapshotNodeUtils.generateIdentifier()
    }
    
}


public struct ObvSyncSnapshotNodeUtils {
    
    public static func generateIdentifier() -> String {
        return [UUID(), UUID(), UUID(), UUID()].map({ $0.uuidString }).joined()
    }

}


//public extension ObvSyncSnapshotNode {
//
//    /// Returns `true` if both ObvSyncSnapshotNode are exactly the same (deep compare).
//    /// If the `other` ObvSyncSnapshotNode is `nil`, this method returns `false`.
//    func isContentIdenticalTo(other syncSnapshotNode: Self?) -> Bool {
//        guard let syncSnapshotNode else { return false }
//        let diff = self.computeDiff(withOther: syncSnapshotNode)
//        return diff.isEmpty
//    }
//
//}
