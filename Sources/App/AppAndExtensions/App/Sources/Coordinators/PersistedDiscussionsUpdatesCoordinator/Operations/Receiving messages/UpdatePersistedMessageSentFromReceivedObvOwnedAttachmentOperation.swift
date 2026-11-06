/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: UpdatePersistedMessageReceivedFromReceivedObvAttachmentOperation.self))

    /// Set when the file the engine reported as complete cannot be used, and saying which way.
    ///
    /// The twin of the property of the same name on `UpdatePersistedMessageReceivedFromReceivedObvAttachmentOperation`, and for the same reasons, which are
    /// written out there. An attachment of a message sent from another owned device is **downloaded** by this device, through the same inbox and the same chunk
    /// machinery as one from a contact, so it fails in the same two ways. Only where it is recorded differs.
    private(set) var whatWasWrongWithTheFile: WhatWasWrongWithADownloadedFile?

    init(obvOwnedAttachment: ObvOwnedAttachment) {
        self.obvOwnedAttachment = obvOwnedAttachment
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
            if let uiCoreDataError = error as? ObvUICoreDataError {
                switch uiCoreDataError {
                case .cannotCreateSentFyleMessageJoinWithStatusForWipedMessage:
                    // The sent message was wiped, we can request a deletion of the attachment from the server.
                    // This will be determined by the `DetermineAttachmentsProcessingRequestOperation` operation.
                    return
                case .couldNotFindSourceFile:
                    // In rare circumstances, the engine might announce a downloaded attachment although there is no file on disk.
                    whatWasWrongWithTheFile = .thereIsNoFileAtAll
                    return cancel(withReason: .coreDataError(error: error))
                case .sha256OfReceivedFileReferenceByObvAttachmentDoesNotMatchWhatWeExpect:
                    // Nothing is done here: see `whatWasWrongWithTheFile`. No assertion either — both of these are handled
                    // conditions now, and a debug build that stops here cannot walk the repair.
                    whatWasWrongWithTheFile = .theFileDoesNotHashAsExpected
                    return cancel(withReason: .coreDataError(error: error))
                default:
                    //assertionFailure(error.localizedDescription)
                    return cancel(withReason: .coreDataError(error: error))
                }
            } else {
                assertionFailure(error.localizedDescription)
                return cancel(withReason: .coreDataError(error: error))
            }
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

