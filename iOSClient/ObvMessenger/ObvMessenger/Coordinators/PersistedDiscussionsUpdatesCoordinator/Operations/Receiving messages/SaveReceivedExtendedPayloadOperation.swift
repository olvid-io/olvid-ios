/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import os.log
import ObvEngine
import ObvEncoder
import ObvUICoreData


final class SaveReceivedExtendedPayloadOperation: ContextualOperationWithSpecificReasonForCancel<SaveReceivedExtendedPayloadOperationReasonForCancel> {

    private let extractReceivedExtendedPayloadOp: ExtractReceivedExtendedPayloadOperation

    init(extractReceivedExtendedPayloadOp: ExtractReceivedExtendedPayloadOperation) {
        self.extractReceivedExtendedPayloadOp = extractReceivedExtendedPayloadOp
        super.init()
    }
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        guard let attachementImages = extractReceivedExtendedPayloadOp.attachementImages else {
            return cancel(withReason: .downsizedImagesIsNil)
        }

        let obvMessage = extractReceivedExtendedPayloadOp.obvMessage

        obvContext.performAndWait {

            do {
                guard let message = try PersistedMessageReceived.get(messageIdentifierFromEngine: obvMessage.messageIdentifierFromEngine, from: obvMessage.fromContactIdentity, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindReceivedMessageInDatabase)
                }

                var permanentIDOfMessageToRefreshInViewContext: ObvManagedObjectPermanentID<PersistedMessageReceived>? = nil
                
                for attachementImage in attachementImages {
                    let attachmentNumber = attachementImage.attachmentNumber
                    guard attachmentNumber < message.fyleMessageJoinWithStatuses.count else {
                        return cancel(withReason: .unexpectedAttachmentNumber)
                    }

                    guard case .data(let data) = attachementImage.dataOrURL else {
                        continue
                    }

                    let fyleMessageJoinWithStatus = message.fyleMessageJoinWithStatuses[attachmentNumber]

                    if fyleMessageJoinWithStatus.setDownsizedThumbnailIfRequired(data: data) {
                        // the setDownsizedThumbnailIfRequired returned true, meaning that the downsized thumbnail has been set. We will need to refresh the message in the view context.
                        permanentIDOfMessageToRefreshInViewContext = message.objectPermanentID
                    }
                }
                
                if let permanentIDOfMessageToRefreshInViewContext {
                    try? obvContext.addContextDidSaveCompletionHandler { error in
                        guard error == nil else { return }
                        ObvStack.shared.viewContext.perform {
                            if let draftInViewContext = ObvStack.shared.viewContext.registeredObjects
                                .filter({ !$0.isDeleted })
                                .first(where: { ($0 as? PersistedMessageReceived)?.objectPermanentID == permanentIDOfMessageToRefreshInViewContext }) {
                                ObvStack.shared.viewContext.refresh(draftInViewContext, mergeChanges: false)
                            }
                        }
                    }
                }
                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
        }
        
    }
    
}

enum SaveReceivedExtendedPayloadOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case contextIsNil
    case coreDataError(error: Error)
    case downsizedImagesIsNil
    case couldNotFindReceivedMessageInDatabase
    case unexpectedAttachmentNumber

    
    var logType: OSLogType {
        switch self {
        case .coreDataError, .contextIsNil:
            return .fault
        case .downsizedImagesIsNil, .couldNotFindReceivedMessageInDatabase, .unexpectedAttachmentNumber:
            return .error
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil: return "Context is nil"
        case .coreDataError(error: let error): return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindReceivedMessageInDatabase: return "Could not find received message in database"
        case .unexpectedAttachmentNumber: return "Unexpected attachment number"
        case .downsizedImagesIsNil: return "Downsized images is nil"
        }
    }

}
