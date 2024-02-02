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
import UserNotifications
import ObvUICoreData
import ObvSettings


/// After too many wrong passcode attempts, we wipe all read once and limited visibility messages until now, if the user decided to choose this option. This wipe is performed by this operation.
///
/// Two possible `WipeType` are possible:
/// - `startWipeFromAppOrShareExtension`: generally used right after too many wrong passcode attempts, either from the share extension and the main app.
/// - `finishIfRequiredWipeStartedByAnExtension`: called from the main app to finish a prior wipe operation performed by the share extension, but that was aborted early due to a lack of processing time.
final class WipeAllReadOnceAndLimitedVisibilityMessagesAfterLockOutOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: WipeAllReadOnceAndLimitedVisibilityMessagesAfterLockOutOperation.self))
    
    enum WipeType {
        case startWipeFromAppOrShareExtension
        case finishIfRequiredWipeStartedByAnExtension
    }
    
    private let userDefaults: UserDefaults?
    private let appType: ObvUICoreDataConstants.AppType
    private let wipeType: WipeType
    
    @Atomic() var earlyAbortWipe: Bool = false {
        didSet {
            assert(appType.wipeCanBeAborted)
        }
    }
    
    init(userDefaults: UserDefaults?, appType: ObvUICoreDataConstants.AppType, wipeType: WipeType) {
        self.userDefaults = userDefaults
        self.appType = appType
        self.wipeType = wipeType
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        // If this operation was launched to finish a wipe started by the share extension, we make sure there is indeed a wipe to finish. This is the case iff `userDefaults.getExtensionFailedToWipeAllEphemeralMessagesBeforeDate` is non-nil. Indeed, if a wipe was start, but not finished, by the share extension, this user defaults variable was necessarily set.
        
        switch wipeType {
            
        case .startWipeFromAppOrShareExtension:
            
            guard ObvMessengerSettings.Privacy.lockoutCleanEphemeral else { return }
            
        case .finishIfRequiredWipeStartedByAnExtension:
            
            guard userDefaults?.getExtensionFailedToWipeAllEphemeralMessagesBeforeDate != nil else {
                return
            }
            
        }
        
        do {
            
            // Determine the date until which read-once and limited visibility messages must be wiped
            
            let timestampOfLastMessageToWipe: Date
            
            switch wipeType {
                
            case .startWipeFromAppOrShareExtension:
                
                // Get the latest message to wipe in order to get its date
                
                let dateSent = try PersistedMessageSent.getDateOfLatestSentMessageWithLimitedVisibilityOrReadOnce(within: obvContext.context)
                let dateReceived = try PersistedMessageReceived.getDateOfLatestReceivedMessageWithLimitedVisibilityOrReadOnce(within: obvContext.context)
                
                guard dateSent != nil || dateReceived != nil else {
                    // No message to wipe, we are done
                    return
                }
                
                timestampOfLastMessageToWipe = max(dateSent ?? .distantPast, dateReceived ?? .distantPast)
                
            case .finishIfRequiredWipeStartedByAnExtension:
                
                // When the share extension starts a wipe without finishing it, it sets a date in the user defaults. This date corresponds to the date of the last message to wipe.
                // We will use this date here to wipe this message and all those (read-once and with limited visibility) with an earlier date. This makes it possible to preserve messages that may have arrived after this message.
                
                guard let date = userDefaults?.getExtensionFailedToWipeAllEphemeralMessagesBeforeDate else {
                    assertionFailure()
                    return
                }
                timestampOfLastMessageToWipe = date
                
            }
            
            // If we reach this point, we must wipe read-once and limited visibility messages until the date specified in `wipeMessageUntilDate`.
            
            var messagesToDelete = [PersistedMessage]()
            
            if !earlyAbortWipe {
                messagesToDelete += try PersistedMessageSent.getAllReadOnceAndLimitedVisibilitySentMessagesToDelete(until: timestampOfLastMessageToWipe, within: obvContext.context)
            }
            
            if !earlyAbortWipe {
                messagesToDelete += try PersistedMessageReceived.getAllReadOnceAndLimitedVisibilityReceivedMessagesToDelete(until: timestampOfLastMessageToWipe, within: obvContext.context)
            }
            
            // Wipe messages
            
            var infos = [InfoAboutWipedOrDeletedPersistedMessage]()
            for message in messagesToDelete {
                guard !earlyAbortWipe else { break }
                do {
                    let info = try message.deleteExpiredMessage()
                    infos += [info]
                } catch {
                    assertionFailure(error.localizedDescription)
                    // In production, continue anyway
                }
            }
            
            // If the wipe was aborted early, we want to set an appropriate date in the user defaults. If not, we want to remove any prior date from the user defaults
            
            let userDefaults = self.userDefaults
            let earlyAbortWipe = self.earlyAbortWipe
            try obvContext.addContextDidSaveCompletionHandler { error in
                guard error == nil else { return }
                // The following dispatch queue allows to make sure we do not create a deadlock by modifying the user defaults:
                // Since these defaults are observed by a coordinator that launches this operation again, we want to make sure the value changes on an independent queue.
                DispatchQueue(label: "Queue created in WipeAllReadOnceAndLimitedVisibilityMessagesAfterLockOutOperation").async {
                    if earlyAbortWipe {
                        userDefaults?.setExtensionFailedToWipeAllEphemeralMessagesBeforeDate(with: timestampOfLastMessageToWipe)
                    } else {
                        userDefaults?.setExtensionFailedToWipeAllEphemeralMessagesBeforeDate(with: nil)
                    }
                }
            }
            
            // If we indeed deleted at least one message, we must refresh the view context
            
            if !infos.isEmpty {
                let viewContext = self.viewContext
                try obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else { return }
                    // We deleted some persisted messages. We notify about that.
                    
                    InfoAboutWipedOrDeletedPersistedMessage.notifyThatMessagesWereWipedOrDeleted(infos)
                    
                    // Refresh objects in the view context
                    
                    if let viewContext = viewContext {
                        InfoAboutWipedOrDeletedPersistedMessage.refresh(viewContext: viewContext, infos)
                    }
                }
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}

fileprivate extension ObvUICoreDataConstants.AppType {
    var wipeCanBeAborted: Bool {
        switch self {
        case .mainApp:
            return false
        case .shareExtension:
            return true
        case .notificationExtension:
            return false
        }
    }
}
