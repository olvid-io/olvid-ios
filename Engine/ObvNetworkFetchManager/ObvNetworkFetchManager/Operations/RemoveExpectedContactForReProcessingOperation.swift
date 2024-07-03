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
import CoreData
import OlvidUtils
import ObvTypes


/// When a remote identity becomes a contact, we can re-process all ``InboxMessage`` instances that were decrypted using a pre-key, sent by this remote identity (which is now a contact),
/// and that we put "on hold". The allow re-processing, we remove the "ExpectedContactForReProcessing" from appropriate message, using this operation.
final class RemoveExpectedContactForReProcessingOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let expectedContactsThatAreNowContacts: Set<ObvContactIdentifier>

    init(expectedContactsThatAreNowContacts: Set<ObvContactIdentifier>) {
        self.expectedContactsThatAreNowContacts = expectedContactsThatAreNowContacts
        super.init()
    }
    
    private(set) var didRemoveAtLeastOneExpectedContactForReProcessing = false
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        do {
            for contact in expectedContactsThatAreNowContacts {
                let didRemoveExpectedContactForReProcessing = try InboxMessage.removeExpectedContactForReProcessing(contactIdentifier: contact, within: obvContext.context)
                if didRemoveExpectedContactForReProcessing {
                    didRemoveAtLeastOneExpectedContactForReProcessing = true
                }
            }
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
    }
    
}
