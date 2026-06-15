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
import OSLog
import ObvAppCoreConstants


/// Actor used both by the source and the destination. It allows to await until a sent message was fully acked before returning to the transfer step.
///
/// When send a message (or an attachment chunk), the `WebRTCTransferTransportDelegate` eventually calls the following method:
/// ```
/// private func sendMessage(type: TransferMessageType, serializedMessage: Data) async throws
///
/// ```
/// We want this method to return only when all the chunks of the message (at the RTC level) are properly acknoledged.
///
/// This actor is called when:
/// - a new chunk must be acknowledged;
/// - a chunk is acknowledged;
/// - when the above method needs to await until all chunks are ackowledged.
///
/// The above method draws a random `UUID` for the message it sents, allowing to easily map expected acks to received acks.
actor AckDispatcher {
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "AckDispatcher")
    
    private var unackedSentMessages: [UUID: [RTCDataBufferHandler.MessageAndChunkNumber]] = [:]
    private var continuationForSentMessage = [UUID : CheckedContinuation<Void, Error>]()
    
    func newUnackedSentMessages(sentMessageUuid: UUID, messageAndChunkNumber: RTCDataBufferHandler.MessageAndChunkNumber) {
        var currentUnackedSentMessages = self.unackedSentMessages[sentMessageUuid, default: []]
        currentUnackedSentMessages.append(messageAndChunkNumber)
        self.unackedSentMessages[sentMessageUuid] = currentUnackedSentMessages
    }
    
    func receivedAck(messageAndChunkNumber: RTCDataBufferHandler.MessageAndChunkNumber) {
        var sentMessageUuidFound: UUID?
        for (messageUuid, currentUnackedSentMessages) in self.unackedSentMessages {
            guard sentMessageUuidFound == nil else { break }
            if currentUnackedSentMessages.contains(where: { $0 == messageAndChunkNumber }) {
                sentMessageUuidFound = messageUuid
                let newUnackedSentMessages = currentUnackedSentMessages.filter({ $0 != messageAndChunkNumber })
                self.unackedSentMessages[messageUuid] = newUnackedSentMessages
                Self.logger.debug("📰 Received ack. Number of remaining expected acks for the sent message: \(newUnackedSentMessages.count)")
                break
            }
        }
        
        if let sentMessageUuidFound {
            yieldIfPossible(sentMessageUuid: sentMessageUuidFound)
        } else {
            Self.logger.fault("We receive a ack we were not expecting")
            assertionFailure()
        }
    }
    
    
    func waitUntilAllSentMessageAcksAreReceived(sentMessageUuid: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            assert(self.continuationForSentMessage[sentMessageUuid] == nil)
            self.continuationForSentMessage[sentMessageUuid] = continuation
            yieldIfPossible(sentMessageUuid: sentMessageUuid)
        }
    }
    
    
    private func yieldIfPossible(sentMessageUuid: UUID) {
        guard let continuation = self.continuationForSentMessage[sentMessageUuid] else { return }
        guard unackedSentMessages[sentMessageUuid]?.isEmpty == true else { return }
        unackedSentMessages.removeValue(forKey: sentMessageUuid)
        continuationForSentMessage.removeValue(forKey: sentMessageUuid)
        continuation.resume()
    }
    
}


extension AckDispatcher {
    
    func finishAllDispatchesByThrowing(_ error: any Error) {
        while let continuation = continuationForSentMessage.popFirst() {
            continuation.value.resume(throwing: error)
        }
    }
    
}
