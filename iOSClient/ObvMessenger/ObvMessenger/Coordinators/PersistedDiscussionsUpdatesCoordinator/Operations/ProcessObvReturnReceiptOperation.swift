/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import OlvidUtils

final class ProcessObvReturnReceiptOperation: OperationWithSpecificReasonForCancel<ProcessObvReturnReceiptOperationReasonForCancel> {
 
    private let obvReturnReceipt: ObvReturnReceipt
    private let obvEngine: ObvEngine

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    init(obvReturnReceipt: ObvReturnReceipt, obvEngine: ObvEngine) {
        self.obvReturnReceipt = obvReturnReceipt
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main() {
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            
            // Given the nonce and identity in the receipt, we fetch all the corresponding PersistedMessageSentRecipientInfos
            
            let allMsgSentRcptInfos: Set<PersistedMessageSentRecipientInfos>
            do {
                allMsgSentRcptInfos = try PersistedMessageSentRecipientInfos.get(withNonce: obvReturnReceipt.nonce, ownedIdentity: obvReturnReceipt.identity, within: context)
            } catch let error {
                assertionFailure()
                return cancel(withReason: .coreDataError(error: error))
            }
            
            guard !allMsgSentRcptInfos.isEmpty else {
                return cancel(withReason: .couldNotFindAnyPersistedMessageSentRecipientInfosInDatabase)
            }
            
            for infos in allMsgSentRcptInfos {
                guard let elements = infos.returnReceiptElements else { assertionFailure(); continue }
                let contactCryptoId: ObvCryptoId
                let rawStatus: Int
                do {
                    (contactCryptoId, rawStatus) = try obvEngine.decryptPayloadOfObvReturnReceipt(obvReturnReceipt, usingElements: elements)
                } catch {
                    os_log("Could not decrypt the return receipt encrypted payload: %{public}@", log: log, type: .error, error.localizedDescription)
                    continue
                }
                guard let status = ReturnReceiptJSON.Status(rawValue: rawStatus) else {
                    os_log("Could not parse the status within the return receipt", log: log, type: .error)
                    continue
                }
                guard contactCryptoId == infos.recipientCryptoId else {
                    // The recipient do not concern the contact (but another contact of the discussion), so we continue the for loop
                    continue
                }
                switch status {
                case .delivered:
                    infos.setTimestampDelivered(to: obvReturnReceipt.timestamp)
                case .read:
                    infos.setTimestampRead(to: obvReturnReceipt.timestamp)
                }
                // If we reach this point, we can break out of the loop since we updated an appropriate PersistedMessageSentRecipientInfos
                break
            }
            
            do {
                try context.save(logOnFailure: log)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

        }
        
    }

}


enum ProcessObvReturnReceiptOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case couldNotFindAnyPersistedMessageSentRecipientInfosInDatabase
    
    var logType: OSLogType {
        switch self {
        case .couldNotFindAnyPersistedMessageSentRecipientInfosInDatabase:
            return .error
        case .coreDataError:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .couldNotFindAnyPersistedMessageSentRecipientInfosInDatabase:
            return "Could not find any PersistedMessageSentRecipientInfos for the given return receipt"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        }
    }

}
