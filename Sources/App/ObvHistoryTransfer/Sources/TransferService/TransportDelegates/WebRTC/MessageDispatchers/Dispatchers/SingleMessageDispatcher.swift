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


/// Used to dispatch the following messages:
/// - `SrcDiscussionList`
/// - `DstExpectedSha256`
actor SingleMessageDispatcher<MessageType: Sendable & Equatable> {
    
    private enum ReceptionStatus: Equatable {
        case notReceivedYet
        case received(MessageType)
        case transferredToDestinationTransferSteps
    }
    
    
    private var receptionStatus: ReceptionStatus = .notReceivedYet
    private var continuationOnMessage: CheckedContinuation<MessageType, any Error>?

    
    func dispatchMessageToTransferSteps(message: MessageType) {
        assert(receptionStatus == .notReceivedYet)
        self.receptionStatus = .received(message)
        yieldMessageIfPossible()
    }

    
    func receiveMessage() async throws -> MessageType {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MessageType, any Error>) in
            self.continuationOnMessage = continuation
            yieldMessageIfPossible()
        }
    }

    
    private func yieldMessageIfPossible() {
        guard let continuationOnMessage else { return }
        switch receptionStatus {
        case .notReceivedYet, .transferredToDestinationTransferSteps:
            return
        case .received(let message):
            continuationOnMessage.resume(returning: message)
            self.continuationOnMessage = nil
            self.receptionStatus = .transferredToDestinationTransferSteps
        }
    }
    
}


extension SingleMessageDispatcher {
    
    func finishAllDispatchesByThrowing(_ error: any Error) {
        continuationOnMessage?.resume(throwing: error)
        continuationOnMessage = nil
    }
    
}
