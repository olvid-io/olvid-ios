/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
@preconcurrency import ObvCoreDataStack
import OlvidUtils


public actor ObvAppInboxStack {

    nonisolated(unsafe) private static var _shared: CoreDataStack<ObvAppInboxPersistentContainer>!
    
    public static func initSharedInstance(transactionAuthor: String, runningLog: RunningLogError, enableMigrations: Bool, deleteStoreOnFailure: Bool) throws {
        guard _shared == nil else { return }
        let manager = DataMigrationManagerForObvAppInbox(
            modelName: "ObvAppInboxDataModel",
            storeName: "ObvAppInboxDataModel",
            transactionAuthor: transactionAuthor,
            enableMigrations: enableMigrations,
            migrationRunningLog: runningLog)
        do {
            try manager.initializeCoreDataStack()
        } catch {
            // In the particular case of the ObvAppInboxDataModel, we delete the store in case it fails to initializer (e.g., because of a migration error)
            try manager.deleteStore()
            try manager.initializeCoreDataStack()
        }
        _shared = manager.coreDataStack
        _ = shared.viewContext
    }
    
    public static let shared: CoreDataStack<ObvAppInboxPersistentContainer> = {
        guard _shared != nil else {
            fatalError("initSharedInstance() has not been called or was not successful")
        }
        return _shared!
    }()
    
}
