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
import CoreData
import ObvTypes
import ObvAppTypes
import ObvUICoreData


struct HistoryTransferDataSourceHelper {
    
    let backgroundContext: NSManagedObjectContext
    
    init(backgroundContext: NSManagedObjectContext) {
        self.backgroundContext = backgroundContext
    }
    
    func getAllHashAndSizesOfFyles(ownedCryptoId: ObvCryptoId) async throws -> [Data : UInt64] {
        let backgroundContext = self.backgroundContext
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Data : UInt64], any Error>) in
            backgroundContext.perform {
                do {
                    let sentFyles = try SentFyleMessageJoinWithStatus.getSha256AndSizeOfCompleteFyles(
                        ownedCryptoId: ownedCryptoId,
                        within: backgroundContext)
                    let receivedFyles = try ReceivedFyleMessageJoinWithStatus.getSha256AndSizeOfCompleteFyles(
                        ownedCryptoId: ownedCryptoId,
                        within: backgroundContext)
                    let allHashAndSizes: [Data : UInt64] = sentFyles.merging(receivedFyles) { current, _ in
                        return current
                    }
                    return continuation.resume(returning: allHashAndSizes)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
    }

    
    func getTitleAndAllMessageIdentifiersOfDiscussion(discussionIdentifier: ObvDiscussionIdentifier) async throws -> (discussionTitle: String, messageIdentifiers: [ObvMessageAppIdentifier]) {
        let backgroundContext = self.backgroundContext
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(discussionTitle: String, messageIdentifiers: [ObvMessageAppIdentifier]), any Error>) in
            backgroundContext.perform {
                do {
                    let discussion = try PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: discussionIdentifier, within: backgroundContext)
                    guard let discussion else {
                        assertionFailure()
                        throw ObvError.couldNotFindDiscussion
                    }
                    let identifiersOfSentMessages: [ObvMessageAppIdentifier] = try PersistedMessageSent.getMessageIdenfiersOfAllNonSensitiveSentMessages(
                        in: discussionIdentifier,
                        within: backgroundContext)
                    let identifiersOfReceivedMessages: [ObvMessageAppIdentifier] = try PersistedMessageReceived.getMessageIdenfiersOfAllNonSensitiveSentMessages(
                        in: discussionIdentifier,
                        within: backgroundContext)
                    let identifiersOfMessages = identifiersOfSentMessages + identifiersOfReceivedMessages
                    return continuation.resume(returning: (discussion.title, messageIdentifiers: identifiersOfMessages))
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
    }

    
    func getAllDiscussionIdentifiers(ownedCryptoId: ObvCryptoId) async throws -> [ObvAppTypes.ObvDiscussionIdentifier] {
        let backgroundContext = self.backgroundContext
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ObvAppTypes.ObvDiscussionIdentifier], any Error>) in
            backgroundContext.perform {
                do {
                    let discussionIdentifiers = try PersistedDiscussion.getIdentifiersOfActiveAndLockedDiscussions(ownedCryptoId: ownedCryptoId, within: backgroundContext)
                    return continuation.resume(returning: discussionIdentifiers)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
    }

}


extension HistoryTransferDataSourceHelper {
    
    enum ObvError: Error {
        case couldNotFindDiscussion
    }
    
}
