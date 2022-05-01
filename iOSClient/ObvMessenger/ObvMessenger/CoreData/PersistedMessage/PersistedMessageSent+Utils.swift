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
import CoreData

extension PersistedMessageSent {

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: Self.self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    /// This method returns the number of outbound messages within the specified discussion that are at least in the `sent` state, and
    /// that occur after the message passed as a parameter.
    /// This method is typically used for displaying count based retention information for a specific message.
    static func countAllSentMessages(after messageObjectID: NSManagedObjectID, discussion: PersistedDiscussion) throws -> Int {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Cannot find context in PersistedDiscussion") }
        guard let message = try PersistedMessage.get(with: messageObjectID, within: context) else {
            throw makeError(message: "Cannot find message to compare to")
        }
        let request: NSFetchRequest<PersistedMessageSent> = PersistedMessageSent.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.wasSent,
            Predicate.withLargerSortIndex(than: message)
        ])
        return try context.count(for: request)
    }

}
