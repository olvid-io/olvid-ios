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
import ObvTypes
import ObvUICoreData


final class SetTimestampAllAttachmentsSentIfPossibleOfPersistedMessageSentRecipientInfosOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
 

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: SetTimestampAllAttachmentsSentIfPossibleOfPersistedMessageSentRecipientInfosOperation.self))

    private let ownedCryptoId: ObvCryptoId
    private let messageIdentifiersFromEngine: [Data]
    
    init(ownedCryptoId: ObvCryptoId, messageIdentifiersFromEngine: [Data]) {
        self.ownedCryptoId = ownedCryptoId
        self.messageIdentifiersFromEngine = messageIdentifiersFromEngine
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            for messageIdentifierFromEngine in messageIdentifiersFromEngine {
                
                let infos = try PersistedMessageSentRecipientInfos.getAllPersistedMessageSentRecipientInfos(messageIdentifierFromEngine: messageIdentifierFromEngine, ownedCryptoId: ownedCryptoId, within: obvContext.context)
                guard !infos.isEmpty else {
                    continue
                }
                
                for info in infos {
                    info.setTimestampAllAttachmentsSentIfPossible()
                }
                
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }

}
