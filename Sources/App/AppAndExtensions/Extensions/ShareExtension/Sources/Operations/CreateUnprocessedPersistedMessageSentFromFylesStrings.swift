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
import ObvCrypto
import ObvUICoreData
import UniformTypeIdentifiers


final class FyleJoinImpl: FyleJoin {

    var fyle: Fyle?
    let fileName: String
    let contentType: UTType
    let uti: String
    let index: Int
    let fyleObjectID: NSManagedObjectID

    init(fyle: Fyle, fileName: String, contentType: UTType, index: Int) {
        self.fyle = fyle
        self.fyleObjectID = fyle.objectID
        self.fileName = fileName
        self.contentType = contentType
        self.index = index
        self.uti = contentType.identifier
    }
    
}

final class CreateUnprocessedPersistedMessageSentFromFylesAndStrings: ContextualOperationWithSpecificReasonForCancel<CreateUnprocessedPersistedMessageSentFromPersistedDraftOperationReasonForCancel>, @unchecked Sendable, UnprocessedPersistedMessageSentProvider {

    private let body: String?
    private let fyleJoins: [FyleJoin]?
    private let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
    private let log: OSLog

    private(set) var messageSentPermanentID: MessageSentPermanentID?

    init(body: String?, fyleJoins: [FyleJoin]?, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, log: OSLog) {
        self.body = body
        self.fyleJoins = fyleJoins
        self.discussionObjectID = discussionObjectID
        self.log = log
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        let body = body ?? ""
        
        guard let fyleJoins else { return }
        
        do {
            guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectID, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindDiscussion)
            }
            
            let persistedMessageSent = try PersistedMessageSent.createPersistedMessageSentFromShareExtension(
                body: body,
                fyleJoins: fyleJoins,
                discussion: discussion)
            
            do {
                try obvContext.context.obtainPermanentIDs(for: [persistedMessageSent])
            } catch {
                return cancel(withReason: .couldNotObtainPermanentIDForPersistedMessageSent)
            }
            
            self.messageSentPermanentID = try? persistedMessageSent.objectPermanentID
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }

}


enum CreateUnprocessedPersistedMessageSentFromPersistedDraftOperationReasonForCancel: LocalizedErrorWithLogType {

    case contextIsNil
    case couldNotFindDiscussion
    case coreDataError(error: Error)
    case couldNotObtainPermanentIDForPersistedMessageSent

    var logType: OSLogType { .fault }

    var errorDescription: String? {
        switch self {
        case .contextIsNil: return "Context is nil"
        case .couldNotFindDiscussion: return "Cannot find discussion"
        case .coreDataError(error: let error): return "Core Data error: \(error.localizedDescription)"
        case .couldNotObtainPermanentIDForPersistedMessageSent: return "Could not obtain persisted permanent ID for PersistedMessageSent"
        }
    }

}
