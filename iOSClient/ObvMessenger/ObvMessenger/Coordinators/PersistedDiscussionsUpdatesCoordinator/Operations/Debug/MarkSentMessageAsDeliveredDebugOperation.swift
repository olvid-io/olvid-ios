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
import ObvTypes
import ObvCrypto

final class MarkSentMessageAsDeliveredDebugOperation: ContextualOperationWithSpecificReasonForCancel<MarkSentMessageAsDeliveredDebugOperationReasonForCancel> {
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        let appropriateDependencies = dependencies.compactMap({ $0 as? CreateUnprocessedPersistedMessageSentFromPersistedDraftOperation })
        guard appropriateDependencies.count == 1, let persistedMessageSentObjectID = appropriateDependencies.first!.persistedMessageSentObjectID else {
            return cancel(withReason: .internalError)
        }
        
        let prng = ObvCryptoSuite.sharedInstance.prngService()

        obvContext.performAndWait {

            do {
                guard let persistedMessageSent = try PersistedMessageSent.getPersistedMessageSent(objectID: persistedMessageSentObjectID, within: obvContext.context) else {
                    return cancel(withReason: .internalError)
                }
                
                // Simulate the sending and reception of the message
                
                for recipientInfos in persistedMessageSent.unsortedRecipientsInfos {
                    let randomMessageIdentifierFromEngine = UID.gen(with: prng).raw
                    let randomNonce = prng.genBytes(count: 16)
                    let randomKey = prng.genBytes(count: 32)
                    recipientInfos.setMessageIdentifierFromEngine(to: randomMessageIdentifierFromEngine,
                                                                  andReturnReceiptElementsTo: (randomNonce, randomKey))
                }

                for recipientInfos in persistedMessageSent.unsortedRecipientsInfos {
                    recipientInfos.setTimestampMessageSent(to: Date())
                }

                for recipientInfos in persistedMessageSent.unsortedRecipientsInfos {
                    recipientInfos.setTimestampDelivered(to: Date())
                }

            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            
        }
        
    }
    
}


enum MarkSentMessageAsDeliveredDebugOperationReasonForCancel: LocalizedErrorWithLogType {

    case coreDataError(error: Error)
    case couldNotFindDiscussion
    case contextIsNil
    case internalError

    var logType: OSLogType {
        switch self {
        case .coreDataError,
             .contextIsNil,
             .internalError:
            return .fault
        case .couldNotFindDiscussion:
            return .error
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .internalError:
            return "Internal error"
        case .contextIsNil:
            return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindDiscussion:
            return "Could not find discussion in database"
        }
    }

    
}
