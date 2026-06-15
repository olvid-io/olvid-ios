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

/// Dispatches `SrcDiscussionRanges` messages received from the transport layer to `DestinationTransferSteps`.
actor SrcDiscussionRangesMessageDispatcher {
    
    private enum ReceptionStatus: Equatable {
        case notReceivedYet
        case received(SrcDiscussionRanges)
        case transferredToDestinationTransferSteps
    }
    
    private var pendingSrcDiscussionRangesForDiscussionIdentifiers = [JsonDiscussionIdentifier : ReceptionStatus]()
    private var continuationOnSrcDiscussionRanges: AsyncThrowingStream<SrcDiscussionRanges, Error>.Continuation?

    
    func dispatchSrcDiscussionRangesToDestinationTransferSteps(srcDiscussionRanges: SrcDiscussionRanges) {
        self.pendingSrcDiscussionRangesForDiscussionIdentifiers[srcDiscussionRanges.discussionIdentifier] = .received(srcDiscussionRanges)
        yieldSrcDiscussionRangesIfPossible()
    }
 
    
    func destinationTransferStepsRequestsStreamOfSrcDiscussionRanges(expectedDiscussionIdentifiers: [JsonDiscussionIdentifier]) async -> AsyncThrowingStream<SrcDiscussionRanges, Error> {
        for discussionIdentifier in expectedDiscussionIdentifiers {
            if pendingSrcDiscussionRangesForDiscussionIdentifiers[discussionIdentifier] == nil {
                pendingSrcDiscussionRangesForDiscussionIdentifiers[discussionIdentifier] = .notReceivedYet
            }
        }
        let stream = AsyncThrowingStream<SrcDiscussionRanges, Error> { (continuation: AsyncThrowingStream<SrcDiscussionRanges, Error>.Continuation) in
            assert(self.continuationOnSrcDiscussionRanges == nil)
            self.continuationOnSrcDiscussionRanges = continuation
            yieldSrcDiscussionRangesIfPossible()
        }
        return stream
    }
    
    
    private func yieldSrcDiscussionRangesIfPossible() {
        guard let continuationOnSrcDiscussionRanges else { return }
        for (discussionIdentifier, receptionStatus) in self.pendingSrcDiscussionRangesForDiscussionIdentifiers {
            switch receptionStatus {
            case .received(let srcDiscussionRanges):
                pendingSrcDiscussionRangesForDiscussionIdentifiers[discussionIdentifier] = .transferredToDestinationTransferSteps
                continuationOnSrcDiscussionRanges.yield(srcDiscussionRanges)
            case .notReceivedYet,
                    .transferredToDestinationTransferSteps:
                continue
            }
        }
        if pendingSrcDiscussionRangesForDiscussionIdentifiers.allSatisfy({ $1 == .transferredToDestinationTransferSteps }) {
            continuationOnSrcDiscussionRanges.finish()
            self.continuationOnSrcDiscussionRanges = nil
        }
    }

}


extension SrcDiscussionRangesMessageDispatcher {
    
    func finishAllDispatchesByThrowing(_ error: any Error) {
        continuationOnSrcDiscussionRanges?.finish(throwing: error)
        continuationOnSrcDiscussionRanges = nil
    }
    
}
