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
import ObvEngine
import ObvCrypto
import OlvidUtils
import ObvUICoreData
import ObvTypes


final class UpdatePersistedMessageSentFromReceivedObvOwnedAttachmentOperation: ContextualOperationWithSpecificReasonForCancel<UpdatePersistedMessageSentFromReceivedObvOwnedAttachmentOperation.ReasonForCancel> {
    
    private let obvOwnedAttachment: ObvOwnedAttachment
    private let obvEngine: ObvEngine
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: UpdatePersistedMessageReceivedFromReceivedObvAttachmentOperation.self))

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
            
            let attachmentFullyReceivedOrCancelledByServer = try persistedObvOwnedIdentity.processObvOwnedAttachmentFromOtherOwnedDevice(obvOwnedAttachment: obvOwnedAttachment)
            
            // If the attachment was fully received, we ask the engine to delete the attachment
            
            if attachmentFullyReceivedOrCancelledByServer {
                let obvEngine = self.obvEngine
                let obvOwnedAttachment = self.obvOwnedAttachment
                let log = self.log
                do {
                    try obvContext.addContextDidSaveCompletionHandler { error in
                        do {
                            try obvEngine.deleteObvAttachment(attachmentNumber: obvOwnedAttachment.number, ofMessageWithIdentifier: obvOwnedAttachment.messageIdentifier, ownedCryptoId: obvOwnedAttachment.ownedCryptoId)
                        } catch {
                            os_log("Call to the engine method deleteObvAttachment did fail", log: log, type: .fault)
                            assertionFailure()
                        }
                    }
                } catch {
                    assertionFailure(error.localizedDescription)
                }
                
            }
            
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

