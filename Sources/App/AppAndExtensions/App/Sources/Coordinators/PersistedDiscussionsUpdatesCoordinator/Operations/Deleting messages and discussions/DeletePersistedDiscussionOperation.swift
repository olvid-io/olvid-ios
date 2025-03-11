/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import os.log
import OlvidUtils
import ObvUICoreData
import ObvTypes



/// Called when processing the message deletion requested by an owned identity from the current device.
final class DeletePersistedDiscussionOperation: ContextualOperationWithSpecificReasonForCancel<DeletePersistedDiscussionOperation.ReasonForCancel>, @unchecked Sendable {

    private let ownedCryptoId: ObvCryptoId
    private let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
    private let deletionType: DeletionType
    
    
    init(ownedCryptoId: ObvCryptoId, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, deletionType: DeletionType) {
        self.ownedCryptoId = ownedCryptoId
        self.discussionObjectID = discussionObjectID
        self.deletionType = deletionType
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                return cancel(withReason: .cannotFindOwnedIdentity)
            }
            
            try ownedIdentity.processDiscussionDeletionRequestFromCurrentDeviceOfThisOwnedIdentity(discussionObjectID: discussionObjectID, deletionType: deletionType)
            
        } catch {
            assertionFailure(error.localizedDescription)
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {

        case coreDataError(error: Error)
        case contextIsNil
        case cannotFindOwnedIdentity
        
        var logType: OSLogType {
            switch self {
            case .coreDataError, .contextIsNil, .cannotFindOwnedIdentity:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .contextIsNil:
                return "Context is nil"
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .cannotFindOwnedIdentity:
                return "Cannot find owned identity"
            }
        }
        
    }

}
