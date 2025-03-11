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
import ObvUICoreData
import ObvAppCoreConstants


final class WipeExpiredMessagesOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: WipeExpiredMessagesOperation.self))

    let launchedByBackgroundTask: Bool
    
    init(launchedByBackgroundTask: Bool) {
        self.launchedByBackgroundTask = launchedByBackgroundTask
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        var infos = [InfoAboutWipedOrDeletedPersistedMessage]()
        
        // Deal with sent messages
        
        do {
            let now = Date()
            let expiredMessages = try PersistedMessageSent.getSentMessagesThatExpired(before: now, within: obvContext.context)
            for message in expiredMessages {
                if let expirationForSentLimitedExistence = message.expirationForSentLimitedExistence, expirationForSentLimitedExistence.expirationDate < now {
                    let info = try message.deleteExpiredMessage()
                    infos += [info]
                } else if let expirationForSentLimitedVisibility = message.expirationForSentLimitedVisibility, expirationForSentLimitedVisibility.expirationDate < now {
                    do {
                        let info = try message.wipeOrDeleteExpiredMessageSent()
                        infos += [info]
                    } catch {
                        os_log("Could not wipe a message sent with expired visibility", log: log, type: .fault)
                        assertionFailure()
                        // Continue anyway
                    }
                } else {
                    assertionFailure("A message that we fetched because it expired has not expiration before now. Weird.")
                }
            }
        } catch {
            cancel(withReason: .coreDataError(error: error))
            return
        }
        
        // Deal with received messages
        
        do {
            let expiredMessages = try PersistedMessageReceived.getReceivedMessagesThatExpired(within: obvContext.context)
            for message in expiredMessages {
                let info = try message.deleteExpiredMessage()
                infos += [info]
            }
        } catch {
            cancel(withReason: .coreDataError(error: error))
            return
        }
        
        // Notify on context save
        
        do {
            if !infos.isEmpty {
                try obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else { return }
                    // We wiped/deleted some persisted messages. We notify about that.
                    
                    InfoAboutWipedOrDeletedPersistedMessage.notifyThatMessagesWereWipedOrDeleted(infos)
                    
                    // Refresh objects in the view context
                    
                    if let viewContext = self.viewContext {
                        InfoAboutWipedOrDeletedPersistedMessage.refresh(viewContext: viewContext, infos)
                    }
                }
            }
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
