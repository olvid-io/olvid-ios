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
import ObvCrypto
import OlvidUtils
import ObvTypes
import ObvUICoreData
import ObvAppCoreConstants


/// Operation used to determine which attachments to download and to delete from server when receiving a message from another owned device
final class DetermineAttachmentsProcessingRequestForMessageSentOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    // MARK: attributes - private
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "DetermineAttachmentsProcessingRequestForMessageSentOperation")
    private let kind: Kind

    enum Kind {
        case allAttachmentsOfMessage(messageSentPermanentId: MessageSentPermanentID)
        case specificAttachment(attachmentId: ObvAttachmentIdentifier)
    }

    // MARK: methods - Life Cycle
    init(kind: Kind) {
        self.kind = kind
        super.init()
    }
    
    private(set) var attachmentsProcessingRequest: ObvAttachmentsProcessingRequest?

    // MARK: methods - implementation - ContextualOperationWithSpecificReasonForCancel
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        os_log("Executing a DetermineAttachmentsProcessingRequestForMessageSentOperation", log: log, type: .debug)
                
        do {
            
            let indexesOfAttachmentsToDownload: Set<Int>
            let indexesOfAttachmentsToDelete: Set<Int>

            switch kind {

            case .allAttachmentsOfMessage(messageSentPermanentId: let messageSentPermanentId):

                guard let persistedMessage = try PersistedMessageSent.getManagedObject(withPermanentID: messageSentPermanentId, within: obvContext.context) else {
                    return
                }

                indexesOfAttachmentsToDownload = Set(persistedMessage.fyleMessageJoinWithStatusesToDownload.map(\.index))
                indexesOfAttachmentsToDelete = Set(persistedMessage.fyleMessageJoinWithStatusesFromOtherOwnedDeviceToDeleteFromServer.map(\.index))

            case .specificAttachment(let attachmentId):
                
                guard let persistedMessage = try PersistedMessageSent.get(messageId: attachmentId.messageId, within: obvContext.context) else {
                    return
                }
                
                indexesOfAttachmentsToDownload = Set(persistedMessage.fyleMessageJoinWithStatusesToDownload
                    .map(\.index)
                    .filter({ $0 == attachmentId.attachmentNumber }))
                indexesOfAttachmentsToDelete = Set(persistedMessage.fyleMessageJoinWithStatusesFromOtherOwnedDeviceToDeleteFromServer
                    .map(\.index)
                    .filter({ $0 == attachmentId.attachmentNumber }))

            }

            assert(indexesOfAttachmentsToDownload.intersection(indexesOfAttachmentsToDelete).isEmpty)
            
            var processingKindForAttachmentIndex = [Int: ObvAttachmentsProcessingRequest.ProcessingKind]()

            for index in indexesOfAttachmentsToDownload {
                processingKindForAttachmentIndex[index] = .download
            }

            for index in indexesOfAttachmentsToDelete {
                processingKindForAttachmentIndex[index] = .deleteFromServer
            }

            attachmentsProcessingRequest = .process(processingKindForAttachmentIndex: processingKindForAttachmentIndex)

        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }

    }
}
