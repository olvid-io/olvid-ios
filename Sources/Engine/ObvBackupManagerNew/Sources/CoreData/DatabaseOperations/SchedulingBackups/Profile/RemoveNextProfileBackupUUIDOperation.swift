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


final class RemoveNextProfileBackupUUIDOperation: ContextualOperationWithSpecificReasonForCancel<RemoveNextProfileBackupUUIDOperation.ReasonForCancel>, @unchecked Sendable {
    
    private let ownedCryptoId: ObvCryptoId
    private let uuidToRemove: UUID
    
    init(uuidToRemove: UUID, ownedCryptoId: ObvCryptoId) {
        self.uuidToRemove = uuidToRemove
        self.ownedCryptoId = ownedCryptoId
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            try PersistedProfileBackupThreadId.removeNextBackupUUIDIfEqualTo(uuid: uuidToRemove, ownedCryptoId: ownedCryptoId, within: obvContext.context)
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

