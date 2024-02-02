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


final class UpdatePersistedMessageReceivedFromReceivedObvAttachmentOperation: ContextualOperationWithSpecificReasonForCancel<UpdatePersistedMessageReceivedFromReceivedObvAttachmentOperation.ReasonForCancel> {
    
    private let obvAttachment: ObvAttachment
    private let obvEngine: ObvEngine
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: UpdatePersistedMessageReceivedFromReceivedObvAttachmentOperation.self))

    init(obvAttachment: ObvAttachment, obvEngine: ObvEngine) {
        self.obvAttachment = obvAttachment
        self.obvEngine = obvEngine
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            // Grab the persisted contact who sent the message
            
            guard let persistedContactIdentity = try PersistedObvContactIdentity.get(persisted: obvAttachment.fromContactIdentity, whereOneToOneStatusIs: .any, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindPersistedObvContactIdentityInDatabase)
            }
            
            // Update the attachment sent by this contact
            
            let attachmentFullyReceivedOrCancelledByServer: Bool
            do {
                attachmentFullyReceivedOrCancelledByServer = try persistedContactIdentity.process(obvAttachment: obvAttachment)
            } catch {
                // In rare circumstances, the engine might announce a downloaded attachment although there is no file on disk.
                // In that case, we request a re-download of the attachments.
                if let error = error as? ObvUICoreData.Fyle.ObvError, error == .couldNotFindSourceFile {
                    try? obvEngine.resumeDownloadOfAttachment(obvAttachment.number,
                                                              ofMessageWithIdentifier: obvAttachment.messageIdentifier,
                                                              ownedCryptoId: obvAttachment.fromContactIdentity.ownedCryptoId,
                                                              forceResume: true)
                }
                throw error
            }
            
            // If the attachment was fully received, we ask the engine to delete the attachment
            
            if attachmentFullyReceivedOrCancelledByServer {
                let obvEngine = self.obvEngine
                let obvAttachment = self.obvAttachment
                let log = self.log
                do {
                    try obvContext.addContextDidSaveCompletionHandler { error in
                        do {
                            try obvEngine.deleteObvAttachment(attachmentNumber: obvAttachment.number, ofMessageWithIdentifier: obvAttachment.messageIdentifier, ownedCryptoId: obvAttachment.fromContactIdentity.ownedCryptoId)
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
        
        case couldNotFindPersistedObvContactIdentityInDatabase
        case coreDataError(error: Error)
        case contextIsNil
        
        var logType: OSLogType {
            switch self {
            case .coreDataError, .contextIsNil, .couldNotFindPersistedObvContactIdentityInDatabase:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .contextIsNil:
                return "The context is not set"
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindPersistedObvContactIdentityInDatabase:
                return "Could not find contact identity of received message in database"
            }
        }

    }

}
