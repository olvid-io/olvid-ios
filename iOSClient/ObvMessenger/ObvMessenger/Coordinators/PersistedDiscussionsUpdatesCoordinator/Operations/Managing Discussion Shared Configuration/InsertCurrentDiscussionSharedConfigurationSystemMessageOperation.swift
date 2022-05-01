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
import ObvEngine

final class InsertCurrentDiscussionSharedConfigurationSystemMessageOperation: OperationWithSpecificReasonForCancel<InsertUpdatedDiscussionSharedSettingsSystemMessageOperationReasonForCancel> {
    
    let persistedDiscussionObjectID: NSManagedObjectID
    let messageUploadTimestampFromServer: Date?
    let fromContactIdentity: ObvContactIdentity?
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: InsertCurrentDiscussionSharedConfigurationSystemMessageOperation.self))

    init(persistedDiscussionObjectID: NSManagedObjectID, messageUploadTimestampFromServer: Date?, fromContactIdentity: ObvContactIdentity?) {
        self.persistedDiscussionObjectID = persistedDiscussionObjectID
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        self.fromContactIdentity = fromContactIdentity
        super.init()
    }
    
    override func main() {
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in

            let discussion: PersistedDiscussion
            let sharedConfig: PersistedDiscussionSharedConfiguration
            do {
                guard let _discussion = try PersistedDiscussion.get(objectID: persistedDiscussionObjectID, within: context) else {
                    return cancel(withReason: .configCannotBeFound)
                }
                discussion = _discussion
                sharedConfig = discussion.sharedConfiguration
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            let expirationJSON = sharedConfig.toExpirationJSON()

            let contact: PersistedObvContactIdentity?
            if let fromContactIdentity = self.fromContactIdentity {
                guard let _contact = try? PersistedObvContactIdentity.get(persisted: fromContactIdentity, whereOneToOneStatusIs: .any, within: context) else {
                    return cancel(withReason: .inapropriateContact)
                }
                contact = _contact
            } else {
                contact = nil
            }

            do {
                try PersistedMessageSystem.insertUpdatedDiscussionSharedSettingsSystemMessage(within: discussion, optionalContactIdentity: contact, expirationJSON: expirationJSON, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            do {
                try context.save(logOnFailure: log)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

        }
        
    }
    
}


enum InsertUpdatedDiscussionSharedSettingsSystemMessageOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case configCannotBeFound
    case inapropriateContact
    
    var logType: OSLogType {
        switch self {
        case .coreDataError:
            return .fault
        case .configCannotBeFound, .inapropriateContact:
            return .error
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .configCannotBeFound:
            return "Could not find shared configuration in database"
        case .inapropriateContact:
            return "Inapropriate contact"
        }
    }

}
