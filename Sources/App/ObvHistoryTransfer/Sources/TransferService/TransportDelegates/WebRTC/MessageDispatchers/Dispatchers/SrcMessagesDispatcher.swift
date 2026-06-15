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
import ObvAppTypes


actor SrcMessagesDispatcher {
    
    private var pendingSrcMessages = [SrcMessages]()
    private var continuationOnSrcMessages: AsyncThrowingStream<SrcMessages, Error>.Continuation?
    private var numberOfExpectedMessages = 0 // Set when the continuation is created

    
    func dispatchSrcMessagesToDestinationTransferSteps(srcMessages: SrcMessages) {
        pendingSrcMessages.insert(srcMessages, at: 0)
        yieldSrcMessagesIfPossible()
    }

    
    func destinationTransferStepsRequestsStreamOfSrcMessages(numberOfExpectedMessages: Int) -> AsyncThrowingStream<SrcMessages, Error> {
        self.numberOfExpectedMessages = numberOfExpectedMessages
        let stream = AsyncThrowingStream<SrcMessages, Error> { (continuation: AsyncThrowingStream<SrcMessages, Error>.Continuation) in
            assert(continuationOnSrcMessages == nil)
            self.continuationOnSrcMessages = continuation
            yieldSrcMessagesIfPossible()
        }
        return stream
    }
    
    
    private func yieldSrcMessagesIfPossible() {
        guard let continuationOnSrcMessages else { return }
        while let srcMessages = pendingSrcMessages.popLast() {
            numberOfExpectedMessages -= (srcMessages.missingMessageCount + srcMessages.messages.count)
            assert(numberOfExpectedMessages >= 0)
            continuationOnSrcMessages.yield(srcMessages)
        }
        if numberOfExpectedMessages <= 0 {
            continuationOnSrcMessages.finish()
            self.continuationOnSrcMessages = nil
        }
    }

}


extension SrcMessagesDispatcher {
    
    func finishAllDispatchesByThrowing(_ error: any Error) {
        continuationOnSrcMessages?.finish(throwing: error)
        continuationOnSrcMessages = nil
    }
    
}
