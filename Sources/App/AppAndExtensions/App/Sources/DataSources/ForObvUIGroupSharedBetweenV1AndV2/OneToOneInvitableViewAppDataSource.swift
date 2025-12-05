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
final class OneToOneInvitableViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var oneToOneInvitableViewModelFromGroupV1StreamManagerForStreamUUID = [UUID: OneToOneInvitableViewModelFromGroupV1StreamManager]()
    private var oneToOneInvitableViewModelFromGroupV2StreamManagerForStreamUUID = [UUID: OneToOneInvitableViewModelFromGroupV2StreamManager]()

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
    
}


extension OneToOneInvitableViewAppDataSource: OneToOneInvitableViewDataSource {
    
    /// Called when displaying the group details, for the view showing the number of group members that are:
    /// - contacts
    /// - but not yet one-to-one.
    /// These are the contacts that can be invited to a one-to-one discussion.
    func getAsyncSequenceOfOneToOneInvitableViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.OneToOneInvitableView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.OneToOneInvitableViewModel>) {
        switch groupIdentifier {
        case .groupV1(let groupIdentifier):
            let streamManager = OneToOneInvitableViewModelFromGroupV1StreamManager(groupIdentifier: groupIdentifier, context: backgroundContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.oneToOneInvitableViewModelFromGroupV1StreamManagerForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        case .groupV2(let groupIdentifier):
            let streamManager = OneToOneInvitableViewModelFromGroupV2StreamManager(groupIdentifier: groupIdentifier, context: backgroundContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.oneToOneInvitableViewModelFromGroupV2StreamManagerForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        }
    }
    
    func finishAsyncSequenceOfOneToOneInvitableViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.OneToOneInvitableView, streamUUID: UUID) {
        if let streamManager = oneToOneInvitableViewModelFromGroupV1StreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
        if let streamManager = oneToOneInvitableViewModelFromGroupV2StreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
    }
    
}


// MARK: - OneToOneInvitableViewModelFromGroupV1IdentifierStreamManager

extension OneToOneInvitableViewAppDataSource {
    
    /// See the comment about `OneToOneInvitableViewModelStreamManager`
    private final class OneToOneInvitableViewModelFromGroupV1StreamManager: ObvDataSourceStreamManagerWithThreeFetchedResultsController<ObvUIGroupSharedBetweenV1AndV2.OneToOneInvitableViewModel, PersistedObvContactIdentity, PersistedInvitationOneToOneInvitationSent, PersistedContactGroup>, @unchecked Sendable {
        
        init(groupIdentifier: ObvGroupV1Identifier, context: NSManagedObjectContext) {
            let frcForInvitableMembers = PersistedObvContactIdentity.getFetchedResultsControllerForGroupV1(groupIdentifier: groupIdentifier, whereOneToOneStatusIs: .nonOneToOne, within: context)
            let frcForOneToOneInvitation = PersistedInvitationOneToOneInvitationSent.getFetchedResultsControllerForAll(ownedCryptoId: groupIdentifier.ownedCryptoId, within: context)
            let frc3 = PersistedContactGroup.getFetchedResultsController(groupV1Identifier: groupIdentifier, within: context)
            super.init(frc1: frcForInvitableMembers, frc2: frcForOneToOneInvitation, frc3: frc3)
        }
        
        override func createModel(fetchedObjects1: [PersistedObvContactIdentity], fetchedObjects2: [PersistedInvitationOneToOneInvitationSent], fetchedObjects3: [PersistedContactGroup]) throws -> OneToOneInvitableViewModel {
            
            let invitableMembers = fetchedObjects1
            let oneToOneInvitation = fetchedObjects2
            
            let identitiesOfInvitableGroupMembers: Set<ObvCryptoId> = Set(invitableMembers.map(\.cryptoId))
            let invitedIdentities: Set<ObvCryptoId> = Set(oneToOneInvitation.compactMap(\.contactIdentity))
            
            let numberOfGroupMembersThatAreContactsButNotOneToOne = identitiesOfInvitableGroupMembers.count
            let numberOfOneToOneInvitationsSent = invitedIdentities.intersection(identitiesOfInvitableGroupMembers).count
            let numberOfPendingMembersWithNoAssociatedContact = fetchedObjects3.count
            
            let groupHasNoOtherMember = fetchedObjects3.first?.contactIdentities.isEmpty ?? false
            
            return ObvUIGroupSharedBetweenV1AndV2.OneToOneInvitableViewModel(
                numberOfGroupMembersThatAreContactsButNotOneToOne: numberOfGroupMembersThatAreContactsButNotOneToOne,
                numberOfOneToOneInvitationsSent: numberOfOneToOneInvitationsSent,
                numberOfPendingMembersWithNoAssociatedContact: numberOfPendingMembersWithNoAssociatedContact,
                groupHasNoOtherMember: groupHasNoOtherMember)
            
        }
        
    }
    
}

// MARK: - Stream Manager for OneToOneInvitableViewModel

extension OneToOneInvitableViewAppDataSource {

    
    /// This manager produces a stream feeding the view indicating how many group members are not yet one2one contacts.
    /// To determine this number, we need to consider all group members that have an associated PersistedObvContactIdentity that is not one2one.
    /// Since we also need the number of invitations sent, we also need to fetch `PersistedInvitationOneToOneInvitationSent` and count how many correspond to
    /// the "invitable" members.
    private final class OneToOneInvitableViewModelFromGroupV2StreamManager: ObvDataSourceStreamManagerWithFourFetchedResultsController<ObvUIGroupSharedBetweenV1AndV2.OneToOneInvitableViewModel, PersistedObvContactIdentity, PersistedInvitationOneToOneInvitationSent, PersistedGroupV2Member, PersistedGroupV2Member>, @unchecked Sendable {
        
        init(groupIdentifier: ObvTypes.ObvGroupV2Identifier, context: NSManagedObjectContext) {
            let frcForInvitableMembers = PersistedObvContactIdentity.getFetchedResultsControllerForGroupV2(groupIdentifier: groupIdentifier, whereOneToOneStatusIs: .nonOneToOne, within: context)
            let frcForOneToOneInvitation = PersistedInvitationOneToOneInvitationSent.getFetchedResultsControllerForAll(ownedCryptoId: groupIdentifier.ownedCryptoId, within: context)
            let frcForPersistedGroupV2MemberWithNoAssociatedContact = PersistedGroupV2Member.getFetchedResultsControllerForMembersWithNoAssociatedContact(groupV2Identifier: groupIdentifier, within: context)
            let frcForAllGroupMembers = PersistedGroupV2Member.getFetchedResultsController(groupV2Identifier: groupIdentifier, within: context)
            super.init(frc1: frcForInvitableMembers, frc2: frcForOneToOneInvitation, frc3: frcForPersistedGroupV2MemberWithNoAssociatedContact, frc4: frcForAllGroupMembers)
        }

        override func createModel(fetchedObjects1: [PersistedObvContactIdentity], fetchedObjects2: [PersistedInvitationOneToOneInvitationSent], fetchedObjects3: [PersistedGroupV2Member], fetchedObjects4: [PersistedGroupV2Member]) throws -> OneToOneInvitableViewModel {
            let invitableMembers = fetchedObjects1
            let oneToOneInvitation = fetchedObjects2
            let allMembers = fetchedObjects4
            
            let identitiesOfInvitableGroupMembers: Set<ObvCryptoId> = Set(invitableMembers.map(\.cryptoId))
            let invitedIdentities: Set<ObvCryptoId> = Set(oneToOneInvitation.compactMap(\.contactIdentity))
            
            let numberOfGroupMembersThatAreContactsButNotOneToOne = identitiesOfInvitableGroupMembers.count
            let numberOfOneToOneInvitationsSent = invitedIdentities.intersection(identitiesOfInvitableGroupMembers).count
            let numberOfPendingMembersWithNoAssociatedContact = fetchedObjects3.count
            
            let groupHasNoOtherMember = allMembers.isEmpty
            
            return ObvUIGroupSharedBetweenV1AndV2.OneToOneInvitableViewModel(
                numberOfGroupMembersThatAreContactsButNotOneToOne: numberOfGroupMembersThatAreContactsButNotOneToOne,
                numberOfOneToOneInvitationsSent: numberOfOneToOneInvitationsSent,
                numberOfPendingMembersWithNoAssociatedContact: numberOfPendingMembersWithNoAssociatedContact,
                groupHasNoOtherMember: groupHasNoOtherMember)
        }
        
    }
        
}
