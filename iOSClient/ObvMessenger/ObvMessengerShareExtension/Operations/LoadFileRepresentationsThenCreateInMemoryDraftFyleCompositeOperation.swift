/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import os.log
import OlvidUtils

final class LoadFileRepresentationsThenCreateInMemoryDraftFyleCompositeOperation: Operation {
    
    private func logReasonOfCancelledOperations(_ operations: [OperationThatCanLogReasonForCancel]) {
        let cancelledOps = operations.filter({ $0.isCancelled })
        for op in cancelledOps {
            op.logReasonIfCancelled(log: log)
        }
    }

    private let internalQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "LoadFileRepresentationsThenCreateInMemoryDraftFyleOperation internal queue"
        return queue
    }()
    

    private let inMemoryDraft: InMemoryDraft
    private let itemProviders: [NSItemProvider]
    private let log: OSLog
    
    init(inMemoryDraft: InMemoryDraft, itemProviders: [NSItemProvider], log: OSLog) {
        self.inMemoryDraft = inMemoryDraft
        self.itemProviders = itemProviders
        self.log = log
        super.init()
    }
    
    override func main() {
        
        let loadItemProviderOperations = itemProviders.map { LoadItemProviderOperation(itemProvider: $0, progressAvailable: { _ in }) }
        internalQueue.addOperations(loadItemProviderOperations, waitUntilFinished: true)
        logReasonOfCancelledOperations(loadItemProviderOperations)
        
        let loadedItemProviders = loadItemProviderOperations.compactMap({ $0.loadedItemProvider })
        let createDraftFyleJoinsOperation = CreateInMemoryDraftFyleFromLoadedFileRepresentationsOperation(inMemoryDraft: inMemoryDraft, loadedItemProviders: loadedItemProviders, log: log)
        internalQueue.addOperations([createDraftFyleJoinsOperation], waitUntilFinished: true)
        createDraftFyleJoinsOperation.logReasonIfCancelled(log: log)
        
    }

}
