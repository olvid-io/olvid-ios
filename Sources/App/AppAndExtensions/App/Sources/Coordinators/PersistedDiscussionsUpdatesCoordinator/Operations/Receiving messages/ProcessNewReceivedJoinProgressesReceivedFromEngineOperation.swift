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
import os.log
import CoreData
import OlvidUtils
import ObvEngine
import ObvTypes
import ObvUICoreData
import ObvAppCoreConstants


final class ProcessNewReceivedJoinProgressesReceivedFromEngineOperation: Operation, @unchecked Sendable {

    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: MarkReceivedJoinAsResumedOrPausedOperation.self))

    private let progresses: [(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int, progress: Float)]

    init(progresses: [(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int, progress: Float)]) {
        self.progresses = progresses
        super.init()
    }

    override func main() {

        ObvStack.shared.performBackgroundTaskAndWait { context in

            do {
                for progress in progresses {
                    
                    guard let message = try PersistedMessageReceived.get(messageIdentifierFromEngine: progress.messageIdentifierFromEngine,
                                                                         ownedCryptoId: progress.ownedCryptoId,
                                                                         within: context) else {
                        continue
                    }
                    
                    guard let join = message.fyleMessageJoinWithStatuses.first(where: { $0.index == progress.attachmentNumber }) else {
                        assertionFailure()
                        return
                    }
                    
                    guard join.status != .complete else { continue }
                    
                    let joinWithObjectID = (join as FyleMessageJoinWithStatus).typedObjectID
                    Task {
                        await FyleMessageJoinWithStatus.setProgressTo(progress.progress, forJoinWithObjectID: joinWithObjectID)
                    }

                }
            } catch {
                assertionFailure()
                return
            }
            
        }

    }
}
