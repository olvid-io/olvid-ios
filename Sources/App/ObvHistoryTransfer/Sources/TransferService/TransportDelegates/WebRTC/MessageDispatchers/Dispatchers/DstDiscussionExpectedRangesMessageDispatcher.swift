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


actor DstDiscussionExpectedRangesMessageDispatcher {
    
    private enum ReceptionStatus: Equatable {
        case notReceivedYet
        case received(DstDiscussionExpectedRanges)
        case transferredToDestinationTransferSteps
    }

    private var receptionStatusForDiscussion = [JsonDiscussionIdentifier : ReceptionStatus]()
    private var continuationOnDstDiscussionExpectedRangesForDiscussion = [JsonDiscussionIdentifier: CheckedContinuation<DstDiscussionExpectedRanges, any Error>]()

    func dispatchDstDiscussionExpectedRangesToSourceTransferSteps(dstDiscussionExpectedRanges: DstDiscussionExpectedRanges) {
        let discussionIdentifier = dstDiscussionExpectedRanges.discussionIdentifier
        assert(receptionStatusForDiscussion[discussionIdentifier, default: .notReceivedYet] == .notReceivedYet)
        receptionStatusForDiscussion[discussionIdentifier] = .received(dstDiscussionExpectedRanges)
        yieldDstDiscussionExpectedRangesIfPossible()
    }
    
 
    func receiveDstDiscussionExpectedRanges(discussionIdentifier: JsonDiscussionIdentifier) async throws -> DstDiscussionExpectedRanges {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DstDiscussionExpectedRanges, any Error>) in
            assert(continuationOnDstDiscussionExpectedRangesForDiscussion[discussionIdentifier] == nil)
            self.continuationOnDstDiscussionExpectedRangesForDiscussion[discussionIdentifier] = continuation
            yieldDstDiscussionExpectedRangesIfPossible()
        }
    }
    
    
    private func yieldDstDiscussionExpectedRangesIfPossible() {
        for (discussionIdentifier, receptionStatus) in receptionStatusForDiscussion {
            switch receptionStatus {
            case .received(let dstDiscussionExpectedRanges):
                if let continuation = continuationOnDstDiscussionExpectedRangesForDiscussion.removeValue(forKey: discussionIdentifier) {
                    continuation.resume(returning: dstDiscussionExpectedRanges)
                    receptionStatusForDiscussion[discussionIdentifier] = .transferredToDestinationTransferSteps
                }
            case .notReceivedYet, .transferredToDestinationTransferSteps:
                continue
            }
        }
        
    }
    
}


extension DstDiscussionExpectedRangesMessageDispatcher {
    
    func finishAllDispatchesByThrowing(_ error: any Error) {
        while let continuation = self.continuationOnDstDiscussionExpectedRangesForDiscussion.popFirst() {
            continuation.value.resume(throwing: error)
        }
    }
    
}
