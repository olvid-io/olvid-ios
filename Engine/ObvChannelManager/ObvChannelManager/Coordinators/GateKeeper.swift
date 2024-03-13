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
import ObvTypes
import OlvidUtils
import os.log

final class GateKeeper {


    private let readOnly: Bool
    private let slotManager: ObvContextSlotManager


    init(readOnly: Bool) {
        self.readOnly = readOnly
        self.slotManager = ObvContextSlotManager()
    }


    func waitUntilSlotIsAvailableForObvContext(_ obvContext: ObvContext) throws {

        if self.readOnly {

            // If the context is read-only (which is the case when the engine is initialized by the notification extension), we make sure that the context is never saved
            try obvContext.addContextWillSaveCompletionHandler {
                assertionFailure("The channel manager expects this context to be read only")
                return
            }

        } else {

            slotManager.waitUntilSlotIsAvailableForObvContext(obvContext)

        }
    }

}


// MARK: - ObvContextSlotManager

fileprivate final class ObvContextSlotManager {

    private static let log = OSLog(subsystem: ObvObliviousChannel.delegateManager.logSubsystem, category: "ObvContextSlotManager")

    private let semaphore = DispatchSemaphore(value: 1) // Tested

    // 2023-01-25: We remove the sync mechanism around this variable, as it is not required
    private var currentContextInSlot: ObvContext?
    
    func waitUntilSlotIsAvailableForObvContext(_ obvContext: ObvContext) {

        // If the slot is taken by the obvContext we just reaceived (which happens for re-entrant calls), we can return immediately
        
        guard currentContextInSlot != obvContext else {
            return
        }
        
        //assert(Task.currentPriority.rawValue > TaskPriority.medium.rawValue)
        os_log("🚪[%{public}@] Context %{public}@ will wait. Current context in slot: %{public}@", log: Self.log, type: .debug, Task.currentPriority.debugDescription, obvContext.debugDescription, currentContextInSlot?.debugDescription ?? "None")
        
        semaphore.wait()
        
        os_log("🚪 Context %{public}@ will take the slot and continue", log: Self.log, type: .debug, obvContext.debugDescription)

        assert(currentContextInSlot == nil)
        
        currentContextInSlot = obvContext
        
        let contextDescription = obvContext.debugDescription
        
        obvContext.addEndOfScopeCompletionHandler { [weak self] in
            guard let self else { assertionFailure(); return }
            currentContextInSlot = nil
            os_log("🚪 Context %{public}@ will free the slot", log: Self.log, type: .debug, contextDescription)
            semaphore.signal()
            os_log("🚪 Context %{public}@ did free the slot", log: Self.log, type: .debug, contextDescription)
        }

    }

}


private extension TaskPriority {
    
    var debugDescription: String {
        switch self {
        case .background: return "background"
        case .high: return "high"
        case .low: return "low"
        case .medium: return "medium"
        case .userInitiated: return "userInitiated"
        case .utility: return "utility"
        default:
            return "custom<\(self.rawValue)>"
        }
    }
    
}
