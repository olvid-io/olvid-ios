/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import CoreData
import OlvidUtils
import ObvMetaManager
import ObvTypes
import os.log


final class UpdateCachedWellKnownOperation: ContextualOperationWithSpecificReasonForCancel<UpdateCachedWellKnownOperation.ReasonForCancel>, @unchecked Sendable {
    
    private let server: URL
    private let newWellKnownData: Data
    private let flowId: FlowIdentifier

    
    init(server: URL, newWellKnownData: Data, flowId: FlowIdentifier) {
        self.server = server
        self.newWellKnownData = newWellKnownData
        self.flowId = flowId
        super.init()
    }
    
    private(set) var cachedWellKnownJSON: (json: WellKnownJSON, isUpdated: Bool)?
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            var isUpdated = false

            let newWellKnownJSON: WellKnownJSON?
            if let currentWellKnown = try CachedWellKnown.getCachedWellKnown(for: server, within: obvContext) {
                if newWellKnownData == currentWellKnown.wellKnownData {
                    if let wellKnownJSON = currentWellKnown.wellKnownJSON {
                        self.cachedWellKnownJSON = (wellKnownJSON, false)
                        // Nothing left to do
                        return
                    } else {
                        assertionFailure()
                        currentWellKnown.update(with: newWellKnownData)
                        isUpdated = true
                    }
                } else {
                    currentWellKnown.update(with: newWellKnownData)
                    isUpdated = true
                }
                newWellKnownJSON = currentWellKnown.wellKnownJSON
            } else {
                guard let cachedWellKnown = CachedWellKnown(serverURL: server, wellKnownData: newWellKnownData, downloadTimestamp: Date(), within: obvContext) else {
                    return cancel(withReason: .couldNotCreateCachedWellKnownObject)
                }
                newWellKnownJSON = cachedWellKnown.wellKnownJSON
            }

            guard let newWellKnownJSON else {
                return
            }
            
            self.cachedWellKnownJSON = (newWellKnownJSON, isUpdated)
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case couldNotCreateCachedWellKnownObject

        public var logType: OSLogType {
            return .fault
        }

        public var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .couldNotCreateCachedWellKnownObject:
                return "Could not create CachedWellKnown object"
            }
        }

    }

}
