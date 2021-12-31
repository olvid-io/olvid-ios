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
import OlvidUtils
import ObvMetaManager
import ObvTypes
import os.log

protocol UpdateCachedWellKnownOperationDelegate: AnyObject {
    func newWellKnownWasCached(server: URL, newWellKnownJSON: WellKnownJSON, flowId: FlowIdentifier)
    func cachedWellKnownWasUpdated(server: URL, newWellKnownJSON: WellKnownJSON, flowId: FlowIdentifier)
}

final class UpdateCachedWellKnownOperation: OperationWithSpecificReasonForCancel<UpdateCachedWellKnownOperationReasonForCancel> {

    let newWellKnownData: Data
    let server: URL
    let flowId: FlowIdentifier
    let log: OSLog
    weak var contextCreator: ObvCreateContextDelegate?
    weak var delegate: UpdateCachedWellKnownOperationDelegate?

    init(newWellKnownData: Data, server: URL, log: OSLog, flowId: FlowIdentifier, contextCreator: ObvCreateContextDelegate, delegate: UpdateCachedWellKnownOperationDelegate) {
        self.newWellKnownData = newWellKnownData
        self.server = server
        self.contextCreator = contextCreator
        self.delegate = delegate
        self.flowId = flowId
        self.log = log
        super.init()
    }
    
    override func main() {
        
        guard let contextCreator = self.contextCreator, let delegate = self.delegate else {
            assertionFailure()
            return cancel(withReason: .delegateIsNotSet)
        }
        
        let flowId = self.flowId
        let server = self.server
        let log = self.log
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { obvContext in

            var isUpdated = false

            let _newWellKnownJSON: WellKnownJSON?
            if let currentWellKnown = try? CachedWellKnown.getCachedWellKnown(for: server, within: obvContext) {
                if newWellKnownData == currentWellKnown.wellKnownData {
                    // Nothing to do
                    return
                } else {
                    currentWellKnown.update(with: newWellKnownData)
                    isUpdated = true
                }
                _newWellKnownJSON = currentWellKnown.wellKnownJSON
            } else {
                guard let cachedWellKnown = CachedWellKnown(serverURL: server, wellKnownData: newWellKnownData, downloadTimestamp: Date(), within: obvContext) else {
                    return cancel(withReason: .couldNotCreateCachedWellKnownObject)
                }
                _newWellKnownJSON = cachedWellKnown.wellKnownJSON
            }

            guard let newWellKnownJSON = _newWellKnownJSON else {
                return
            }
            
            try? obvContext.addContextDidSaveCompletionHandler { error in
                guard error == nil else { return }

                // This will trigger a `wellKnownHasBeenDownloaded` notification. On Android, this notification is not sent when `wellKnownHasBeenUpdated` is sent. But we agreed with Matthieu that this is better ;-)
                delegate.newWellKnownWasCached(server: server, newWellKnownJSON: newWellKnownJSON, flowId: flowId)

                if isUpdated {
                    delegate.cachedWellKnownWasUpdated(server: server, newWellKnownJSON: newWellKnownJSON, flowId: flowId)
                }
            }

            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                os_log("Could not save context", log: log, type: .error)
                return
            }

            
        }
        

    }
    
    
}


public enum UpdateCachedWellKnownOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case delegateIsNotSet
    case couldNotCreateCachedWellKnownObject
    case couldNotDecodeNewWellKnown

    public var logType: OSLogType {
        switch self {
        case .coreDataError,
             .delegateIsNotSet,
             .couldNotDecodeNewWellKnown:
            return .fault
        case .couldNotCreateCachedWellKnownObject:
            return .error
        }
    }

    public var errorDescription: String? {
        switch self {
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .delegateIsNotSet:
            return "Delegate is not set"
        case .couldNotCreateCachedWellKnownObject:
            return "Could not create CachedWellKnown object"
        case .couldNotDecodeNewWellKnown:
            return "Could not decode new well known"
        }
    }

}
