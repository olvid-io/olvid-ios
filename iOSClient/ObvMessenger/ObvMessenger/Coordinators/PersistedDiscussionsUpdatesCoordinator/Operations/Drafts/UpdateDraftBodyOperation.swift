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


final class UpdateDraftBodyOperation: ContextualOperationWithSpecificReasonForCancel<UpdateDraftBodyOperationReasonForCancel> {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    let value: String
    let draftObjectID: TypeSafeManagedObjectID<PersistedDraft>

    init(value: String, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        self.value = value
        self.draftObjectID = draftObjectID
        super.init()
    }

    override func main() {
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            let draft: PersistedDraft?
            do {
                draft = try PersistedDraft.get(objectID: draftObjectID, within: context)
            } catch(let error) {
                return cancel(withReason: .coreDataError(error: error))
            }
            guard let draft = draft else {
                return cancel(withReason: .couldNotFindDraft)
            }
            draft.setContent(with: value)
            do {
                try context.save(logOnFailure: log)
            } catch(let error) {
                return cancel(withReason: .coreDataError(error: error))
            }
        }
    }

}

enum UpdateDraftBodyOperationReasonForCancel: LocalizedErrorWithLogType {

    case coreDataError(error: Error)
    case couldNotFindDraft

    var logType: OSLogType {
        switch self {
        case .coreDataError:
            return .fault
        case .couldNotFindDraft:
            return .error
        }
    }

    var errorDescription: String? {
        switch self {
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindDraft:
            return "Could not find draft in database"
        }
    }


}
