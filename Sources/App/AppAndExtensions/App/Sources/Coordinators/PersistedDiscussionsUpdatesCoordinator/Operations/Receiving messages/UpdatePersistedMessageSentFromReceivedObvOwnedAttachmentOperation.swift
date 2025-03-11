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
import CoreData
import os.log
import ObvEngine
import ObvCrypto
import OlvidUtils
import ObvUICoreData
import ObvTypes
import ObvAppCoreConstants


final class UpdatePersistedMessageSentFromReceivedObvOwnedAttachmentOperation: ContextualOperationWithSpecificReasonForCancel<UpdatePersistedMessageSentFromReceivedObvOwnedAttachmentOperation.ReasonForCancel>, @unchecked Sendable {
    
    private let obvOwnedAttachment: ObvOwnedAttachment
    private let obvEngine: ObvEngine
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: UpdatePersistedMessageReceivedFromReceivedObvAttachmentOperation.self))

    init(obvOwnedAttachment: ObvOwnedAttachment, obvEngine: ObvEngine) {
        self.obvOwnedAttachment = obvOwnedAttachment
        self.obvEngine = obvEngine
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            // Grab the persisted owned identity who sent the message on another owned device
            
            guard let persistedObvOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: obvOwnedAttachment.ownedCryptoId, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindOwnedIdentityInDatabase)
            }
            
            // Update the attachment sent by this owned identity on another of her owned devices
            
            try persistedObvOwnedIdentity.processObvOwnedAttachmentFromOtherOwnedDevice(obvOwnedAttachment: obvOwnedAttachment)
            
        } catch {
            assertionFailure(error.localizedDescription)
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }

 
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case couldNotFindOwnedIdentityInDatabase
        case coreDataError(error: Error)
        case contextIsNil
        
        var logType: OSLogType {
            switch self {
            case .coreDataError, .contextIsNil, .couldNotFindOwnedIdentityInDatabase:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .contextIsNil:
                return "The context is not set"
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindOwnedIdentityInDatabase:
                return "Could not find owned identity of attachment (sent for other owned device) in database"
            }
        }

    }

}

