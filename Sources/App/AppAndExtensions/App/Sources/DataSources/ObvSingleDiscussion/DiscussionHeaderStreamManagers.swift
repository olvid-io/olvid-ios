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
import ObvAppTypes
import ObvSingleDiscussion
import ObvTypes
import ObvUICoreData
import OlvidUtils
import ObvSharedDataSources


/// What the three managers below have in common, so that the data source can keep them in one dictionary.
///
/// They cannot share a superclass: `ObvDataSourceStreamManagerWith*FetchedResultsController` is generic over the *entities* each one watches, and those differ by
/// the kind of discussion — which is the whole reason there are three.
protocol ObvDataSourceStreamManagerForDiscussionHeader: AnyObject, Sendable {
    var streamUUID: UUID { get }
    func startStream() async throws -> (streamUUID: UUID, stream: AsyncStream<ObvSingleDiscussion.DiscussionHeader>)
    func finishStream()
}


// MARK: - One manager per kind of discussion

/// Follows the header of a **one-to-one** discussion: the discussion itself, and the contact it is with.
///
/// Two controllers and not four, which is the point of having one manager per kind: an `ObvDiscussionIdentifier` already says which kind this is, so each manager
/// watches exactly what its own subtitle is made of and nothing else.
///
/// The contact is watched because everything the header says about a one-to-one comes from them — the name, the position at company, the picture — and none of it
/// touches the discussion when it changes.
///
/// The **local configuration** is watched by all three, since step 32b, because that is where a mute lives: setting or clearing one writes to a
/// `PersistedDiscussionLocalConfiguration` and marks neither the discussion nor anything else these controllers hold. It is *not* what makes an expiring mute go
/// away, though — nothing is written then, so nothing can be reported. See `DiscussionUnmuteButton`.
final class OneToOneDiscussionHeaderStreamManager: ObvDataSourceStreamManagerWithThreeFetchedResultsController<ObvSingleDiscussion.DiscussionHeader, PersistedDiscussion, PersistedObvContactIdentity, PersistedDiscussionLocalConfiguration>, @unchecked Sendable, ObvDataSourceStreamManagerForDiscussionHeader {

    init(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, contactIdentifier: ObvContactIdentifier, context: NSManagedObjectContext) {
        let frc1 = PersistedDiscussion.getFetchedResultsController(objectID: discussionObjectID, within: context)
        let frc2 = PersistedObvContactIdentity.getFetchedResultsControllerForContactIdentifier(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: context)
        let frc3 = PersistedDiscussionLocalConfiguration.getFetchedResultsController(persistedDiscussionObjectID: discussionObjectID, within: context)
        super.init(frc1: frc1, frc2: frc2, frc3: frc3)
    }

    override func createModel(fetchedObjects1: [PersistedDiscussion], fetchedObjects2: [PersistedObvContactIdentity], fetchedObjects3: [PersistedDiscussionLocalConfiguration]) throws -> ObvSingleDiscussion.DiscussionHeader {
        guard let discussion = fetchedObjects1.first else { throw ObvError.couldNotFindDiscussion }
        return SingleDiscussionViewAppDataSource.header(of: discussion)
    }

    enum ObvError: Error {
        case couldNotFindDiscussion
    }

}


/// Follows the header of a **group v1** discussion: the discussion, the group, and its members.
///
/// The members have a controller of their own because the subtitle is their names: a member renamed changes an attribute of a `PersistedObvContactIdentity` and
/// touches neither the group nor the discussion, so nothing else would report it.
final class GroupV1DiscussionHeaderStreamManager: ObvDataSourceStreamManagerWithFourFetchedResultsController<ObvSingleDiscussion.DiscussionHeader, PersistedDiscussion, PersistedContactGroup, PersistedObvContactIdentity, PersistedDiscussionLocalConfiguration>, @unchecked Sendable, ObvDataSourceStreamManagerForDiscussionHeader {

    init(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, groupIdentifier: ObvGroupV1Identifier, context: NSManagedObjectContext) {
        let frc1 = PersistedDiscussion.getFetchedResultsController(objectID: discussionObjectID, within: context)
        let frc2 = PersistedContactGroup.getFetchedResultsController(groupV1Identifier: groupIdentifier, within: context)
        let frc3 = PersistedObvContactIdentity.getFetchedResultsControllerForGroupV1(groupIdentifier: groupIdentifier, whereOneToOneStatusIs: .any, within: context)
        let frc4 = PersistedDiscussionLocalConfiguration.getFetchedResultsController(persistedDiscussionObjectID: discussionObjectID, within: context)
        super.init(frc1: frc1, frc2: frc2, frc3: frc3, frc4: frc4)
    }

    override func createModel(fetchedObjects1: [PersistedDiscussion], fetchedObjects2: [PersistedContactGroup], fetchedObjects3: [PersistedObvContactIdentity], fetchedObjects4: [PersistedDiscussionLocalConfiguration]) throws -> ObvSingleDiscussion.DiscussionHeader {
        guard let discussion = fetchedObjects1.first else { throw ObvError.couldNotFindDiscussion }
        return SingleDiscussionViewAppDataSource.header(of: discussion)
    }

    enum ObvError: Error {
        case couldNotFindDiscussion
    }

}


/// Follows the header of a **group v2** discussion: the discussion, the group, and its members.
///
/// The members are `PersistedGroupV2Member` here, and not contacts — a member of a group v2 need not be a contact at all — which is also what the subtitle is
/// built from.
final class GroupV2DiscussionHeaderStreamManager: ObvDataSourceStreamManagerWithFourFetchedResultsController<ObvSingleDiscussion.DiscussionHeader, PersistedDiscussion, PersistedGroupV2, PersistedGroupV2Member, PersistedDiscussionLocalConfiguration>, @unchecked Sendable, ObvDataSourceStreamManagerForDiscussionHeader {

    init(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, groupIdentifier: ObvGroupV2Identifier, context: NSManagedObjectContext) {
        let frc1 = PersistedDiscussion.getFetchedResultsController(objectID: discussionObjectID, within: context)
        let frc2 = PersistedGroupV2.getFetchedResultsController(groupV2Identifier: groupIdentifier, within: context)
        let frc3 = PersistedGroupV2Member.getFetchedResultsController(groupV2Identifier: groupIdentifier, within: context)
        let frc4 = PersistedDiscussionLocalConfiguration.getFetchedResultsController(persistedDiscussionObjectID: discussionObjectID, within: context)
        super.init(frc1: frc1, frc2: frc2, frc3: frc3, frc4: frc4)
    }

    override func createModel(fetchedObjects1: [PersistedDiscussion], fetchedObjects2: [PersistedGroupV2], fetchedObjects3: [PersistedGroupV2Member], fetchedObjects4: [PersistedDiscussionLocalConfiguration]) throws -> ObvSingleDiscussion.DiscussionHeader {
        guard let discussion = fetchedObjects1.first else { throw ObvError.couldNotFindDiscussion }
        return SingleDiscussionViewAppDataSource.header(of: discussion)
    }

    enum ObvError: Error {
        case couldNotFindDiscussion
    }

}
