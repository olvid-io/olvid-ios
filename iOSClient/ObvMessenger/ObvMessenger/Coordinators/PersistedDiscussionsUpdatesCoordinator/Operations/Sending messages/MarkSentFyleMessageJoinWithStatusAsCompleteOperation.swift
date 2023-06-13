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
import CoreData
import os.log
import OlvidUtils
import ObvTypes
import ObvUICoreData


/// This operation not only marks the appropriate `SentFyleMessageJoinWithStatus` as complete, it also marks all the appropriate `PersistedAttachmentSentRecipientInfos` as complete too.
final class MarkSentFyleMessageJoinWithStatusAsCompleteOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
 
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: MarkSentFyleMessageJoinWithStatusAsCompleteOperation.self))

    private let ownedCryptoId: ObvCryptoId
    private let messageIdentifierFromEngineAndAttachmentNumbersToRestrictTo: [(messageIdentifierFromEngine: Data, restrictToAttachmentNumbers: [Int]?)]
    
    /// - Parameters:
    ///   - messageIdentifierFromEngine: The message identifier from the engine. If this identifier corresponds to more than one `PersistedMessageSent`, the result of this operation is not properly defined. But this case is very unlikely.
    ///   - restrictToAttachmentNumbers: If `nil`, all attachments are considered. Otherwise, only the specified attachments are considered.
    init(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngineAndAttachmentNumbersToRestrictTo: [(messageIdentifierFromEngine: Data, restrictToAttachmentNumbers: [Int]?)]) {
        self.ownedCryptoId = ownedCryptoId
        self.messageIdentifierFromEngineAndAttachmentNumbersToRestrictTo = messageIdentifierFromEngineAndAttachmentNumbersToRestrictTo
        super.init()
    }

    convenience init(ownedCryptoId: ObvCryptoId, messageIdentifiersFromEngine: [Data]) {
        let messageIdentifierFromEngineAndAttachmentNumbersToRestrictTo: [(messageIdentifierFromEngine: Data, restrictToAttachmentNumbers: [Int]?)] = messageIdentifiersFromEngine.map({ ($0, nil) })
        self.init(ownedCryptoId: ownedCryptoId, messageIdentifierFromEngineAndAttachmentNumbersToRestrictTo: messageIdentifierFromEngineAndAttachmentNumbersToRestrictTo)
    }

    override func main() {
        
        guard let obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {
            
            do {
                
                for (messageIdentifierFromEngine, restrictToAttachmentNumbers) in messageIdentifierFromEngineAndAttachmentNumbersToRestrictTo {
                    
                    let infos = try PersistedMessageSentRecipientInfos.getAllPersistedMessageSentRecipientInfos(messageIdentifierFromEngine: messageIdentifierFromEngine, ownedCryptoId: ownedCryptoId, within: obvContext.context)
                    guard !infos.isEmpty, let persistedMessageSent = infos.first?.messageSent else {
                        continue
                    }
                    
                    let attachmentNumbers: [Int]
                    if let restrictToAttachmentNumbers {
                        attachmentNumbers = restrictToAttachmentNumbers
                    } else {
                        attachmentNumbers = Array(0..<persistedMessageSent.fyleMessageJoinWithStatuses.count)
                    }
                    
                    for attachmentNumber in attachmentNumbers {
                        // Mark all the approprate `PersistedAttachmentSentRecipientInfos` as complete
                        infos.forEach { info in
                            info.attachmentInfos.first(where: { $0.index == attachmentNumber })?.status = .complete
                        }
                        
                        guard attachmentNumber < persistedMessageSent.fyleMessageJoinWithStatuses.count else {
                            assertionFailure()
                            continue
                        }
                        
                        // Mark the appropriate `SentFyleMessageJoinWithStatus` as complete
                        let fyleMessageJoinWithStatus = persistedMessageSent.fyleMessageJoinWithStatuses[attachmentNumber]
                        fyleMessageJoinWithStatus.markAsComplete()
                    }
                    
                } // End of for (messageIdentifierFromEngine, restrictToAttachmentNumbers) in messageIdentifierFromEngineAndAttachmentNumbersToRestrictTo
                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
                
        }

    }

}
