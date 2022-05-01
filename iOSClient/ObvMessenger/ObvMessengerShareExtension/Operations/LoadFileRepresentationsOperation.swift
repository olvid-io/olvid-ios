/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

final class LoadFileRepresentationsOperation: Operation, LoadedItemProviderProvider {

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


    private let itemProviders: [NSItemProvider]
    private let log: OSLog

    private(set) var loadedItemProviders: [LoadedItemProvider]?

    init(itemProviders: [NSItemProvider], log: OSLog) {
        self.itemProviders = itemProviders
        self.log = log
        super.init()
    }

    override func main() {
        var loadedItemProviders = [LoadedItemProvider]()
        for itemProvider in itemProviders {
            let op = LoadItemProviderOperation(itemProvider: itemProvider, progressAvailable: { _ in })
            op.start()
            op.waitUntilFinished()
            assert(op.isFinished)
            guard !op.isCancelled else {
                op.logReasonIfCancelled(log: log)
                return
            }
            guard let loadedItemProvider = op.loadedItemProvider else {
                return
            }
            loadedItemProviders += [loadedItemProvider]
        }
        self.loadedItemProviders = loadedItemProviders
    }

}
