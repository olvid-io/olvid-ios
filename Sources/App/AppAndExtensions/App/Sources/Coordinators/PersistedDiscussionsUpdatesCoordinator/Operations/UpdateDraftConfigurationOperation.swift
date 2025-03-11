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

final class UpdateDraftConfigurationOperation: ContextualOperationWithSpecificReasonForCancel<UpdateDraftConfigurationOperationReasonForCancel>, @unchecked Sendable {

    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: UpdateDraftConfigurationOperation.self))

    let value: PersistedDiscussionSharedConfigurationValue?
    let draftObjectID: TypeSafeManagedObjectID<PersistedDraft>

    init(value: PersistedDiscussionSharedConfigurationValue?, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        self.value = value
        self.draftObjectID = draftObjectID
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            guard let draft = try PersistedDraft.get(objectID: draftObjectID, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindDraft)
            }
            draft.update(with: value)
            let draftObjectID = self.draftObjectID
            try obvContext.addContextDidSaveCompletionHandler { error in
                guard error == nil else { return }
                ObvMessengerInternalNotification.draftExpirationWasBeenUpdated(persistedDraftObjectID: draftObjectID).postOnDispatchQueue()
            }
        } catch(let error) {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }

}

enum UpdateDraftConfigurationOperationReasonForCancel: LocalizedErrorWithLogType {

    case contextIsNil
    case coreDataError(error: Error)
    case couldNotFindDraft

    var logType: OSLogType {
        switch self {
        case .coreDataError, .contextIsNil:
            return .fault
        case .couldNotFindDraft:
            return .error
        }
    }

    var errorDescription: String? {
        switch self {
        case .contextIsNil: return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindDraft:
            return "Could not find draft in database"
        }
    }


}
