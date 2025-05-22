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

import UIKit
import ObvTypes
import ObvDesignSystem
import ObvAppTypes


public enum ObvUIGroupV2RouterDataSourceMode {
    case creation(ownedCryptoId: ObvTypes.ObvCryptoId)
    case edition(groupIdentifier: ObvTypes.ObvGroupV2Identifier)
}


@MainActor
public protocol ObvUIGroupV2RouterDataSource: AnyObject {
    
    func getAsyncSequenceOfSingleGroupMemberViewModels(_ router: ObvUIGroupV2Router, memberIdentifier: SingleGroupMemberViewModelIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupMemberViewModel>)
    func finishAsyncSequenceOfSingleGroupMemberViewModels(_ router: ObvUIGroupV2Router, memberIdentifier: SingleGroupMemberViewModelIdentifier, streamUUID: UUID)
    
    func getAsyncSequenceOfGroupLightweightModel(_ router: ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<GroupLightweightModel>)
    func finishAsyncSequenceOfGroupLightweightModel(_ router: ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier, streamUUID: UUID)

    
    func getAsyncSequenceOfListOfSingleGroupMemberViewModel(_ router: ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>)
    func filterAsyncSequenceOfListOfSingleGroupMemberViewModel(_ router: ObvUIGroupV2Router, streamUUID: UUID, searchText: String?)
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModel(_ router: ObvUIGroupV2Router, streamUUID: UUID)
 
    func getAsyncSequenceOfListOfSingleGroupAdminsMemberViewModel(_ router: ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>)
    func finishAsyncSequenceOfListOfSingleGroupAdminsMemberViewModel(_ router: ObvUIGroupV2Router, streamUUID: UUID)


    func getAsyncSequenceOfSingleGroupV2MainViewModel(_ router: ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupV2MainViewModelOrNotFound>)
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(_ router: ObvUIGroupV2Router, streamUUID: UUID)

    func getAsyncSequenceOfSelectUsersToAddViewModel(_ router: ObvUIGroupV2Router, mode: ObvUIGroupV2RouterDataSourceMode) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel>)
    func filterAsyncSequenceOfSelectUsersToAddViewModel(_ router: ObvUIGroupV2Router, streamUUID: UUID, searchText: String?)
    func finishAsyncSequenceOfSelectUsersToAddViewModel(_ router: ObvUIGroupV2Router, streamUUID: UUID)
    func getAsyncSequenceOfSelectUsersToAddViewModelUser(_ router: ObvUIGroupV2Router, withIdentifier identifier: SelectUsersToAddViewModel.User.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SelectUsersToAddViewModel.User>)
    func finishAsyncSequenceOfSelectUsersToAddViewModelUser(_ router: ObvUIGroupV2Router, withIdentifier identifier: SelectUsersToAddViewModel.User.Identifier, streamUUID: UUID)
    
    func fetchAvatarImage(_ router: ObvUIGroupV2Router, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?

    func getContactIdentifierOfUser(_ router: ObvUIGroupV2Router, contactIdentifier: SelectUsersToAddViewModel.User.Identifier) async throws -> ObvContactIdentifier
    func getGroupType(_ router: ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws -> ObvGroupType
    
    func getContactIdentifierOfGroupMember(_ router: ObvUIGroupV2Router, contactIdentifier: SingleGroupMemberViewModelIdentifier) async throws -> ObvContactIdentifier
    func getContactIdentifierOfGroupMember(_ router: ObvUIGroupV2Router, contactIdentifier: SelectUsersToAddViewModel.User.Identifier) async throws -> ObvContactIdentifier

    func filterUsersWithSearchText(users: [SelectUsersToAddViewModel.User.Identifier], searchText: String?) -> [SelectUsersToAddViewModel.User.Identifier]
    
    func getAsyncSequenceOfOneToOneInvitableViewModel(_ router: ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<OneToOneInvitableViewModel>)
    func finishAsyncSequenceOfOneToOneInvitableViewModel(_ router: ObvUIGroupV2Router, streamUUID: UUID)

    func getAsyncSequenceOfOnetoOneInvitableGroupMembersViewModel(_ router: ObvUIGroupV2Router, groupIdentifier: ObvTypes.ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<OnetoOneInvitableGroupMembersViewModel>)
    func finishAsyncSequenceOfOnetoOneInvitableGroupMembersViewModel(_ router: ObvUIGroupV2Router, streamUUID: UUID)

    func getAsyncSequenceOfOnetoOneInvitableGroupMembersViewCellModels(_ router: ObvUIGroupV2Router, identifier: OnetoOneInvitableGroupMembersViewModel.Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<OnetoOneInvitableGroupMembersViewCellModel>)
    func finishAsyncSequenceOfOnetoOneInvitableGroupMembersViewCellModels(_ router: ObvUIGroupV2Router, identifier: OnetoOneInvitableGroupMembersViewModel.Identifier, streamUUID: UUID)

    func getValuesOfGroupToClone(_ router: ObvUIGroupV2Router, identifierOfGroupToClone: ObvTypes.ObvGroupV2Identifier) async throws -> ObvUIGroupV2Router.ValuesOfClonedGroup
    
    func getContactIdentifiers(_ router: ObvUIGroupV2Router, identifiers: [OnetoOneInvitableGroupMembersViewModel.Identifier]) async throws -> [ObvContactIdentifier]

    func getAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ router: ObvUIGroupV2Router, groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<OwnedIdentityAsGroupMemberViewModel>)
    func finishAsyncSequenceOfOwnedIdentityAsGroupMemberViewModel(_ router: ObvUIGroupV2Router, groupIdentifier: ObvGroupV2Identifier, streamUUID: UUID)

}


@MainActor
public final class ObvUIGroupV2Router {
    
    public enum Mode {
        case creation(delegate: ObvUIGroupV2RouterDelegateForCreation)
        case edition(delegate: ObvUIGroupV2RouterDelegateForEdition)
    }
    
    public enum CreationMode {
        case fromScratch
        case cloneExistingGroup(valuesOfGroupToClone: ValuesOfClonedGroup)
    }

    public struct ValuesOfClonedGroup {
        let userIdentifiersOfAddedUsers: [SelectUsersToAddViewModel.User.Identifier]
        let selectedAdmins: Set<SingleGroupMemberViewModelIdentifier>
        let selectedGroupType: ObvGroupType?
        let selectedPhoto: UIImage?
        let selectedGroupName: String?
        let selectedGroupDescription: String?
        public init(userIdentifiersOfAddedUsers: [SelectUsersToAddViewModel.User.Identifier], selectedAdmins: Set<SingleGroupMemberViewModelIdentifier>, selectedGroupType: ObvGroupType?, selectedPhoto: UIImage?, selectedGroupName: String?, selectedGroupDescription: String?) {
            self.userIdentifiersOfAddedUsers = userIdentifiersOfAddedUsers
            self.selectedAdmins = selectedAdmins
            self.selectedGroupType = selectedGroupType
            self.selectedPhoto = selectedPhoto
            self.selectedGroupName = selectedGroupName
            self.selectedGroupDescription = selectedGroupDescription
        }
    }

    private enum InternalMode {
        case edition(router: RouterForEditionMode)
        case creation(router: RouterForCreationMode)
    }
    
    private let internalMode: InternalMode

    public init(mode: Mode, dataSource: ObvUIGroupV2RouterDataSource) {
        
        switch mode {
        case .edition(delegate: let delegate):
            let router = RouterForEditionMode(dataSource: dataSource, delegate: delegate)
            self.internalMode = .edition(router: router)
        case .creation(delegate: let delegate):
            let router = RouterForCreationMode(dataSource: dataSource, delegate: delegate)
            self.internalMode = .creation(router: router)
        }
        
        switch internalMode {
        case .edition(router: let router):
            router.parentRouter = self
        case .creation(router: let router):
            router.parentRouter = self
        }

    }
    
}


// MARK: - Public API

extension ObvUIGroupV2Router {
    
    public func pushOrPopInitialViewControllerForGroupEdition(navigationController: UINavigationController, groupIdentifier: ObvGroupV2Identifier) {
        switch internalMode {
        case .edition(router: let router):
            router.pushOrPopInitialViewController(navigationController: navigationController, groupIdentifier: groupIdentifier)
        case .creation:
            assertionFailure()
        }
    }
    
    public func getInitialViewControllerToPresentForGroupEdition(groupIdentifier: ObvGroupV2Identifier) -> UIViewController? {
        switch internalMode {
        case .edition(router: let router):
            return router.getInitialViewControllerForGroupEdition(groupIdentifier: groupIdentifier)
        case .creation:
            assertionFailure()
            return nil
        }
    }
    
    /// This gets called when a group is deleted (e.g., because we were removed from the group)
    public func removeFromNavigationAllViewControllersRelatingToGroup(navigationController: UINavigationController, groupIdentifier: ObvGroupV2Identifier) {
        switch internalMode {
        case .edition(router: let router):
            return router.removeFromNavigationAllViewControllersRelatingToGroup(navigationController: navigationController, groupIdentifier: groupIdentifier)
        case .creation:
            assertionFailure()
        }
    }
        
    public func presentInitialViewControllerForGroupCreation(ownedCryptoId: ObvCryptoId, presentingViewController: UIViewController, creationMode: CreationMode) {
        switch internalMode {
        case .edition:
            assertionFailure()
        case .creation(router: let router):
            router.presentInitialViewController(ownedCryptoId: ownedCryptoId, presentingViewController: presentingViewController, creationType: creationMode)
        }
    }
    
}
