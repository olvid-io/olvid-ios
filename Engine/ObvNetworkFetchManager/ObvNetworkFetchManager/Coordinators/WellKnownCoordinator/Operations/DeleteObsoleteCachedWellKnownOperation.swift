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
import ObvCrypto
import ObvTypes
import os.log


final class DeleteObsoleteCachedWellKnownOperation: OperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    let ownedIdentities: Set<ObvCryptoIdentity>
    weak var contextCreator: ObvCreateContextDelegate?
    let log: OSLog
    let flowId: FlowIdentifier
    
    init(ownedIdentities: Set<ObvCryptoIdentity>, log: OSLog, flowId: FlowIdentifier, contextCreator: ObvCreateContextDelegate) {
        self.ownedIdentities = ownedIdentities
        self.contextCreator = contextCreator
        self.log = log
        self.flowId = flowId
        super.init()
    }
    
    override func main() {
        
        contextCreator?.performBackgroundTaskAndWait(flowId: flowId) { obvContext in
            
            let cachedWellKnowns: [CachedWellKnown]
            do {
                cachedWellKnowns = try CachedWellKnown.getAllCachedWellKnown(within: obvContext)
            } catch {
                return self.cancel(withReason: .coreDataError(error: error))
            }
            
            let currentServers = Set(ownedIdentities.map({ $0.serverURL }))

            for cachedWellKnown in cachedWellKnowns {
                if !currentServers.contains(cachedWellKnown.serverURL) {
                    obvContext.delete(cachedWellKnown)
                }
            }
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
                        
        }
        
    }

}
