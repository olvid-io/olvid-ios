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
import ObvUI

extension PersistedDiscussion {

    func computeNumberOfNewReceivedMessages() -> Int {
        var numberOfNewMessages = 0
        numberOfNewMessages += (try? PersistedMessageReceived.countNew(within: self)) ?? 0
        numberOfNewMessages += (try? PersistedMessageSystem.countNew(within: self)) ?? 0
        return numberOfNewMessages
    }

    var circledInitialsConfiguration: ObvUI.CircledInitialsConfiguration? {
        switch status {
        case .locked:
            return .icon(.lockFill)
        case .preDiscussion, .active:
            switch try? kind {
            case .oneToOne(withContactIdentity: let contactIdentity):
                return contactIdentity?.circledInitialsConfiguration
            case .groupV1(withContactGroup: let contactGroup):
                return contactGroup?.circledInitialsConfiguration
            case .groupV2(withGroup: let group):
                return group?.circledInitialsConfiguration
            case .none:
                assertionFailure()
                return .icon(.lockFill)
            }
        }
    }
}


// MARK: - Utility methods for PersistedSystemMessage showing the number of new messages

extension PersistedDiscussion {

    var appropriateSortIndexAndNumberOfNewMessagesForNewMessagesSystemMessage: (sortIndex: Double, numberOfNewMessages: Int)? {

        assert(Thread.isMainThread)

        guard let context = self.managedObjectContext else {
            assertionFailure()
            return nil
        }

        guard context.concurrencyType == NSManagedObjectContextConcurrencyType.mainQueueConcurrencyType else {
            assertionFailure()
            return nil
        }

        let firstNewMessage: PersistedMessage
        do {
            let firstNewReceivedMessage: PersistedMessageReceived?
            do {
                firstNewReceivedMessage = try PersistedMessageReceived.getFirstNew(in: self)
            } catch {
                assertionFailure()
                return nil
            }

            let firstNewRelevantSystemMessage: PersistedMessageSystem?
            do {
                firstNewRelevantSystemMessage = try PersistedMessageSystem.getFirstNewRelevantSystemMessage(in: self)
            } catch {
                assertionFailure()
                return nil
            }

            switch (firstNewReceivedMessage, firstNewRelevantSystemMessage) {
            case (.none, .none):
                return nil
            case (.some(let msg), .none):
                firstNewMessage = msg
            case (.none, .some(let msg)):
                firstNewMessage = msg
            case (.some(let msg1), .some(let msg2)):
                firstNewMessage = msg1.sortIndex < msg2.sortIndex ? msg1 : msg2
            }
        }

        let numberOfNewMessages: Int
        do {
            let numberOfNewReceivedMessages = try PersistedMessageReceived.countNew(within: self)
            let numberOfNewRelevantSystemMessages = try PersistedMessageSystem.countNewRelevantSystemMessages(in: self)
            numberOfNewMessages = numberOfNewReceivedMessages + numberOfNewRelevantSystemMessages
        } catch {
            assertionFailure()
            return nil
        }

        guard numberOfNewMessages > 0 else {
            return nil
        }

        let sortIndexForFirstNewMessageLimit: Double

        if let messageAboveFirstUnNewReceivedMessage = try? PersistedMessage.getMessage(beforeSortIndex: firstNewMessage.sortIndex, in: self) {
            if (messageAboveFirstUnNewReceivedMessage as? PersistedMessageSystem)?.category == .numberOfNewMessages {
                // The message just above the first new message is a PersistedMessageSystem showing the number of new messages
                // We can simply use its sortIndex
                sortIndexForFirstNewMessageLimit = messageAboveFirstUnNewReceivedMessage.sortIndex
            } else {
                // The message just above the first new message is *not* a PersistedMessageSystem showing the number of new messages
                // We compute the mean of the sort indexes of the two messages to get a sortIndex appropriate to "insert" a new message between the two
                let preceedingSortIndex = messageAboveFirstUnNewReceivedMessage.sortIndex
                sortIndexForFirstNewMessageLimit = (firstNewMessage.sortIndex + preceedingSortIndex) / 2.0
            }
        } else {
            // There is no message above, we simply take a smaller sort index
            let preceedingSortIndex = firstNewMessage.sortIndex - 1
            sortIndexForFirstNewMessageLimit = (firstNewMessage.sortIndex + preceedingSortIndex) / 2.0
        }

        return (sortIndexForFirstNewMessageLimit, numberOfNewMessages)

    }

}
