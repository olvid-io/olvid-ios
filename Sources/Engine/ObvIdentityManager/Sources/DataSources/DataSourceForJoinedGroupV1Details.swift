/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvTypes
import OlvidUtils


final class DataSourceForJoinedGroupV1Details {
    
    let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        context.automaticallyMergesChangesFromParent = true
        self.context = context
    }
    
    private var joinedGroupV1DetailsStreamManagerForStreamUUID = [UUID: JoinedGroupV1DetailsStreamManager]()

}


extension DataSourceForJoinedGroupV1Details {
    
    func getAsyncStreamOfJoinedGroupV1Details(groupIdentifier: ObvGroupV1Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvGroupTrustedAndPublishedDetails>) {
        let streamManager = JoinedGroupV1DetailsStreamManager(groupIdentifier: groupIdentifier, context: context)
        let (streamUUID, stream) = try await streamManager.startStream()
        self.joinedGroupV1DetailsStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }
    
    func finishAsyncStreamOfJoinedGroupV1Details(streamUUID: UUID) {
        guard let streamManager = joinedGroupV1DetailsStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        streamManager.finishStream()
    }
    
}


extension DataSourceForJoinedGroupV1Details {
    
    private final class JoinedGroupV1DetailsStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvGroupTrustedAndPublishedDetails, ContactGroupJoined, ContactGroupDetailsPublished>, @unchecked Sendable {
        
        init(groupIdentifier: ObvGroupV1Identifier, context: NSManagedObjectContext) {
            let frc1 = ContactGroupJoined.getFetchedResultsController(groupIdentifier: groupIdentifier, within: context)
            // The following frc may return other published details than the one we expect (the reason is that it doesn't seem technically possible to create an frc based on the ObvGroupV1Identifier
            // given the structure of tables). This is not an issue, as we only use this frc to ensure the `createModel` method is called when the published details of the group are updated.
            let frc2 = ContactGroupDetailsPublished.getFetchedResultsController(ownedCryptoId: groupIdentifier.ownedCryptoId, groupUid: groupIdentifier.groupV1Identifier.groupUid, within: context)
            super.init(frc1: frc1, frc2: frc2)
        }
     
        override func createModel(fetchedObjects1: [ContactGroupJoined], fetchedObjects2: [ContactGroupDetailsPublished]) throws -> ObvGroupTrustedAndPublishedDetails {
            assert(fetchedObjects1.count <= 1)
            guard let joinedGroup = fetchedObjects1.first else {
                throw ObvError.couldNotFindGroupJoined
            }
            
            let trustedInfo = try joinedGroup.getTrustedJoinedGroupInformationWithPhoto().groupDetailsElementsWithPhoto
            let publishedInfo = try joinedGroup.getPublishedJoinedGroupInformationWithPhoto().groupDetailsElementsWithPhoto
            
            let trustedDetails: ObvGroupDetails = .init(
                coreDetails: trustedInfo.coreDetails,
                photoURL: trustedInfo.photoURL)
            
            let publishedDetails: ObvGroupDetails = .init(
                coreDetails: publishedInfo.coreDetails,
                photoURL: publishedInfo.photoURL)
            
            if trustedDetails == publishedDetails {
                return .init(trustedDetails: trustedDetails, publishedDetails: nil)
            } else {
                return .init(trustedDetails: trustedDetails, publishedDetails: publishedDetails)
            }

        }
        
        enum ObvError: Error {
            case couldNotFindGroupJoined
        }
        
    }
    
}
