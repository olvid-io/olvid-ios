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
import CoreData

extension PersistedMessageSystem {

    public static func insertNumberOfNewMessagesSystemMessage(within discussion: PersistedDiscussion) throws -> PersistedMessageSystem? {
        assert(Thread.isMainThread)
        guard let context = discussion.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        guard context.concurrencyType == NSManagedObjectContextConcurrencyType.mainQueueConcurrencyType else {
            assertionFailure()
            throw ObvUICoreDataError.inappropriateContext
        }
        if let message = try PersistedMessageSystem(discussion: discussion) {
            context.insert(message)
            return message
        } else {
            return nil
        }
    }


    /// This initialiser is specific to `numberOfNewMessages` system messages
    ///
    /// - Parameter discussion: The persisted discussion in which a `numberOfNewMessages` should be added
    private convenience init?(discussion: PersistedDiscussion) throws {

        assert(Thread.isMainThread)

        guard let context = discussion.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }

        guard context.concurrencyType == NSManagedObjectContextConcurrencyType.mainQueueConcurrencyType else {
            assertionFailure()
            throw ObvUICoreDataError.inappropriateContext
        }

        guard let (sortIndexForFirstNewMessageLimit, numberOfNewMessages) = discussion.appropriateSortIndexAndNumberOfNewMessagesForNewMessagesSystemMessage else {
            return nil
        }

        try self.init(discussion: discussion,
                      sortIndexForFirstNewMessageLimit: sortIndexForFirstNewMessageLimit,
                      timestamp: Date.distantPast,
                      numberOfNewMessages: numberOfNewMessages)
    }

}
