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
import OlvidUtils
import ObvTypes
import ObvUICoreData
import CoreData


/// Called when the user declines a contact suggestion or removes a one-to-one contact, on this device or on another owned device: that contact is
/// never suggested again.
final class StopSuggestingContactOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {

    private let contactIdentifier: ObvContactIdentifier

    /// Whether this operation set the contact aside. Read once the operation is finished.
    private(set) var stopSuggestingWasChangedInDatabase = false

    init(contactIdentifier: ObvContactIdentifier) {
        self.contactIdentifier = contactIdentifier
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        do {
            stopSuggestingWasChangedInDatabase = try PersistedObvContactIdentity.stopSuggesting(
                contactIdentifier: contactIdentifier,
                within: obvContext.context
            )
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
    }

}
