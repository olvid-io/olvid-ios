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


final class GetOrCreateProfileBackupThreadUIDForOwnedCryptoIdOperation: ContextualOperationWithSpecificReasonForCancel<GetOrCreateProfileBackupThreadUIDForOwnedCryptoIdOperation.ReasonForCancel>, @unchecked Sendable {

    private let ownedCryptoId: ObvCryptoId
    private let prng: any PRNGService
    
    init(ownedCryptoId: ObvCryptoId, prng: any PRNGService) {
        self.ownedCryptoId = ownedCryptoId
        self.prng = prng
        super.init()
    }
    
    private(set) var profileBackupThreadUID: UID?
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            profileBackupThreadUID = try PersistedProfileBackupThreadId.getOrCreateProfileBackupThreadUIDForOwnedCryptoId(ownedCryptoId, prng: prng, within: obvContext.context)
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
