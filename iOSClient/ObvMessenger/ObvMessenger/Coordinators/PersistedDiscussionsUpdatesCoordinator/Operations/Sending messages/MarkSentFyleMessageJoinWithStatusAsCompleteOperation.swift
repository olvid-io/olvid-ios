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


/// This operation not only marks the appropriate `SentFyleMessageJoinWithStatus` as complete, it also marks all the appropriate `PersistedAttachmentSentRecipientInfos` as complete too.
final class MarkSentFyleMessageJoinWithStatusAsCompleteOperation: OperationWithSpecificReasonForCancel<MarkSentFyleMessageJoinWithStatusAsCompleteOperationReasonForCancel> {
 
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: MarkSentFyleMessageJoinWithStatusAsCompleteOperation.self))

    private let messageIdentifierFromEngine: Data
    private let attachmentNumber: Int
    
    init(messageIdentifierFromEngine: Data, attachmentNumber: Int) {
        self.messageIdentifierFromEngine = messageIdentifierFromEngine
        self.attachmentNumber = attachmentNumber
        super.init()
    }
    
    override func main() {
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            
            let persistedMessageSent: PersistedMessageSent
            do {
                let infos = try PersistedMessageSentRecipientInfos.getAllPersistedMessageSentRecipientInfos(messageIdentifierFromEngine: messageIdentifierFromEngine, within: context)
                guard !infos.isEmpty else {
                    return cancel(withReason: .couldNotFindPersistedMessageSentRecipientInfos)
                }
                // Mark all the approprate `PersistedAttachmentSentRecipientInfos` as complete
                infos.forEach { info in
                    info.attachmentInfos.first(where: { $0.index == attachmentNumber })?.status = .complete
                }
                persistedMessageSent = infos.first!.messageSent
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            guard attachmentNumber < persistedMessageSent.fyleMessageJoinWithStatuses.count else {
                return cancel(withReason: .noSentFyleMessageJoinWithStatusCorrespondingToReceivedAttachmentNumber)
            }
            
            // Mark the appropriate `SentFyleMessageJoinWithStatus` as complete
            let fyleMessageJoinWithStatus = persistedMessageSent.fyleMessageJoinWithStatuses[attachmentNumber]
            fyleMessageJoinWithStatus.markAsComplete()
            
            do {
                try context.save(logOnFailure: log)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

        }

    }

}


enum MarkSentFyleMessageJoinWithStatusAsCompleteOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case couldNotFindPersistedMessageSentRecipientInfos
    case noSentFyleMessageJoinWithStatusCorrespondingToReceivedAttachmentNumber
    case coreDataError(error: Error)
    
    var logType: OSLogType {
        switch self {
        case .couldNotFindPersistedMessageSentRecipientInfos:
            return .error
        case .coreDataError,
             .noSentFyleMessageJoinWithStatusCorrespondingToReceivedAttachmentNumber:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .couldNotFindPersistedMessageSentRecipientInfos:
            return "Could not find persisted message sent recipient infos for given message identifier from engine"
        case .noSentFyleMessageJoinWithStatusCorrespondingToReceivedAttachmentNumber:
            return "There is no SentFyleMessageJoinWithStatus corresponding to the received engine attachment number"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        }
    }
    
}
