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

import UIKit
import OSLog
import CoreData
import UniformTypeIdentifiers
import Combine
import ObvTypes
import ObvUICoreData
import ObvSettings


protocol NewGroupEditionFlowViewControllerGroupModificationDelegate: AnyObject {
    func userWantsToPublishGroupV2Modification(controller: NewGroupEditionFlowViewController, groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2>, changeset: ObvGroupV2.Changeset) async
}


protocol NewGroupEditionFlowViewControllerGroupCreationDelegate: AnyObject {
    func userWantsToPublishGroupV2Creation(controller: NewGroupEditionFlowViewController, groupCoreDetails: GroupV2CoreDetails, ownPermissions: Set<ObvGroupV2.Permission>, otherGroupMembers: Set<ObvGroupV2.IdentityAndPermissions>, ownedCryptoId: ObvCryptoId, photoURL: URL?, groupType: PersistedGroupV2.GroupType) async
}



@MainActor
final class NewGroupEditionFlowViewController: UIViewController {

    enum EditionType {
        
        case modifyGroup(delegate: NewGroupEditionFlowViewControllerGroupModificationDelegate, groupIdentifier: Data)
        case createGroup(delegate: NewGroupEditionFlowViewControllerGroupCreationDelegate)
        case cloneGroup(delegate: NewGroupEditionFlowViewControllerGroupCreationDelegate,
                        initialGroupMembers: Set<InitialGroupMember>,
                        initialGroupName: String?,
                        initialGroupDescription: String?,
                        initialPhotoURL: URL?,
                        initialGroupType: PersistedGroupV2.GroupType?)

        struct InitialGroupMember: Hashable {
            let cryptoId: ObvCryptoId
            let isAdmin: Bool
        }
        
    }

    //MARK: Attributes - Private - Group infos
    private var groupProxyModel: ObvGroupProxyModel
    
    //MARK: Attributes - Private - Edition Type
    private var editionType: EditionType
    
    // MARK: Attributes - Private - Logger
    private static let defaultLogSubsystem = "io.olvid.messenger"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: String(describing: NewGroupEditionFlowViewController.self))

    // MARK: Attributes - Private - Datas
    let ownedCryptoId: ObvCryptoId
    private let directoryForTempFiles: URL
    
    // MARK: Methods - Public - Ctor
    public init(ownedCryptoId: ObvCryptoId, editionType: EditionType, logSubsystem: String, directoryForTempFiles: URL) {
        self.ownedCryptoId = ownedCryptoId
        self.directoryForTempFiles = directoryForTempFiles
        self.editionType = editionType
        self.groupProxyModel = ObvGroupProxyModel(ownedCryptoId: ownedCryptoId, editionType: editionType, directoryForTempFiles: directoryForTempFiles)
        super.init(nibName: nil, bundle: nil)
        Self.log = OSLog(subsystem: logSubsystem, category: String(describing: NewGroupEditionFlowViewController.self))
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    //MARK: Methods - Public - Life cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        self.isModalInPresentation = true // disable dismissal of a view controller presentation
        view.backgroundColor = .clear
        goTo(state: .selectGroupMembers)
    }
    
    //MARK: Extension - Private - View Hierarchy

    private lazy var flowNavigationController: UINavigationController = {
        
        let mode: ContactsSelectionForGroupHostingViewController.Mode
        switch editionType {
        case .cloneGroup, .createGroup:
            mode = .create
        case .modifyGroup:
            mode = .modify
        }
        let rootViewController = ContactsSelectionForGroupHostingViewController(ownedCryptoId: ownedCryptoId, mode: mode, preSelectedContacts: groupProxyModel.selectedContacts, delegate: self)
                
        let flowNavigationController = UINavigationController(rootViewController: rootViewController)
        flowNavigationController.setNavigationBarHidden(false, animated: false)
        flowNavigationController.navigationBar.backgroundColor = .clear
        flowNavigationController.navigationBar.prefersLargeTitles = false
        
        flowNavigationController.willMove(toParent: self)
        addChild(flowNavigationController)
        flowNavigationController.didMove(toParent: self)
        
        view.addSubview(flowNavigationController.view)
        
        flowNavigationController.view.translatesAutoresizingMaskIntoConstraints = true
        flowNavigationController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        flowNavigationController.view.frame = view.bounds

        return flowNavigationController
        
    }()
    
    
    private func userWantsToCancelGroupCreationFlow() {
        self.dismiss(animated: true)
    }
        
}


// MARK: navigation flow

extension NewGroupEditionFlowViewController {
    
    private func goTo(state: GroupCreationFlowState, animated: Bool = true) {
        
        switch state {
            
        case .selectGroupMembers:
            flowNavigationController.popToRootViewController(animated: animated)
            
        case .selectType:
            if let selectTypeVC = flowNavigationController.viewControllers.first(where: { $0 is GroupCreationTypeHostingViewController }) {
                flowNavigationController.popToViewController(selectTypeVC, animated: animated)
            } else {
                let vc = GroupCreationTypeHostingViewController(preselectedGroupType: groupProxyModel.groupType?.value,
                                                                selectedContacts: groupProxyModel.selectedContacts.sorted(by: \.customOrShortDisplayName),
                                                                delegate: self)
                flowNavigationController.pushViewController(vc, animated: animated)
            }

        case .advancedParameters:
            if let vc = flowNavigationController.viewControllers.first(where: { $0 is GroupCreationParametersHostingViewController }) {
                flowNavigationController.popToViewController(vc, animated: animated)
            } else {
                let orderedContacts = groupProxyModel.selectedContacts.sorted(by: \.customOrShortDisplayName)
                let (isReadOnly, remoteDeleteAnythingPolicy) = groupProxyModel.parametersOfAdvancedType
                let vc = GroupCreationParametersHostingViewController(model: .init(orderedContacts: orderedContacts,
                                                                                   remoteDeleteAnythingPolicy: remoteDeleteAnythingPolicy,
                                                                                   isReadOnly: isReadOnly),
                                                                      delegate: self)
                flowNavigationController.pushViewController(vc, animated: animated)
            }
            
        case .informations:
            if let infoVC = flowNavigationController.viewControllers.first(where: { $0 is GroupCreationInfoHostingViewController }) {
                flowNavigationController.popToViewController(infoVC, animated: animated)
            } else {
                let orderedContacts = groupProxyModel.selectedContacts.sorted(by: \.customOrShortDisplayName)
                let model = GroupInfoViewModel(orderedContacts: orderedContacts,
                                               initialName: groupProxyModel.groupName,
                                               initialDescription: groupProxyModel.groupDescription,
                                               initialCircledInitialsConfiguration: groupProxyModel.circledInitialsConfiguration, 
                                               editOrCreate: groupProxyModel.editOrCreate)
                let vc = GroupCreationInfoHostingViewController(model: model, delegate: self)
                flowNavigationController.pushViewController(vc, animated: animated)
            }
            
        case .adminChoice(showButton: let showButton):
            //guard let groupType = groupProxyModel.groupType else { return }
            if let vc = flowNavigationController.viewControllers.first(where: { $0 is GroupCreationAdminChoiceHostingViewController }) {
                flowNavigationController.popToViewController(vc, animated: animated)
            } else {
                let vc = GroupCreationAdminChoiceHostingViewController(contacts: groupProxyModel.selectedContacts.sorted(by: \.customOrShortDisplayName),
                                                                       admins: groupProxyModel.admins,
                                                                       showButton: showButton,
                                                                       delegate: self)
                flowNavigationController.pushViewController(vc, animated: animated)
            }
            
        case .moderation:
            if let vc = flowNavigationController.viewControllers.first(where: { $0 is GroupCreationModerationHostingViewController }) {
                flowNavigationController.popToViewController(vc, animated: animated)
            } else {
                let vc = GroupCreationModerationHostingViewController(model: .init(currentPolicy: groupProxyModel.parametersOfAdvancedType.policy), delegate: self)
                flowNavigationController.pushViewController(vc, animated: animated)
            }
        }
        
    }
}


// MARK: - GroupCreationModerationHostingViewControllerDelegate

extension NewGroupEditionFlowViewController: GroupCreationModerationHostingViewControllerDelegate {
    
    func userWantsToChangeRemoteDeleteAnythingPolicy(in controller: GroupCreationModerationHostingViewController, to policy: PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy) -> PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy {
        
        groupProxyModel.setRemoteDeleteAnythingPolicy(to: policy)
        
        // Update GroupCreationParametersHostingViewController if one is found in the stack
        if let vc = flowNavigationController.viewControllers.first(where: { $0 is GroupCreationParametersHostingViewController }) as? GroupCreationParametersHostingViewController {
            vc.userChangedRemoteDeleteAnythingPolicy(to: groupProxyModel.parametersOfAdvancedType.policy)
        }

        return groupProxyModel.parametersOfAdvancedType.policy
        
    }
    
}

// MARK: - GroupCreationParametersHostingViewControllerDelegate

extension NewGroupEditionFlowViewController: GroupCreationParametersHostingViewControllerDelegate {
    
    func userWantsToChangeReadOnlyParameter(in controller: GroupCreationParametersHostingViewController, isReadOnly: Bool) -> Bool {
        groupProxyModel.setIsReadOnly(to: isReadOnly)
        return groupProxyModel.parametersOfAdvancedType.isReadOnly
    }
    
    
    func userWantsToNavigateToAdminsChoice(in controller: GroupCreationParametersHostingViewController) {
        goTo(state: .adminChoice(showButton: false))
    }
    
    
    func userWantsToNavigateToRemoteDeleteAnythingPolicyChoice(in controller: GroupCreationParametersHostingViewController) {
        goTo(state: .moderation)
    }
    
    
    func userWantsToNavigateToNextScreen(in controller: GroupCreationParametersHostingViewController) {
        goTo(state: .informations)
    }
    
    func userWantsToCancelGroupCreationFlow(in controller: GroupCreationParametersHostingViewController) {
        userWantsToCancelGroupCreationFlow()
    }

}

// MARK: - GroupCreationInfoHostingViewControllerDelegate

extension NewGroupEditionFlowViewController: GroupCreationInfoHostingViewControllerDelegate {
    
    func userDidChooseGroupInfos(in controller: GroupCreationInfoHostingViewController, name: String?, description: String?, photo: UIImage?) async {
        
        groupProxyModel.setGroupInfos(name: name, description: description, photo: photo)
        
        switch editionType {
            
        case .modifyGroup(delegate: let delegate, groupIdentifier: let groupIdentifier):
            do {
                try await startUpdateFlow(delegate: delegate, groupIdentifier: groupIdentifier)
            } catch {
                assertionFailure()
                self.dismiss(animated: true)
            }
            
        case .createGroup(delegate: let delegate),
                .cloneGroup(delegate: let delegate, initialGroupMembers: _, initialGroupName: _, initialGroupDescription: _, initialPhotoURL: _, initialGroupType: _):
            await startCreationFlow(delegate: delegate)
            
        }
        
    }

    
    func userWantsToCancelGroupCreationFlow(in controller: GroupCreationInfoHostingViewController) {
        userWantsToCancelGroupCreationFlow()
    }

}


// MARK: - GroupCreationAdminChoiceHostingViewControllerDelegate

extension NewGroupEditionFlowViewController: GroupCreationAdminChoiceHostingViewControllerDelegate {
    
    func userWantsToChangeContactAdminStatus(in controller: GroupCreationAdminChoiceHostingViewController, contactCryptoId: ObvTypes.ObvCryptoId, isAdmin: Bool) -> Set<ObvUICoreData.PersistedObvContactIdentity> {
        groupProxyModel.changeContactAdminStatus(contactCryptoId: contactCryptoId, isAdmin: isAdmin)
        return groupProxyModel.admins
    }
    
    
    func userConfirmedGroupAdminChoice(in controller: GroupCreationAdminChoiceHostingViewController) async {
        assert(groupProxyModel.groupType == .managed || groupProxyModel.groupType == .readOnly)
        goTo(state: .informations)
    }
    
    func userWantsToCancelGroupCreationFlow(in controller: GroupCreationAdminChoiceHostingViewController) {
        userWantsToCancelGroupCreationFlow()
    }

}


// MARK: - GroupContactsHostingViewControllerDelegate

extension NewGroupEditionFlowViewController: ContactsSelectionForGroupHostingViewControllerDelegate {
        
    func userDidValidateSelectedContacts(in controller: ContactsSelectionForGroupHostingViewController, selectedContacts: [ObvUICoreData.PersistedObvContactIdentity]) async {
        groupProxyModel.setselectedContacts(to: Set(selectedContacts))
        goTo(state: .selectType)
    }
    
    func userWantsToCancelGroupCreationFlow(in controller: ContactsSelectionForGroupHostingViewController) {
        userWantsToCancelGroupCreationFlow()
    }

}


// MARK: - GroupCreationTypeHostingViewControllerDelegate

extension NewGroupEditionFlowViewController: GroupCreationTypeHostingViewControllerDelegate {
    
    func userDidSelectGroupType(in controller: GroupCreationTypeHostingViewController, selectedGroupType: GroupTypeValue) async {
        groupProxyModel.setGroupTypeValue(to: selectedGroupType)
        switch selectedGroupType {
        case .standard:
            goTo(state: .informations)
        case .managed, .readOnly:
            if groupProxyModel.selectedContacts.isEmpty {
                goTo(state: .informations)
            } else {
                goTo(state: .adminChoice(showButton: true))
            }
        case .advanced:
            goTo(state: .advancedParameters)
        }
    }
 
    
    func userWantsToCancelGroupCreationFlow(in controller: GroupCreationTypeHostingViewController) {
        userWantsToCancelGroupCreationFlow()
    }

}


// MARK: - Finalizing the group creation/modification

extension NewGroupEditionFlowViewController {
    
    private func startCreationFlow(delegate: NewGroupEditionFlowViewControllerGroupCreationDelegate) async {
        
        // Group core details
        
        let groupCoreDetails = GroupV2CoreDetails(groupName: groupProxyModel.groupName, groupDescription: groupProxyModel.groupDescription)
        
        // Group type
        
        guard let groupType = groupProxyModel.groupType else { assertionFailure(); return }
        
        // Own permissions
        
        let ownPermissions = PersistedGroupV2.exactPermissions(of: .admin, forGroupType: groupType)
        
        // Other group members
        
        let otherGroupMembers: [ObvGroupV2.IdentityAndPermissions] = groupProxyModel.selectedContacts
            .map { contact in
                let contactIsAdminOrRegularMember: PersistedGroupV2.AdminOrRegularMember = groupProxyModel.admins.contains(contact) ? .admin : .regularMember
                let contactPermissions = PersistedGroupV2.exactPermissions(of: contactIsAdminOrRegularMember, forGroupType: groupType)
                return .init(identity: contact.cryptoId, permissions: contactPermissions)
            }
        
        // Photo URL
        
        let photoURL = groupProxyModel.groupPicture?.url
        
        // Delegate call
        
        await delegate.userWantsToPublishGroupV2Creation(controller: self,
                                                         groupCoreDetails: groupCoreDetails,
                                                         ownPermissions: ownPermissions,
                                                         otherGroupMembers: Set(otherGroupMembers),
                                                         ownedCryptoId: ownedCryptoId,
                                                         photoURL: photoURL,
                                                         groupType: groupType)
        
    }
    
    
    @MainActor
    private func startUpdateFlow(delegate: NewGroupEditionFlowViewControllerGroupModificationDelegate, groupIdentifier: Data) async throws {
        
        guard let currentPersistedGroup = try PersistedGroupV2.get(ownIdentity: ownedCryptoId, appGroupIdentifier: groupIdentifier, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            throw ObvError.couldNotFindGroupInDatabase
        }
        
        let groupObjectID = currentPersistedGroup.typedObjectID

        // Determine the group type
        
        guard let groupType = groupProxyModel.groupType ?? currentPersistedGroup.groupType else {
            assertionFailure()
            throw ObvError.groupTypeIsNil
        }
                
        // Determine cryptoIds of current members and of selected members
        
        let cryptoIdsOfExistingMembers = Set(currentPersistedGroup.otherMembers.compactMap(\.cryptoId))
        let cryptoIdsOfSelectedMembers = Set(groupProxyModel.selectedContacts.map(\.cryptoId))
        let cryptoIdsOfSelectedAdmins = Set(groupProxyModel.admins.map(\.cryptoId))
        
        // Determine admin and regular members permissions
        
        let permissionsOfAdmin = PersistedGroupV2.exactPermissions(of: .admin, forGroupType: groupType)
        let permissionsOfRegularMember = PersistedGroupV2.exactPermissions(of: .regularMember, forGroupType: groupType)
        
        // Consider all possible kinds of change, and evaluate if a change was made

        var changes = Set<ObvGroupV2.Change>()

        for changeValue in ObvGroupV2.ChangeValue.allCases {
            switch changeValue {
                
            case .memberRemoved:
                let cryptoIdsOfOfMembersToRemove = cryptoIdsOfExistingMembers.subtracting(cryptoIdsOfSelectedMembers)
                cryptoIdsOfOfMembersToRemove.forEach({ changes.insert(.memberRemoved(contactCryptoId: $0)) })

            case .memberAdded:
                let cryptoIdsOfOfMembersToAdd = cryptoIdsOfSelectedMembers.subtracting(cryptoIdsOfExistingMembers)
                cryptoIdsOfOfMembersToAdd.forEach { cryptoId in
                    let isAdmin = cryptoIdsOfSelectedAdmins.contains(cryptoId)
                    changes.insert(.memberAdded(contactCryptoId: cryptoId, permissions: isAdmin ? permissionsOfAdmin : permissionsOfRegularMember))
                }
                
            case .memberChanged:
                let cryptoIdsToConsider = cryptoIdsOfExistingMembers.intersection(cryptoIdsOfSelectedMembers)
                cryptoIdsToConsider.forEach { cryptoId in
                    let isAdmin = cryptoIdsOfSelectedAdmins.contains(cryptoId)
                    guard let existingPermissions = currentPersistedGroup.otherMembers.first(where: { $0.cryptoId == cryptoId })?.permissions else { assertionFailure(); return }
                    let selectedPermissions = isAdmin ? permissionsOfAdmin : permissionsOfRegularMember
                    if existingPermissions != selectedPermissions {
                        changes.insert(.memberChanged(contactCryptoId: cryptoId, permissions: selectedPermissions))
                    }
                }
                
            case .ownPermissionsChanged:
                let existingOwnPermissions = currentPersistedGroup.ownPermissions
                if existingOwnPermissions != permissionsOfAdmin {
                    changes.insert(.ownPermissionsChanged(permissions: permissionsOfAdmin))
                }
                
            case .groupDetails:
                guard let currentGroupCoreDetails = currentPersistedGroup.detailsTrusted?.coreDetails else { assertionFailure(); continue }
                if groupProxyModel.coreDetails != currentGroupCoreDetails {
                    guard let serializedGroupCoreDetails = try? groupProxyModel.coreDetails.jsonEncode() else { assertionFailure(); continue }
                    changes.insert(.groupDetails(serializedGroupCoreDetails: serializedGroupCoreDetails))
                }

            case .groupPhoto:
                let existingPhotoURL = currentPersistedGroup.trustedPhotoURL
                let selectedPhotoURL = groupProxyModel.groupPicture?.url
                if existingPhotoURL != selectedPhotoURL {
                    changes.insert(.groupPhoto(photoURL: selectedPhotoURL))
                }
                
            case .groupType:
                if groupType != currentPersistedGroup.groupType {
                    guard let serializedGroupType = try? groupType.toSerializedGroupType() else { assertionFailure(); continue }
                    changes.insert(.groupType(serializedGroupType: serializedGroupType))
                }
                
            }
        }
        
        // Delegate call
        
        let changeset = try ObvGroupV2.Changeset(changes: changes)
        
        await delegate.userWantsToPublishGroupV2Modification(controller: self,
                                                             groupObjectID: groupObjectID,
                                                             changeset: changeset)
        
    }
    
}


// MARK: Errors

extension NewGroupEditionFlowViewController {
    
    enum ObvError: Error {
        case couldNotDetermineObvGroupV2Identifier
        case groupTypeIsNil
        case couldNotFindGroupInDatabase
    }
    
}
