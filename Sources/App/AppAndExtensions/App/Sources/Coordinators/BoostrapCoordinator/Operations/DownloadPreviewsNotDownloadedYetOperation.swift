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
import OlvidUtils
import ObvUICoreData
import ObvEngine
import CoreData

/**
 * Operation used to automatically download attachments that are not downloaded yet when the user is starting from a cold state.
 *  Should be *only* used from the *BootstrapCoordinator*
 */
final class DownloadPreviewsNotDownloadedYetOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    // MARK: attributes - private
    private let obvEngine: ObvEngine
    
    // MARK: methods - Life Cycle
    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        do {
            // Fetch all attachments to download
            let attachmentsToDownload = try FyleMessageJoinWithStatus.getAllPreviewsWithStatusNotDownloaded(within: obvContext.context)
            
            attachmentsToDownload.forEach { attachment in
                guard let ownedCryptoId = attachment.message?.discussion?.ownedIdentity?.cryptoId else { return }
                
                var messageId: Data?
                if let receivedAttachment = attachment as? ReceivedFyleMessageJoinWithStatus {
                    messageId = receivedAttachment.messageIdentifierFromEngine
                } else if let sentAttachment = attachment as? SentFyleMessageJoinWithStatus {
                    messageId = sentAttachment.messageIdentifierFromEngine
                }
                guard let messageId = messageId else { return }
                let attachmentIndex = attachment.index
                Task {
                    do {
                        try await obvEngine.resumeDownloadOfAttachment(attachmentIndex,
                                                                       ofMessageWithIdentifier: messageId,
                                                                       ownedCryptoId: ownedCryptoId)
                    } catch {
                        assertionFailure(error.localizedDescription)
                    }
                }
            }
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
    }
    
    
}
