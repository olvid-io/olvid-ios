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
import CoreData
import OSLog
import OlvidUtils
import ObvCrypto
import ObvTypes


final class GetDeviceBackupSeedAndServerOperation: ContextualOperationWithSpecificReasonForCancel<CreateNewPersistedDeviceBackupSeedOperation.ReasonForCancel>, @unchecked Sendable {

    private let backupSeed: BackupSeed
    
    init(backupSeed: BackupSeed) {
        self.backupSeed = backupSeed
        super.init()
    }
    
    private(set) var deviceBackupSeedAndServer: ObvBackupSeedAndStorageServerURL?
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            deviceBackupSeedAndServer = try PersistedDeviceBackupSeed.getDeviceBackupSeedAndServer(backupSeed: backupSeed, within: obvContext.context)
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
    public enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)

        public var logType: OSLogType {
            switch self {
            case .coreDataError:
                return .fault
            }
        }

        public var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            }
        }

    }

}
