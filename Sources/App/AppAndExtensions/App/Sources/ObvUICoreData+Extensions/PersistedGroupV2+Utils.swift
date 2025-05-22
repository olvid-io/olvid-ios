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
import ObvTypes
import ObvUI
import ObvUICoreData
import CoreData
import ObvAppTypes


extension PersistedGroupV2 {

    
    @MainActor
    func computeChangesetForGroupPhotoAndGroupDetails(with contactGroup: ContactGroup) throws -> ObvGroupV2.Changeset {
        guard let context = self.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        guard context.concurrencyType == .mainQueueConcurrencyType else {
            assertionFailure()
            throw ObvUICoreDataError.inappropriateContext
        }
        var changes = Set<ObvGroupV2.Change>()
        // Augment the changeset with changes made to the group details and photo
        if let change = try computeChangeForGroupDetails(with: contactGroup) {
            changes.insert(change)
        }
        if let change = try computeChangeForGroupPhoto(with: contactGroup) {
            changes.insert(change)
        }
        return try ObvGroupV2.Changeset(changes: changes)
    }

    
    @MainActor private func computeChangeForGroupPhoto(with contactGroup: ContactGroup) throws -> ObvGroupV2.Change? {
        guard let detailsTrusted = self.detailsTrusted else {
            throw ObvUICoreDataError.couldNotGetTrustedGroupDetails
        }
        // Check whether the photo did change.
        let photoURLFromEngine = detailsTrusted.photoURLFromEngine
        let contactGroupPhotoURL = contactGroup.photoURL
        let photoWasChanged = photoURLFromEngine != contactGroupPhotoURL
        // Return a change if necessary
        guard photoWasChanged else { return nil }
        return ObvGroupV2.Change.groupPhoto(photoURL: contactGroupPhotoURL)
    }

    
    @MainActor private func computeChangeForGroupDetails(with contactGroup: ContactGroup) throws -> ObvGroupV2.Change? {
        guard let detailsTrusted = self.detailsTrusted else {
            throw ObvUICoreDataError.couldNotGetTrustedGroupDetails
        }
        // Check whether the core details did change
        let coreDetails = detailsTrusted.coreDetails
        let contactGroupCoreDetails = GroupV2CoreDetails(groupName: contactGroup.name, groupDescription: contactGroup.description)
        let coreDetailsWereChanged = coreDetails != contactGroupCoreDetails
        // Return a change if necessary
        guard coreDetailsWereChanged else { return nil }
        let serializedGroupCoreDetails = try contactGroupCoreDetails.jsonEncode()
        return ObvGroupV2.Change.groupDetails(serializedGroupCoreDetails: serializedGroupCoreDetails)
    }

}
