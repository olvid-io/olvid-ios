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
import ObvCrypto
import ObvTypes
import OlvidUtils

final class PollingWorker {
    
    fileprivate let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "PollingWorker"
    
    weak var delegateManager: ObvNetworkFetchDelegateManager?

    // An identity is registered to poll notifications iff it is present in this dictionary.
    private var pollingIdentifierForIdentity = [ObvCryptoIdentity: UUID]()
    private let dispatchQueueForPolling = DispatchQueue(label: "io.olvid.network.fetch.coordinators.NetworkFetchFlowCoordinator.dispatchQueueForPolling", qos: .default)

    
}

// MARK: - Polling

extension PollingWorker {
    
    func pollingRequested(for identity: ObvCryptoIdentity, withPollingIdentifier pollingIdentifier: UUID) {
        pollingIdentifierForIdentity[identity] = pollingIdentifier
    }
    
    func pollingIfRequired(for identity: ObvCryptoIdentity, withDeviceUid deviceUid: UID, flowId: FlowIdentifier) {
        
        guard let pollingIdentifier = pollingIdentifierForIdentity[identity] else { return }
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The Context Creator is not set", log: log, type: .fault)
            return
        }
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            guard let pollingTimeInterval = RegisteredPushNotification.getPollingTimeInterval(for: identity, pollingIdentifier: pollingIdentifier, within: obvContext) else {
                pollingIdentifierForIdentity.removeValue(forKey: identity)
                os_log("No more polling for identity %@", log: log, type: .debug, identity.debugDescription)
                return
            }
            
            os_log("Polling for identity %@", log: log, type: .debug, identity.debugDescription)
            
            dispatchQueueForPolling.asyncAfter(deadline: .now() + .seconds(Int(pollingTimeInterval))) {
                delegateManager.messagesDelegate.downloadMessagesAndListAttachments(for: identity, andDeviceUid: deviceUid, flowId: flowId)
            }
        }
        
    }
}
