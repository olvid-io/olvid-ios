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
import CoreDataStack
import OlvidUtils

final class ObvStack {

    private static let errorDomain = "ObvStack"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    private static var _shared: CoreDataStack<ObvMessengerPersistentContainer>!
    
    static func initSharedInstance(transactionAuthor: String, runningLog: RunningLogError, enableMigrations: Bool) throws {
        guard _shared == nil else { return }
        let manager = DataMigrationManagerForObvMessenger(modelName: "ObvMessenger", storeName: "ObvMessenger", transactionAuthor: transactionAuthor, enableMigrations: enableMigrations, migrationRunningLog: runningLog)
        try manager.initializeCoreDataStack()
        _shared = manager.coreDataStack
        _ = shared.viewContext
    }
    
    static let shared: CoreDataStack<ObvMessengerPersistentContainer> = {
        guard _shared != nil else {
            fatalError("initSharedInstance() has not been called or was not successful")
        }
        return _shared!
    }()
    
}
