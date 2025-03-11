/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import Network


public protocol ObvNetworkInterfaceChangeListener: AnyObject {
    func networkInterfaceTypeChanged(isConnected: Bool) async
}


public actor ObvNetworkStatus {
    
    public static let shared = ObvNetworkStatus()
    
    private var networkInterfaceChangeListeners = [ObvNetworkInterfaceChangeListener]()
    
    private let monitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "Queue for monitoring network path changes")
    private var currentInterfaceType: NWInterface.InterfaceType?
    private var currentIsConnectedStatus: Bool
 
    init() {
        currentIsConnectedStatus = (monitor.currentPath.status == .satisfied)
        monitor.pathUpdateHandler = { [weak self] nwPath in
            Task { [weak self] in
                await self?.pathUpdateHandler(nWPath: nwPath)
            }
        }
        monitor.start(queue: networkQueue)
    }
    
    var isConnected: Bool {
        return monitor.currentPath.status == .satisfied
    }
    
    private func pathUpdateHandler(nWPath: NWPath) async {
        let oldType = (currentInterfaceType, currentIsConnectedStatus)
        let newType = (nWPath.availableInterfaces.first?.type, isConnected)
        guard oldType != newType else { return }
        currentInterfaceType = newType.0
        currentIsConnectedStatus = newType.1
        for listener in networkInterfaceChangeListeners {
            Task {
                await listener.networkInterfaceTypeChanged(isConnected: currentIsConnectedStatus)
            }
        }
    }
    
    
    public func addNetworkInterfaceChangeListeners(_ newListener: ObvNetworkInterfaceChangeListener) {
        self.networkInterfaceChangeListeners.append(newListener)
    }
    
}
