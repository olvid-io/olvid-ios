/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import OlvidUtils
import os.log
import CoreData
import ObvUICoreData


/// Operation that saves the body and the mentions of a given draft.
/// The rationale behind using a single operation instead of a combination of two operations is that the mentions is directly linked to the saved body; the mentions' ranges need to be relative to the body
final class SaveBodyTextAndMentionsOfPersistedDraftOperation: ContextualOperationWithSpecificReasonForCancel<SaveBodyTextAndMentionsOfPersistedDraftOperation.ReasonForCancel>, @unchecked Sendable {

    /// The draft's permamnt object ID
    private let draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>
    /// The draft's new body to save
    private let bodyText: String
    /// A collection of mentions to add to the draft
    private let mentions: Set<MessageJSON.UserMention>

    init(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, bodyText: String, mentions: Set<MessageJSON.UserMention>) {
        self.draftPermanentID = draftPermanentID
        self.bodyText = bodyText
        self.mentions = Set(mentions)
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            guard let draft = try PersistedDraft.getManagedObject(withPermanentID: draftPermanentID, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindDraftInDatabase)
            }
            
            draft.replaceContentWith(newBody: bodyText, newMentions: mentions)
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case contextIsNil
        case coreDataError(error: Error)
        case couldNotFindDraftInDatabase

        var logType: OSLogType {
            switch self {
            case .contextIsNil,
                 .coreDataError:
                return .fault
            case .couldNotFindDraftInDatabase:
                return .error
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .contextIsNil:
                return "The context is not set"
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindDraftInDatabase:
                return "Could not find draft in database"
            }
        }

    }

}
