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

final class RefreshUpdatedObjectsModifiedByShareExtensionOperation: OperationWithSpecificReasonForCancel<RefreshUpdatedObjectsModifiedByShareExtensionOperationReasonForCancel> {

    private let objectURL: URL
    private let entityName: String

    init(objectURL: URL, entityName: String) {
        self.objectURL = objectURL
        self.entityName = entityName
        super.init()
    }

    override func main() {

        guard let objectID = ObvStack.shared.managedObjectID(forURIRepresentation: objectURL) else {
            assertionFailure()
            cancel(withReason: .couldNotFindManagedObjectIDFromURL)
            return
        }

        do {
            try NSManagedObject.refreshObjectInPersistentStore(for: objectID, with: entityName)
        } catch let error {
            cancel(withReason: .coreDataError(error: error))
        }
    }
    
}

enum RefreshUpdatedObjectsModifiedByShareExtensionOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case couldNotFindManagedObjectIDFromURL
    case coreDataError(error: Error)

    var logType: OSLogType {
        switch self {
        case .couldNotFindManagedObjectIDFromURL:
            return .error
        case .coreDataError:
            return .fault
        }
    }

    var errorDescription: String? {
        switch self {
        case .couldNotFindManagedObjectIDFromURL: return "Could not find ManagedObjectID From Message URL"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        }
    }

}
