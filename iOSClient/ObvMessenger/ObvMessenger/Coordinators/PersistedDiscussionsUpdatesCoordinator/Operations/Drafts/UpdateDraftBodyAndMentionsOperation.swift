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


final class UpdateDraftBodyAndMentionsOperation: ContextualOperationWithSpecificReasonForCancel<UpdateDraftBodyAndMentionsOperation.ReasonForCancel> {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: UpdateDraftBodyAndMentionsOperation.self))

    let draftObjectID: TypeSafeManagedObjectID<PersistedDraft>
    let draftBody: String
    let mentions: Set<MessageJSON.UserMention>

    init(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, draftBody: String, mentions: Set<MessageJSON.UserMention>) {
        self.draftObjectID = draftObjectID
        self.draftBody = draftBody
        self.mentions = mentions
        super.init()
    }

    override func main() {
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {
            do {
                
                guard let draft = try PersistedDraft.get(objectID: draftObjectID, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindDraft)
                }
                
                draft.replaceContentWith(newBody: draftBody, newMentions: mentions)

            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
        }
    }

}


extension UpdateDraftBodyAndMentionsOperation {
    enum ReasonForCancel: LocalizedErrorWithLogType {

        case contextIsNil
        case coreDataError(error: Error)
        case couldNotFindDraft

        var logType: OSLogType {
            switch self {
            case .contextIsNil,
                    .coreDataError:
                return .fault
            case .couldNotFindDraft:
                return .error
            }
        }

        var errorDescription: String? {
            switch self {
            case .contextIsNil:
                return "The context is not set"
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindDraft:
                return "Could not find draft in database"
            }
        }
   }
}
