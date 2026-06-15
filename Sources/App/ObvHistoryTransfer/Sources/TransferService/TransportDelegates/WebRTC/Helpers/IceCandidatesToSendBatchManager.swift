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
import WebRTC


actor IceCandidatesToSendBatchManager {
    
    private let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "IceCandidatesToSendBatchManager")
        
    private enum IceCandidatesToSendBatchStatus {
        case notBatchingYet
        case batching(currentIceCandidates: [RTCIceCandidate])
    }
    
    private var internalStatus: IceCandidatesToSendBatchStatus = .notBatchingYet

    enum BatchResult {
        case batchProcessedByAnotherTask
        case processBatch(iceCandidates: [RTCIceCandidate])
    }
    

    func batch(_ iceCandidate: RTCIceCandidate) async -> BatchResult {
        
        logger.debug("Call to batch")
                
        switch internalStatus {
            
        case .notBatchingYet:

            logger.debug("Not batching yet")

            self.internalStatus = .batching(currentIceCandidates: [iceCandidate])

            logger.debug("Will wait for 200ms")

            try? await Task.sleep(milliseconds: 200)

            logger.debug("Did wait for 200ms")

            let currentInternalStatus = self.internalStatus
            
            switch currentInternalStatus {
            case .notBatchingYet:
                assertionFailure()
                return .batchProcessedByAnotherTask
            case .batching(currentIceCandidates: let currentIceCandidates):
                self.internalStatus = .notBatchingYet
                logger.debug("Returning \(currentIceCandidates.count) ICE candidates to send")
                return .processBatch(iceCandidates: currentIceCandidates)
            }
            
        case .batching(currentIceCandidates: var currentIceCandidates):
            currentIceCandidates.append(iceCandidate)
            self.internalStatus = .batching(currentIceCandidates: currentIceCandidates)
            logger.debug("Added one candidate to the batch that now contains \(currentIceCandidates.count) candidates")
            return .batchProcessedByAnotherTask
            
        }
    }
    
}
