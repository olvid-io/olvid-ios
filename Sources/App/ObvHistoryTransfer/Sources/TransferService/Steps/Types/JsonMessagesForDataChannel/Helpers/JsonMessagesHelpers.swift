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
import ObvTypes
import ObvAppTypes


struct JsonMessagesHelpers {
    
    static func rangesByThreadAndSender(messageIdentifiers: [ObvMessageAppIdentifier]) -> [ObvCryptoId : [UUID : [ClosedRange<Int>]]] {
        
        let messagesForSenderCryptoId: [ObvCryptoId : [ObvMessageAppIdentifier]] = Dictionary(grouping: messageIdentifiers) { $0.senderCryptoId }
        
        var currentRangesByThreadAndSender = [ObvCryptoId : [UUID : [ClosedRange<Int>]]]()

        for (senderCryptoId, messages) in messagesForSenderCryptoId {
            
            let messagesForSenderThreadIdentifier: [UUID: [ObvMessageAppIdentifier]] = Dictionary(grouping: messages) { $0.senderThreadIdentifier }
            
            var currentRangesByThread = [UUID : [ClosedRange<Int>]]()
            
            for (senderThreadIdentifier, messages) in messagesForSenderThreadIdentifier {
                
                let senderSequenceNumbers: [Int] = messages.map(\.senderSequenceNumber)
                currentRangesByThread[senderThreadIdentifier] = senderSequenceNumbers.toClosedRanges
                
            }
                
            currentRangesByThreadAndSender[senderCryptoId] = currentRangesByThread
                    
        }

        return currentRangesByThreadAndSender
        
    }

    
    static func messageIdentifiers(discussionIdentifier: ObvDiscussionIdentifier, rangesByThreadAndSender: [ObvCryptoId : [UUID : [ClosedRange<Int>]]]) -> [ObvMessageAppIdentifier] {
        var messageIdentifiers = [ObvMessageAppIdentifier]()
        for (sender, rangesByThread) in rangesByThreadAndSender {
            messageIdentifiers += Self.messageIdentifiers(discussionIdentifier: discussionIdentifier, sender: sender, rangesByThread: rangesByThread)
        }
        return messageIdentifiers
    }
    
    
    static func messageIdentifiers(discussionIdentifier: ObvDiscussionIdentifier, sender: ObvCryptoId, rangesByThread: [UUID : [ClosedRange<Int>]]) -> [ObvMessageAppIdentifier] {
        var messageIdentifiers = [ObvMessageAppIdentifier]()
        for (senderThreadIdentifier, ranges) in rangesByThread {
            messageIdentifiers += Self.messageIdentifiers(discussionIdentifier: discussionIdentifier, sender: sender, senderThreadIdentifier: senderThreadIdentifier, ranges: ranges)
        }
        return messageIdentifiers
    }
    
    
    static func messageIdentifiers(discussionIdentifier: ObvDiscussionIdentifier, sender: ObvCryptoId, senderThreadIdentifier: UUID, ranges: [ClosedRange<Int>]) -> [ObvMessageAppIdentifier] {
        var messageIdentifiers = [ObvMessageAppIdentifier]()
        for range in ranges {
            for senderSequenceNumber in range {
                if sender == discussionIdentifier.ownedCryptoId {
                    messageIdentifiers.append(.sent(discussionIdentifier: discussionIdentifier, senderThreadIdentifier: senderThreadIdentifier, senderSequenceNumber: senderSequenceNumber))
                } else {
                    messageIdentifiers.append(.received(discussionIdentifier: discussionIdentifier, senderIdentifier: sender.getIdentity(), senderThreadIdentifier: senderThreadIdentifier, senderSequenceNumber: senderSequenceNumber))
                }
            }
        }
        return messageIdentifiers
    }
    

}


// MARK: - Private helpers

fileprivate extension [Int] {
    
    /// Transforms a sorted list of integers into a list of closed ranges (like [1, 2, 3, 5, 6, 7] → [1...3, 5...7]).
    var toClosedRanges: [ClosedRange<Int>] {

        let sortedSelf = self.sorted()
        
        guard let last = sortedSelf.last else { return [] }
        
        var ranges = [ClosedRange<Int>]()
        var currentStart = sortedSelf[0]
        
        for i in 1..<sortedSelf.count {
            if sortedSelf[i] != 1 + sortedSelf[i-1] {
                ranges.append(currentStart...sortedSelf[i-1])
                currentStart = sortedSelf[i]
            }
        }
        ranges.append(currentStart...last)
        
        return ranges
        
    }
    
}


extension String {
    
    var base64EncodedToData: Data? {
        guard let data = Data(base64Encoded: self) else { assertionFailure(); return nil }
        return data
    }
    
}
