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


/// This actor allows to dispatch the sha256s, requested by the destination, to the source.
///
/// - When a sha256 is not requested, we don't dispatch it. We simply remove it from the sha256s that we expect, which will eventually allow to finish the asynchronous loop.
/// - When a sha256 is requested, we yield its value, allowing the `SourceTransferSteps` to actually send the attachment.
actor DstRequestSha256sDispatcher {
    
    private var pendingMessages = [DstRequestSha256OrDstDoNotRequestSha256]()
    private var allSha256ToProcess: Set<Data> = []
    private var continuationOnDstRequestSha256: AsyncThrowingStream<Data, Error>.Continuation?
    
    func dispatchDstRequestSha256ToSourceTransferSteps(dstRequestSha256: DstRequestSha256) {
        self.pendingMessages.insert(.dstRequestSha256(dstRequestSha256), at: 0)
        yieldRequestedSha256IfPossible()
    }

    func dispatchDstDoNotRequestSha256ToSourceTransferSteps(dstDoNotRequestSha256: DstDoNotRequestSha256) {
        self.pendingMessages.insert(.dstDoNotRequestSha256(dstDoNotRequestSha256), at: 0)
        yieldRequestedSha256IfPossible()
    }

    func receiveSha256sRequestedByDestination(allSha256ExpectedByDestination: DstExpectedSha256) -> AsyncThrowingStream<Data, Error> {
        allSha256ToProcess = Set(allSha256ExpectedByDestination.sha256s.map(\.key))
        let stream = AsyncThrowingStream<Data, Error> { (continuation: AsyncThrowingStream<Data, Error>.Continuation) in
            assert(continuationOnDstRequestSha256 == nil)
            self.continuationOnDstRequestSha256 = continuation
            yieldRequestedSha256IfPossible()
        }
        return stream
    }
    
    
    private func yieldRequestedSha256IfPossible() {
        guard let continuationOnDstRequestSha256 else { return }
        while let dstDecision = pendingMessages.popLast() {
            let sha256: Data
            switch dstDecision {
            case .dstRequestSha256(let dstRequestSha256):
                sha256 = dstRequestSha256.sha256
                continuationOnDstRequestSha256.yield(sha256)
            case .dstDoNotRequestSha256(let dstDoNotRequestSha256):
                sha256 = dstDoNotRequestSha256.sha256
            }
            allSha256ToProcess.remove(sha256)
        }
        if allSha256ToProcess.isEmpty {
            continuationOnDstRequestSha256.finish()
            self.continuationOnDstRequestSha256 = nil
        }
    }
    
}


extension DstRequestSha256sDispatcher {
    
    func finishAllDispatchesByThrowing(_ error: any Error) {
        continuationOnDstRequestSha256?.finish(throwing: error)
        continuationOnDstRequestSha256 = nil
    }
    
}


// MARK: - Helper type

private enum DstRequestSha256OrDstDoNotRequestSha256 {
    case dstRequestSha256(DstRequestSha256)
    case dstDoNotRequestSha256(DstDoNotRequestSha256)
}
