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
import ObvAppTypes
import ObvTypes
import ObvHistoryTransfer
import ObvUICoreData


/// This data source is not part of all the centralized data sources as its purpose is not to feed an UI, but to provide all the data required during a message history transfer.
final class DestinationTransferStepsAppDataSource {
    
    private let backgroundContext: NSManagedObjectContext
    
    init(backgroundContext: NSManagedObjectContext) {
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.backgroundContext = backgroundContext
    }
    
}


extension DestinationTransferStepsAppDataSource: DestinationTransferStepsDataSource {
    
    /// Among the sha256s, this method returns those that are already known and complete on this destination device.
    ///
    /// The sha256s correspond to the `Fyle`s that are available on the source device.
    func filterKnownAndCompleteFyles(
        _ actor: ObvHistoryTransfer.DestinationTransferSteps,
        sha256s: [Data]
    ) async throws -> [Data] {
        return try await self.filterKnownAndCompleteFyles(sha256s: sha256s)
    }
    
    
    func filterKnownMessages(_ actor: DestinationTransferSteps, discussionIdentifier: ObvDiscussionIdentifier, messagesAvailableOnSource: [ObvMessageAppIdentifier]) async throws -> [ObvMessageAppIdentifier] {
        return try await self.filterKnownMessages(discussionIdentifier: discussionIdentifier, messagesAvailableOnSource: messagesAvailableOnSource)
    }
    
}


extension DestinationTransferStepsAppDataSource {
    
    private func filterKnownAndCompleteFyles(sha256s: [Data]) async throws -> [Data] {
        let backgroundContext = self.backgroundContext
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Data], any Error>) in
            backgroundContext.perform {
                do {
                    let knownAndCompleteSent = try SentFyleMessageJoinWithStatus.filterKnownAndCompleteFyles(sha256s: sha256s, within: backgroundContext)
                    let knownAndCompleteReceived = try ReceivedFyleMessageJoinWithStatus.filterKnownAndCompleteFyles(sha256s: sha256s, within: backgroundContext)
                    let knownAndComplete = Set(knownAndCompleteSent).union(Set(knownAndCompleteReceived))
                    return continuation.resume(returning: [Data](knownAndComplete))
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
    }

    
    private func filterKnownMessages(discussionIdentifier: ObvDiscussionIdentifier, messagesAvailableOnSource: [ObvMessageAppIdentifier]) async throws -> [ObvMessageAppIdentifier] {
        let backgroundContext = self.backgroundContext
        let sentMessagesAvailableOnSource = messagesAvailableOnSource.filter({ $0.isSent })
        let receivedMessagesAvailableOnSource = messagesAvailableOnSource.filter({ $0.isReceived })
        assert(messagesAvailableOnSource.count == sentMessagesAvailableOnSource.count + receivedMessagesAvailableOnSource.count)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ObvMessageAppIdentifier], any Error>) in
            backgroundContext.perform {
                do {
                    let knownSentMessages = try PersistedMessageSent.filterKnownMessages(discussionIdentifier: discussionIdentifier, messagesAvailableOnSource: sentMessagesAvailableOnSource, within: backgroundContext)
                    let knownReceivedMessages = try PersistedMessageReceived.filterKnownMessages(discussionIdentifier: discussionIdentifier, messagesAvailableOnSource: receivedMessagesAvailableOnSource, within: backgroundContext)
                    let knownMessages = knownSentMessages + knownReceivedMessages
                    return continuation.resume(returning: knownMessages)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
        
}
