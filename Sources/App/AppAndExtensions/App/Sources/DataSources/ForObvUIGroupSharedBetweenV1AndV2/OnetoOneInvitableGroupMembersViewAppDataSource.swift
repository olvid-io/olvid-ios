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
import ObvUIGroupSharedBetweenV1AndV2
import ObvTypes
import ObvAppTypes
import ObvUICoreData
import ObvDesignSystem
import OlvidUtils

@MainActor
final class OnetoOneInvitableGroupMembersViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var onetoOneInvitableGroupMembersViewModelForGroupV1StreamManagerForStreamUUID = [UUID: OnetoOneInvitableGroupMembersViewModelForGroupV1StreamManager]()
    private var onetoOneInvitableGroupMembersViewModelForGroupV2StreamManagerForStreamUUID = [UUID: OnetoOneInvitableGroupMembersViewModelForGroupV2StreamManager]()

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }

}


extension OnetoOneInvitableGroupMembersViewAppDataSource: ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersViewDataSource {
    
    /// Called when displaying the list of group members split in 3 sections:
    /// - Group members that are not yet one2one contacts but that can be invited.
    /// - Group members that are not yet one2one contacts but that must accept the group invitation before they can be invited
    /// - Group members that are one2one contacts already.
    /// Note that since we only return members identifiers in the model, we don't need to know whether invitable group members have already been invited.
    func getAsyncSequenceOfOnetoOneInvitableGroupMembersViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersViewModel>) {
        switch groupIdentifier {
        case .groupV1(let groupIdentifier):
            let streamManager = OnetoOneInvitableGroupMembersViewModelForGroupV1StreamManager(groupIdentifier: groupIdentifier, context: backgroundContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.onetoOneInvitableGroupMembersViewModelForGroupV1StreamManagerForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        case .groupV2(let groupIdentifier):
            let streamManager = OnetoOneInvitableGroupMembersViewModelForGroupV2StreamManager(groupIdentifier: groupIdentifier, context: backgroundContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.onetoOneInvitableGroupMembersViewModelForGroupV2StreamManagerForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        }
    }
    
    func finishAsyncSequenceOfOnetoOneInvitableGroupMembersViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersView, streamUUID: UUID) {
        if let streamManager = onetoOneInvitableGroupMembersViewModelForGroupV1StreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
        if let streamManager = onetoOneInvitableGroupMembersViewModelForGroupV2StreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
    }
    
}


// MARK: - Stream Manager for OnetoOneInvitableGroupMembersViewModel

extension OnetoOneInvitableGroupMembersViewAppDataSource {
    
    private final class OnetoOneInvitableGroupMembersViewModelForGroupV1StreamManager: ObvDataSourceStreamManagerWithThreeFetchedResultsController<ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersViewModel, PersistedObvContactIdentity, PersistedPendingGroupMember, PersistedObvContactIdentity>, @unchecked Sendable {
        
        init(groupIdentifier: ObvTypes.ObvGroupV1Identifier, context: NSManagedObjectContext) {
            let frcForInvitableMembers = PersistedObvContactIdentity.getFetchedResultsControllerForGroupV1(groupIdentifier: groupIdentifier, whereOneToOneStatusIs: .nonOneToOne, within: context)
            let frcForPersistedPendingGroupMember = PersistedPendingGroupMember.getFetchedResultsControllerForContactGroup(groupV1Identifier: groupIdentifier, within: context)
            let frcForMembersThatAreOne2OneAlready = PersistedObvContactIdentity.getFetchedResultsControllerForGroupV1(groupIdentifier: groupIdentifier, whereOneToOneStatusIs: .oneToOne, within: context)
            super.init(frc1: frcForInvitableMembers, frc2: frcForPersistedPendingGroupMember, frc3: frcForMembersThatAreOne2OneAlready)
        }

        override func createModel(fetchedObjects1: [PersistedObvContactIdentity], fetchedObjects2: [PersistedPendingGroupMember], fetchedObjects3: [PersistedObvContactIdentity]) throws -> OnetoOneInvitableGroupMembersViewModel {

            let invitableMembers = fetchedObjects1
            let memberWithNoAssociatedContact = fetchedObjects2
            let membersThatAreOne2OneAlready = fetchedObjects3
            
            let model = ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersViewModel(
                invitableGroupMembers: invitableMembers.map({ .objectIDOfPersistedObvContactIdentity(objectID: $0.objectID) }),
                notInvitableGroupMembers: memberWithNoAssociatedContact.map({ .objectIDOfPersistedPendingGroupMember(objectID: $0.objectID) }),
                oneToOneContactsAmongMembers: membersThatAreOne2OneAlready.map({ .objectIDOfPersistedObvContactIdentity(objectID: $0.objectID) }))

            return model
        }
        
    }
    
    private final class OnetoOneInvitableGroupMembersViewModelForGroupV2StreamManager: ObvDataSourceStreamManagerWithThreeFetchedResultsController<ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersViewModel, PersistedObvContactIdentity, PersistedGroupV2Member, PersistedObvContactIdentity>, @unchecked Sendable {
     
        init(groupIdentifier: ObvTypes.ObvGroupV2Identifier, context: NSManagedObjectContext) {
            let frcForInvitableMembers = PersistedObvContactIdentity.getFetchedResultsControllerForGroupV2(groupIdentifier: groupIdentifier, whereOneToOneStatusIs: .nonOneToOne, within: context)
            let frcForPersistedGroupV2MemberWithNoAssociatedContact = PersistedGroupV2Member.getFetchedResultsControllerForMembersWithNoAssociatedContact(groupV2Identifier: groupIdentifier, within: context)
            let frcForMembersThatAreOne2OneAlready = PersistedObvContactIdentity.getFetchedResultsControllerForGroupV2(groupIdentifier: groupIdentifier, whereOneToOneStatusIs: .oneToOne, within: context)
            super.init(frc1: frcForInvitableMembers, frc2: frcForPersistedGroupV2MemberWithNoAssociatedContact, frc3: frcForMembersThatAreOne2OneAlready)
        }
        
        override func createModel(fetchedObjects1: [PersistedObvContactIdentity], fetchedObjects2: [PersistedGroupV2Member], fetchedObjects3: [PersistedObvContactIdentity]) throws -> OnetoOneInvitableGroupMembersViewModel {
            
            let invitableMembers = fetchedObjects1
            let memberWithNoAssociatedContact = fetchedObjects2
            let membersThatAreOne2OneAlready = fetchedObjects3
            
            let model = ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersViewModel(
                invitableGroupMembers: invitableMembers.map({ .objectIDOfPersistedObvContactIdentity(objectID: $0.objectID) }),
                notInvitableGroupMembers: memberWithNoAssociatedContact.map({ .objectIDOfPersistedGroupV2Member(objectID: $0.objectID) }),
                oneToOneContactsAmongMembers: membersThatAreOne2OneAlready.map({ .objectIDOfPersistedObvContactIdentity(objectID: $0.objectID) }))

            return model
            
        }
        
    }
    
}
