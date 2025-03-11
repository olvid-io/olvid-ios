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
import ObvTypes
import OlvidUtils



final class SaveSignedURLsOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let attachmentId: ObvAttachmentIdentifier
    private let chunkDownloadPrivateUrls: [URL?]
    
    init(attachmentId: ObvAttachmentIdentifier, chunkDownloadPrivateUrls: [URL?]) {
        self.attachmentId = attachmentId
        self.chunkDownloadPrivateUrls = chunkDownloadPrivateUrls
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let attachment = try InboxAttachment.get(attachmentId: attachmentId, within: obvContext) else { return }
            
            if let urls = chunkDownloadPrivateUrls as? [URL] {
                try attachment.setChunksSignedURLs(urls)
            } else {
                attachment.markAsCancelledByServer()
            }

        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
