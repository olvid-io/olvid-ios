/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import OSLog
import ObvAppCoreConstants
import ObvAppTypes
import ObvUICoreData
import OlvidUtils


/// Records the size this draft's photos and videos are to be sent at, and points every one that already has that size at its file.
///
/// An attachment whose file for that size has not been written yet is left alone and picks the choice up when it lands — the choice is
/// recorded here whether or not the files exist, so that the size menu never has to make the reader wait on an encode to express a
/// preference.
final class SetSelectedMediaFormatOfDraftOperation: ContextualOperationWithSpecificReasonForCancel<SetSelectedMediaFormatOfDraftOperationReasonForCancel>, @unchecked Sendable {

    private let draftObjectID: TypeSafeManagedObjectID<PersistedDraft>
    private let format: ObvMediaFormat

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: SetSelectedMediaFormatOfDraftOperation.self))

    init(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, format: ObvMediaFormat) {
        self.draftObjectID = draftObjectID
        self.format = format
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {

        do {

            guard let draft = try PersistedDraft.get(objectID: draftObjectID, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindDraftInDatabase)
            }

            draft.setSelectedMediaFormat(format)

            let numberOfPhotosStillWaiting = draft.photoJoins.filter({ $0.variant(for: format) == nil }).count
            let numberOfVideosStillWaiting = draft.videoJoins.filter({ $0.variant(for: format) == nil }).count
            Self.logger.info("🎬 The draft's media are to be sent at \(self.format.rawValue, privacy: .public); \(numberOfPhotosStillWaiting, privacy: .public) photo(s) and \(numberOfVideosStillWaiting, privacy: .public) video(s) do not have that size yet")

        } catch {
            Self.logger.fault("Could not record the size a draft's media are to be sent at: \(error)")
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }

    }

}


enum SetSelectedMediaFormatOfDraftOperationReasonForCancel: LocalizedErrorWithLogType {

    case contextIsNil
    case coreDataError(error: Error)
    case couldNotFindDraftInDatabase

    var logType: OSLogType {
        switch self {
        case .contextIsNil, .coreDataError:
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
            return "Could not find the draft in database"
        }
    }

}
