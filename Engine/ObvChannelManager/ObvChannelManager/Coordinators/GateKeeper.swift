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

    private let semaphore = DispatchSemaphore(value: 1) // Tested

    private let queueForCurrentContextInSlot = DispatchQueue(label: "ObvContextSlotManager queue for context in slot", attributes: [.concurrent])
    private var _currentContextInSlot: ObvContext?
    
    private var currentContextInSlot: ObvContext? {
        get {
            return queueForCurrentContextInSlot.sync { return _currentContextInSlot }
        }
        set {
            queueForCurrentContextInSlot.async(flags: .barrier) { [weak self] in self?._currentContextInSlot = newValue }
        }
    }
    
    
    func waitUntilSlotIsAvailableForObvContext(_ obvContext: ObvContext) {

        // If the slot is taken by the obvContext we just reaceived (which happens for re-entrant calls), we can return immediately
        
        guard currentContextInSlot != obvContext else {
            return
        }
        
        semaphore.wait()
        
        assert(currentContextInSlot == nil)
        
        currentContextInSlot = obvContext
        
        obvContext.addEndOfScopeCompletionHandler { [weak self] in
            assert(self?.currentContextInSlot == obvContext)
            self?.currentContextInSlot = nil
            self?.semaphore.signal()
        }

        
    }

}
