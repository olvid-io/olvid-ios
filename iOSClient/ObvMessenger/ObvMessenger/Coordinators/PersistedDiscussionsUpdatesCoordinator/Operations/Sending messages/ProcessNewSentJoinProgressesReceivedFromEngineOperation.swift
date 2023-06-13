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
import os.log
import CoreData
import OlvidUtils
import ObvTypes
import ObvUICoreData


final class ProcessNewSentJoinProgressesReceivedFromEngineOperation: Operation {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: MarkReceivedJoinAsResumedOrPausedOperation.self))

    private let progresses: [(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int, progress: Float)]

    init(progresses: [(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int, progress: Float)]) {
        self.progresses = progresses
        super.init()
    }

    override func main() {

        ObvStack.shared.performBackgroundTaskAndWait { context in
            
            for progress in progresses {

                let persistedMessageSent: PersistedMessageSent
                do {
                    let infos = try PersistedMessageSentRecipientInfos.getAllPersistedMessageSentRecipientInfos(
                        messageIdentifierFromEngine: progress.messageIdentifierFromEngine,
                        ownedCryptoId: progress.ownedCryptoId,
                        within: context)
                    guard !infos.isEmpty else { return }
                    persistedMessageSent = infos.first!.messageSent
                } catch {
                    assertionFailure()
                    return
                }
                
                guard progress.attachmentNumber < persistedMessageSent.fyleMessageJoinWithStatuses.count else { assertionFailure(); continue }
                
                let fyleMessageJoinWithStatuses = persistedMessageSent.fyleMessageJoinWithStatuses[progress.attachmentNumber]
                
                guard fyleMessageJoinWithStatuses.status != .complete else { continue }
                
                let joinWithObjectID = (fyleMessageJoinWithStatuses as FyleMessageJoinWithStatus).typedObjectID
                Task {
                    await FyleMessageJoinWithStatus.setProgressTo(progress.progress, forJoinWithObjectID: joinWithObjectID)
                }

            }
            
        }

    }
}
