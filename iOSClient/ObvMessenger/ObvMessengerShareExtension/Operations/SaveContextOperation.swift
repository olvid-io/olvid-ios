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
import OSLog
import OlvidUtils

final class SaveContextOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {

    fileprivate static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: SaveContextOperation.self))

    private let userDefaults: UserDefaults?

    init(userDefaults: UserDefaults?) {
        self.userDefaults = userDefaults
    }

    override func main() {
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        var modifiesObjects = Set<NSManagedObject>()

        do {
            try obvContext.performAndWaitOrThrow {
                modifiesObjects.formUnion(obvContext.context.insertedObjects)
                modifiesObjects.formUnion(obvContext.context.updatedObjects)
                modifiesObjects.formUnion(obvContext.context.deletedObjects)
                modifiesObjects.formUnion(obvContext.context.registeredObjects)

                try obvContext.save(logOnFailure: Self.log)
                os_log("📤 Saving Context done.", log: Self.log, type: .info)
            }
        } catch(let error) {
            return cancel(withReason: .coreDataError(error: error))
        }

        if let userDefaults = self.userDefaults {
            let updatedObjectURLAndEntityName: [(URL, String)] = modifiesObjects.compactMap {
                guard let entityName = $0.entity.name else { assertionFailure(); return nil }
                return ($0.objectID.uriRepresentation(), entityName)
            }
            os_log("📤 Write information about %{public}@ modified object(s) for the app.", log: Self.log, type: .info, String(updatedObjectURLAndEntityName.count))
            userDefaults.addObjectsModifiedByShareExtension(updatedObjectURLAndEntityName)
        }

    }

}
