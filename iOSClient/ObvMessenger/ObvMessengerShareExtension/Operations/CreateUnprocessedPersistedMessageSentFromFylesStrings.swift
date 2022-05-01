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
import ObvCrypto

final class FyleJoinImpl: FyleJoin {

    var fyle: Fyle?
    let fileName: String
    let uti: String
    let index: Int
    let fyleObjectID: NSManagedObjectID

    init(fyle: Fyle, fileName: String, uti: String, index: Int) {
        self.fyle = fyle
        self.fyleObjectID = fyle.objectID
        self.fileName = fileName
        self.uti = uti
        self.index = index
    }
}

final class CreateUnprocessedPersistedMessageSentFromFylesAndStrings: ContextualOperationWithSpecificReasonForCancel<CreateUnprocessedPersistedMessageSentFromPersistedDraftOperationReasonForCancel>, UnprocessedPersistedMessageSentProvider {

    private let body: String?
    private let fyleJoinsProvider: FyleJoinsProvider
    private let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
    private let log: OSLog

    private(set) var persistedMessageSentObjectID: TypeSafeManagedObjectID<PersistedMessageSent>?

    init(body: String?, fyleJoinsProvider: FyleJoinsProvider, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, log: OSLog) {
        self.body = body
        self.fyleJoinsProvider = fyleJoinsProvider
        self.discussionObjectID = discussionObjectID
        self.log = log
        super.init()
    }

    override func main() {
        assert(fyleJoinsProvider.isFinished)

        let body = body ?? ""

        guard let fyleJoins = fyleJoinsProvider.fyleJoins else { return }

        guard let obvContext = self.obvContext else {
            cancel(withReason: .contextIsNil)
            return
        }

        obvContext.performAndWait {
            do {
                guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectID, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindDiscussion)
                }

                let persistedMessageSent = try PersistedMessageSent(body: body, replyTo: nil, fyleJoins: fyleJoins, discussion: discussion, readOnce: false, visibilityDuration: nil, existenceDuration: nil)

                do {
                    try obvContext.context.obtainPermanentIDs(for: [persistedMessageSent])
                } catch {
                    return cancel(withReason: .couldNotObtainPermanentIDForPersistedMessageSent)
                }

                self.persistedMessageSentObjectID = persistedMessageSent.typedObjectID
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
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
