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
import SwiftUI
import ObvEngine
import ObvTypes
import OSLog
import CoreData
import ObvCrypto
import OlvidUtils
import ObvUICoreData
import ObvSettings
import ObvAppCoreConstants
import ObvAppTypes
import ObvDesignSystem
import ObvUIGroupV1
import ObvUIGroupV2
import ObvUIGroupSharedBetweenV1AndV2
import UniformTypeIdentifiers
import ObvKeycloakManager
import ObvDiscussionsList
import ObvSharedDataSources
import ObvGroupsList
import ObvSingleContact
import ObvCells
import ObvAppNavigation
import ObvSingleOwnedIdentity


class ObvFlowController: UINavigationController {

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ObvFlowController")

    weak var flowDelegate: ObvFlowControllerDelegate?
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ObvFlowController.self))
    let obvEngine: ObvEngine

    private var observationTokens = [NSObjectProtocol]()
    
    private var floatingButton: UIButton?
    private var floatingButtonAnimator: FloatingButtonAnimator?

    let delegatesStack = ObvFlowControllerDelegatesStack()

    private(set) lazy var appNavigationRouter: ObvAppNavigationRouter = {
        .init(dataSources: dataSources.appNavigationRouterDataSources,
              actions: self,
              navigation: self,
              navigationController: self)
    }()

    let dataSources: ObvDataSources

    var currentOwnedCryptoId: ObvCryptoId
    
    private let doAddFloatingButton: Bool
    
    init(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine, dataSources: ObvDataSources, doAddFloatingButton: Bool) {
        self.currentOwnedCryptoId = ownedCryptoId
        self.obvEngine = obvEngine
        self.dataSources = dataSources
        self.doAddFloatingButton = doAddFloatingButton
        
        super.init(rootViewController: UIViewController())
        
        self.delegate = delegatesStack

    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var delegate: UINavigationControllerDelegate? {
        get {
            super.delegate
        }
        set {
            guard newValue is ObvFlowControllerDelegatesStack else { assertionFailure(); return }
            super.delegate = newValue
        }
    }

    // MARK: - Switching current owned identity

    @MainActor
    func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) {
        popToRootViewController(animated: false)
        self.currentOwnedCryptoId = newOwnedCryptoId
    }

}


// MARK: - Floating Plus button

extension ObvFlowController {
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if doAddFloatingButton {
            addFloatingButtonIfRequired()
            let floatingButtonAnimator = FloatingButtonAnimator(floatingButton: floatingButton)
            self.delegatesStack.addDelegate(floatingButtonAnimator)
            self.floatingButtonAnimator = floatingButtonAnimator
        }
    }


    @MainActor
    private func createConfiguredFloatingButton() -> UIButton {
        
        var config = UIButton.Configuration.filled()
        config.buttonSize = .large
        
        config.image = UIImage(systemIcon: .plus)?
            .applyingSymbolConfiguration(.init(pointSize: 22, weight: .semibold))
        config.baseBackgroundColor = UIColor.tintColor // UIColor(named: "Blue01")
        config.title = nil
        config.imagePadding = UIAccessibility.isVoiceOverRunning ? 160 : 50

        let inset: CGFloat
        if #available(iOS 26.0, *) {
            inset = 17
        } else {
            inset = 16
        }
        config.contentInsets = .init(top: inset, leading: inset, bottom: inset, trailing: inset)
        config.cornerStyle = .capsule
        
        let action = UIAction(handler: { [weak self] _ in
            guard let self else { return }
            flowDelegate?.floatingButtonTapped(flow: self)
        })
        
        let button = UIButton(configuration: config, primaryAction: action)
        
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.2
        button.layer.shadowRadius = 8.0

        return button
        
    }
    
    
    @MainActor
    private func addFloatingButtonIfRequired() {
        
        guard floatingButton == nil else { return }
        
        guard let rootViewController = self.viewControllers.first else {
            assertionFailure()
            return
        }
        
        guard !(rootViewController is ObvDiscussionsListViewController) && !(rootViewController is ObvGroupsListViewController) else {
            // Adding 'UIButton' as a subview of UIHostingController.view is not supported and may result in a broken view hierarchy.
            // Since ObvDiscussionsListViewController is a UIHostingController, we do not add the floating button in this case.
            // Instead, the `ObvDiscussionsListView` shows an equivalent SwiftUI implementation of the floating button.
            return
        }
                
        // If we reach this point, we can safely add the floating button to the view hierarchy.
        
        let button = createConfiguredFloatingButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        
        rootViewController.view.addSubview(button)
        
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: rootViewController.view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            button.bottomAnchor.constraint(equalTo: rootViewController.view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            button.widthAnchor.constraint(lessThanOrEqualTo: rootViewController.view.safeAreaLayoutGuide.widthAnchor, multiplier: 1.0),
        ])
        
        floatingButton = button
        
    }

}


// MARK: - Showing/Hiding SnackBar

extension ObvFlowController {
    
    func showSnackBar(with category: OlvidSnackBarCategory, currentOwnedCryptoId: ObvCryptoId, completion: @escaping () -> Void) {
    
        removeSnackBar { [weak self] in
            guard let _self = self else { completion(); return }
            guard let firstVC = _self.children.first else { completion(); return }
            let snackBar = OlvidSnackBarView()
            snackBar.alpha = 0.0
            snackBar.configure(with: category, ownedCryptoId: currentOwnedCryptoId)
            firstVC.view.addSubview(snackBar)
            snackBar.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                snackBar.trailingAnchor.constraint(equalTo: firstVC.view.trailingAnchor),
                snackBar.bottomAnchor.constraint(equalTo: firstVC.view.safeAreaLayoutGuide.bottomAnchor),
                snackBar.leadingAnchor.constraint(equalTo: firstVC.view.leadingAnchor),
            ])
            UIView.animate(withDuration: 0.3) {
                snackBar.alpha = 1.0
            } completion: { _ in
                completion()
            }

        }
        
    }
    
    
    func removeSnackBar(completion: @escaping () -> Void) {
        guard let firstVC = children.first else { completion(); return }
        guard let snackBar = firstVC.view.subviews.compactMap({ $0 as? OlvidSnackBarView }).first else {
            completion()
            return
        }
        UIView.animate(withDuration: 0.3) {
            snackBar.alpha = 0.0
        } completion: { _ in
            snackBar.removeFromSuperview()
            completion()
        }

    }
    
}


// MARK: - Implementing PublishedDetailsValidationViewActionsProtocol

extension ObvFlowController: PublishedDetailsValidationViewActionsProtocol {
    
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ view: GroupPublishedDetailsValidationView, publishedDetails: PublishedDetailsValidationViewModel) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        let groupIdentifier = publishedDetails.groupIdentifier
        switch groupIdentifier {
        case .groupV1(let groupIdentifier):
            try await flowDelegate.userWantsToReplaceTrustedDetailsByPublishedDetails(self, groupIdentifier: groupIdentifier)
        case .groupV2(let groupIdentifier):
            try await flowDelegate.userWantsToReplaceTrustedDetailsByPublishedDetails(self, groupIdentifier: groupIdentifier)
        }
    }

    func userHasSeenPublishedDetails(_ view: GroupPublishedDetailsValidationView, publishedDetails: PublishedDetailsValidationViewModel) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userHasSeenPublishedDetails(self, publishedDetails: publishedDetails)
    }
    
}


// MARK: - Implementing SelectUsersToAddViewActionsForEdition

extension ObvFlowController: SelectUsersToAddViewActionsForEdition {
    
    func userWantsToAddSelectedUsersToExistingGroup(_ view: SelectUsersToAddView.InternalView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) async throws {
        
        guard !userIdentifiers.isEmpty else { return }
        
        switch groupIdentifier {

        case .groupV1(let groupV1Identifier):
            
            let newGroupMembers: [ObvCryptoId] = try userIdentifiers
                .map { identifier in
                    switch identifier {
                    case .contactIdentifier(contactIdentifier: let contactIdentifier):
                        guard groupIdentifier.ownedCryptoId == contactIdentifier.ownedCryptoId else {
                            assertionFailure()
                            throw ObvFlowControllerError.unexpectedOwnedCryptoId
                        }
                        return contactIdentifier.contactCryptoId
                    case .objectIDOfPersistedObvContactIdentity(let objectID):
                        let objectID = TypeSafeManagedObjectID<PersistedObvContactIdentity>(objectID: objectID)
                        guard let contact = try PersistedObvContactIdentity.get(objectID: objectID, within: ObvStack.shared.viewContext) else {
                            assertionFailure()
                            throw ObvFlowControllerError.couldNotFindPendingGroupMember
                        }
                        guard contact.ownedIdentity?.cryptoId == groupIdentifier.ownedCryptoId else {
                            assertionFailure()
                            throw ObvFlowControllerError.unexpectedOwnedCryptoId
                        }
                        return contact.cryptoId
                    }
                }
            
            try await flowDelegate?.userWantsToAddSelectedUsersToExistingGroup(self, groupV1Identifier: groupV1Identifier, newGroupMembers: Set(newGroupMembers))
            
        case .groupV2(let groupIdentifier):
            
            var changes = Set<ObvGroupV2.Change>()
            
            let groupType = try await self.getGroupType(groupIdentifier: groupIdentifier)
            let permissions = ObvGroupType.exactPermissions(of: .regularMember, forGroupType: groupType)
            
            for userIdentifier in userIdentifiers {
                
                let obvContactIdentifier = try await self.getContactIdentifierOfUser(contactIdentifier: userIdentifier)
                
                guard obvContactIdentifier.ownedCryptoId == groupIdentifier.ownedCryptoId else {
                    assertionFailure()
                    throw ObvFlowControllerError.unexpectedOwnedCryptoId
                }
                
                changes.insert(.memberAdded(contactCryptoId: obvContactIdentifier.contactCryptoId, permissions: permissions))
                
            }
            
            guard !changes.isEmpty else { return }
            
            let changeset = try ObvGroupV2.Changeset(changes: changes)
            
            try await self.userWantsToUpdateGroupV2(groupIdentifier: groupIdentifier, changeset: changeset)
        }
        
    }

}


// MARK: - Implementing SingleGroupMemberViewActionsProtocol

extension ObvFlowController: SingleGroupMemberViewActionsProtocol {
    
    // Other protocol conformances are enough
    
}


// MARK: - Implementing PersonalNoteEditorViewActions

extension ObvFlowController: PersonalNoteEditorViewActions {
    
    func userWantsToUpdatePersonalNote(_ view: PersonalNoteEditorView, with newText: String?, about: PersonalNoteEditorView.Model.About) async throws {
        guard let flowDelegate else { assertionFailure(); return }
        try await flowDelegate.userWantsToUpdatePersonalNote(self, with: newText, about: about)
    }

}


// MARK: - Implementing EditGroupNameAndPictureViewActionsForEdition

extension ObvFlowController: EditGroupNameAndPictureViewActionsForEdition {
    
    func userWantsToUpdateGroupNameAndPicture(_ view: EditGroupNameAndPictureView.InternalView, groupIdentifier: ObvGroupIdentifier, changes: Set<EditGroupNameAndPictureView.Change>) async throws {
        guard !changes.isEmpty else { return }
        switch groupIdentifier {
        case .groupV1(let groupV1Identifier):
            guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
            try await flowDelegate.userWantsToUpdateGroupNameAndPicture(self, groupV1Identifier: groupV1Identifier, changes: changes)
        case .groupV2(let groupV2Identifier):
            var groupV2Changes = Set<ObvGroupV2.Change>()
            for change in changes {
                switch change {
                case .groupDetails(groupCoreDetails: let groupCoreDetails):
                    groupV2Changes.insert(.groupDetails(serializedGroupCoreDetails: try groupCoreDetails.jsonEncode()))
                case .groupPhoto(photoURL: let photoURL):
                    groupV2Changes.insert(.groupPhoto(photoURL: photoURL))
                }
            }
            try await self.userWantsToUpdateGroupV2(groupIdentifier: groupV2Identifier, changeset: .init(changes: groupV2Changes))
        }
    }
    
}


// MARK: - Implementing EditGroupNameAndPictureViewActionsProtocol

extension ObvFlowController: EditGroupNameAndPictureViewActionsProtocol {
    
    func userWantsObtainAvatar(_ view: EditGroupNameAndPictureView.InternalView, avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return try await userWantsObtainAvatar(avatarSource: avatarSource, avatarSize: avatarSize)
    }
    
    
    func userWantsToSaveImageToTempFile(_ view: EditGroupNameAndPictureView.InternalView, image: UIImage) async throws -> URL {
        try await userWantsToSaveImageToTempFile(image: image)
    }

}


// MARK: - Implementing SingleGroupV1MainViewActionsProtocol

extension ObvFlowController: SingleGroupV1MainViewActionsProtocol {
    
    func userWantsToLeaveGroup(_ view: SingleGroupV1MainView, groupIdentifier: ObvGroupV1Identifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToLeaveGroup(self, groupIdentifier: .groupV1(groupIdentifier))
    }

    
    func userWantsToDisbandGroup(_ view: SingleGroupV1MainView, groupIdentifier: ObvGroupV1Identifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToDisbandGroup(self, groupIdentifier: .groupV1(groupIdentifier))
    }

}


// MARK: - Implementing SelectUsersToRemoveViewActions

extension ObvFlowController: SelectUsersToRemoveViewActions {
    
    func userWantsToRemoveMembersFromGroup(_ view: SelectUsersToRemoveView, groupIdentifier: ObvGroupIdentifier, membersToRemove: Set<SingleGroupMemberView.Model.Identifier>) async throws {
        
        switch groupIdentifier {
            
        case .groupV1(let groupV1Identifier):
            
            switch groupV1Identifier.groupType {
            case .joined:
                assertionFailure()
                throw ObvFlowControllerError.cannotRemoveMemberForJoinedGroupV1
            case .owned:
                break
            }
            
            let removedGroupMembers: [ObvCryptoId] = try membersToRemove.map { identifier in
                switch identifier {
                case .contactIdentifierForExistingGroupForPreviews:
                    assertionFailure("This identifier kind should only be used in previews")
                    throw ObvFlowControllerError.unexpectedIdentifier
                case .contactIdentifierForCreatingGroupForPreviews:
                    assertionFailure("This identifier kind should only be used in previews")
                    throw ObvFlowControllerError.unexpectedIdentifier
                case .objectIDOfPersistedGroupV2Member:
                    assertionFailure("For now, we don't expect this identifier when removing a member from a group v1.")
                    throw ObvFlowControllerError.unexpectedIdentifier
                case .objectIDOfPersistedContact(objectID: let objectID, _):
                    guard let contact = try PersistedObvContactIdentity.get(objectID: objectID, within: ObvStack.shared.viewContext) else {
                        assertionFailure()
                        throw ObvFlowControllerError.couldNotFindContact
                    }
                    guard contact.ownedIdentity?.cryptoId == groupIdentifier.ownedCryptoId else {
                        assertionFailure()
                        throw ObvFlowControllerError.unexpectedOwnedCryptoId
                    }
                    return contact.cryptoId
                case .objectIDOfPersistedPendingGroupMember(let objectID):
                    let objectID = TypeSafeManagedObjectID<PersistedPendingGroupMember>(objectID: objectID)
                    guard let pendingMember = try PersistedPendingGroupMember.get(objectID: objectID, within: ObvStack.shared.viewContext) else {
                        assertionFailure()
                        throw ObvFlowControllerError.couldNotFindPendingGroupMember
                    }
                    guard try pendingMember.ownedCryptoId == groupIdentifier.ownedCryptoId else {
                        assertionFailure()
                        throw ObvFlowControllerError.unexpectedOwnedCryptoId
                    }
                    return pendingMember.cryptoId
                }
            }
            
            try await flowDelegate?.userWantsToRemoveMembersFromGroupV1(self, groupV1Identifier: groupV1Identifier, removedGroupMembers: Set(removedGroupMembers))
                        
        case .groupV2(let groupIdentifier):
            
            guard !membersToRemove.isEmpty else { return }
            
            for memberToRemove in membersToRemove {
                guard memberToRemove.groupV2Identifier == groupIdentifier else {
                    assertionFailure()
                    throw ObvFlowControllerError.unexpectedGroupIdentifier
                }
            }
            
            guard let persistedGroup = try PersistedGroupV2.get(ownIdentity: groupIdentifier.ownedCryptoId, appGroupIdentifier: groupIdentifier.identifier.appGroupIdentifier, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                throw ObvFlowControllerError.couldNotFindGRoup
            }
            
            let changes: Set<ObvGroupV2.Change> = Set(try membersToRemove.map { memberIdentifier in
                switch memberIdentifier {
                case .contactIdentifierForCreatingGroupForPreviews:
                    assertionFailure("This identifier kind should only be used in previews")
                    throw ObvFlowControllerError.unexpectedIdentifier
                case .contactIdentifierForExistingGroupForPreviews(groupIdentifier: _, contactIdentifier: _):
                    assertionFailure("This identifier kind should only be used in previews")
                    throw ObvFlowControllerError.unexpectedIdentifier
                case .objectIDOfPersistedContact(objectID: _, usageContext: _):
                    assertionFailure("For now, we don't expect this identifier when removing a member from a group v2.")
                    throw ObvFlowControllerError.unexpectedIdentifier
                case .objectIDOfPersistedPendingGroupMember(objectID: _):
                    assertionFailure("For now, we don't expect this identifier when removing a member from a group v2.")
                    throw ObvFlowControllerError.unexpectedIdentifier
                case .objectIDOfPersistedGroupV2Member(groupIdentifier: _, objectID: let objectID):
                    guard let groupMemberToRemove = persistedGroup.otherMembers.first(where: { $0.objectID == objectID }) else {
                        assertionFailure()
                        throw ObvFlowControllerError.groupMemberNotFound
                    }
                    let cryptoId = groupMemberToRemove.cryptoId
                    return .memberRemoved(contactCryptoId: cryptoId)
                }
            })
            let changeset: ObvGroupV2.Changeset = try .init(changes: changes)
            
            try await self.userWantsToUpdateGroupV2(groupIdentifier: groupIdentifier, changeset: changeset)
            
        }
        
    }

}


// MARK: - Implementing ListOfMembersWithAddAndRemoveButtonsViewActions

extension ObvFlowController: ListOfMembersWithAddAndRemoveButtonsViewActions {
    
    // Other protocol conformances are enough

}


// MARK: - Implementing ListOfMembersWithSegmentedControlViewActions

extension ObvFlowController: ListOfMembersWithSegmentedControlViewActions {
 
    // Other protocol conformances are enough

}


// MARK: - Implementing OnetoOneInvitableGroupMembersViewCellActionsProtocol

extension ObvFlowController: OnetoOneInvitableGroupMembersViewCellActionsProtocol {
    
    func userWantsToSendOneToOneInvitationTo(_ view: OnetoOneInvitableGroupMembersViewCell.InternalView, contactIdentifier: ObvContactIdentifier) async throws {
        try userWantsToSendOneToOneInvitationToContact(contactIdentifier: contactIdentifier)
    }
    
    func userWantsToCancelOneToOneInvitationSentTo(_ view: OnetoOneInvitableGroupMembersViewCell.InternalView, contactIdentifier: ObvContactIdentifier) async throws {
        try await cancelSentInviteContactToOneToOne(ownedCryptoId: contactIdentifier.ownedCryptoId,
                                                    contactCryptoId: contactIdentifier.contactCryptoId)
    }

}


// MARK: Implementing OnetoOneInvitableGroupMembersViewActionsProtocol

extension ObvFlowController: OnetoOneInvitableGroupMembersViewActionsProtocol {
    
    func userWantsToSendOneToOneInvitationsTo(_ view: OnetoOneInvitableGroupMembersView.InternalView, contactIdentifiers: [OnetoOneInvitableGroupMembersViewModel.Identifier]) async throws {
        let contactIdentifiers = try getContactIdentifiers(identifiers: contactIdentifiers)
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        let ownedCryptoIds = Set(contactIdentifiers.map { $0.ownedCryptoId })
        guard ownedCryptoIds.count == 1, let ownedCryptoId = ownedCryptoIds.first else { assertionFailure(); return }
        let users: [(cryptoId: ObvCryptoId, keycloakDetails: ObvKeycloakUserDetails?)] = contactIdentifiers.map { contactIdentifier in
            return (contactIdentifier.contactCryptoId, nil)
        }
        try await flowDelegate.userWantsToInviteContactsToOneToOne(self, ownedCryptoId: ownedCryptoId, users: users)
    }

}

// MARK: - Implementing EditGroupTypeViewActionsForEdition

extension ObvFlowController: EditGroupTypeViewActionsForEdition {
 
    func userWantsToUpdateGroupV2(_ view: EditGroupTypeView, groupIdentifier: ObvGroupV2Identifier, changeset: ObvGroupV2.Changeset) async throws {
        Self.logger.debug("🧑‍🧑‍🧒‍🧒 Call to userWantsToUpdateGroupV2(_ router: ObvUIGroupV2Router, groupIdentifier: ObvGroupV2Identifier, changeset: ObvGroupV2.Changeset)")
        try await self.userWantsToUpdateGroupV2(groupIdentifier: groupIdentifier, changeset: changeset)
    }

}


// MARK: - Implementing FullListOfGroupMembersViewActionsInEditAdminsMode

extension ObvFlowController: FullListOfGroupMembersViewActionsInEditAdminsMode {
    
    func userWantsToUpdateGroupV2(_ view: FullListOfGroupMembersView.InternalView, groupIdentifier: ObvGroupV2Identifier, changeset: ObvGroupV2.Changeset) async throws {
        Self.logger.debug("🧑‍🧑‍🧒‍🧒 Call to userWantsToUpdateGroupV2(_ router: ObvUIGroupV2Router, groupIdentifier: ObvGroupV2Identifier, changeset: ObvGroupV2.Changeset)")
        try await self.userWantsToUpdateGroupV2(groupIdentifier: groupIdentifier, changeset: changeset)
    }

}


// MARK: - Implementing EditGroupTypeNavigationStackActions

extension ObvFlowController: EditGroupTypeNavigationStackActions {
    
    // Other protocol conformances are enough

}


// MARK: - Implementing SingleGroupV2MainViewActionsProtocol

extension ObvFlowController: SingleGroupV2MainViewActionsProtocol {
    
    func userWantsToLeaveGroup(_ view: SingleGroupV2MainView, groupIdentifier: ObvGroupV2Identifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToLeaveGroup(self, groupIdentifier: .groupV2(groupIdentifier))
    }
    
    func userWantsToDisbandGroup(_ view: SingleGroupV2MainView, groupIdentifier: ObvGroupV2Identifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToDisbandGroup(self, groupIdentifier: .groupV2(groupIdentifier))
    }

    func userTappedOnManualResyncOfGroupV2Button(_ view: SingleGroupV2MainView, groupIdentifier: ObvGroupV2Identifier) async throws {
        guard let persistedGroup = try PersistedGroupV2.get(groupIdentifier: groupIdentifier, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            throw ObvFlowControllerError.couldNotFindGRoup
        }
        if persistedGroup.keycloakManaged {
            try await KeycloakManagerSingleton.shared.syncAllManagedIdentities()
        } else {
            try await obvEngine.performReDownloadOfGroupV2(ownedCryptoId: groupIdentifier.ownedCryptoId, groupIdentifier: groupIdentifier.identifier.appGroupIdentifier)
        }
    }

}


// MARK: - Implementing ObvSingleContactViewActions

extension ObvFlowController: ObvSingleContactViewActions {
    
    func userWantsToReblockContact(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToReblockContact(self, contactIdentifier: contactIdentifier)
    }


    func userWantsToRestartChannelCreationWithContact(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        try await obvEngine.restartAllOngoingChannelEstablishmentProtocolsWithContactIdentity(contactIdentifier: contactIdentifier)
    }

    
    func userWantsToReplaceTrustedContactDetailsByPublishedContactDetails(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier, publishedDetails: ObvTypes.ObvIdentityDetails) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToUpdateTrustedIdentityDetailsOfContactIdentity(self, contactIdentifier: contactIdentifier, using: publishedDetails)
    }

    
    func userWantsToUnblockContact(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        try await obvEngine.unblockContactIdentity(contactIdentifier: contactIdentifier)
    }
    
    
    func userWantsToCancelTheOneToOneInvitationSentToContact(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToRemoveOneToOneInvitationSent(self, contactIdentifier: contactIdentifier)
    }

    
    func userWantsToSendOneToOneInvitationToContact(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        try userWantsToSendOneToOneInvitationToContact(contactIdentifier: contactIdentifier)
    }

    
    func userWantsToRemoveContactFromTheirContacts(_ view: ObvSingleContact.ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier, contactDeletionType: ObvSingleContact.ObvSingleContactView.Model.ContactDeletionType) async throws {
        
        assert(Thread.isMainThread)

        guard let persistedContact = try PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) else {
            // The contact doesn't exist, no deletion required
            return
        }

        // When the user wants to delete a contact, we have 2 main cases to consider :
        // Main case 1: the contact has the .oneToOneContacts capability
        // Main case 2: they do not.

        if persistedContact.supportsCapability(.oneToOneContacts) {
            
            // We are in the Main case 1 as the contact supports the oneToOneContacts capability.
            // In that case, if she is a OneToOne contact, we want to downgrade her to be non-OneToOne.
            // Otherwise, we are in the same situation as if we were in Main case 2 (as we want to delete the identity).
            
            if persistedContact.isOneToOne {
                
                guard contactDeletionType == .downgradeToNonOneToOne else {
                    assertionFailure()
                    throw ObvFlowControllerError.inappropriateContactDeletionType
                }
                
                try await obvEngine.downgradeOneToOneContact(contactIdentifier: contactIdentifier)

            } else {

                guard contactDeletionType == .fullDeletion else {
                    assertionFailure()
                    throw ObvFlowControllerError.inappropriateContactDeletionType
                }

                try await obvEngine.deleteContactIdentity(contactIdentifier: contactIdentifier)
                
            }

            
        } else {
            
            guard contactDeletionType == .legacyFullDeletion || contactDeletionType == .fullDeletion else {
                assertionFailure()
                throw ObvFlowControllerError.inappropriateContactDeletionType
            }
            
            try await obvEngine.deleteContactIdentity(contactIdentifier: contactIdentifier)

        }
        
    }

    
    func userWantsToSyncOneToOneStatusOfContact(_ view: ObvSingleContactView, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        try await obvEngine.requestOneStatusSyncRequest(ownedIdentity: contactIdentifier.ownedCryptoId, contactsToSync: [contactIdentifier.contactCryptoId])
    }

    
    func userDidSeeNewDetailsOfContact(_ view: ObvSingleContactView, contactIdentifier: ObvContactIdentifier) {
        guard let flowDelegate else { assertionFailure(); return }
        flowDelegate.userDidSeeNewDetailsOfContact(self, contactIdentifier: contactIdentifier)
    }

}


// MARK: - Implementing ObvContactDeviceViewActions

extension ObvFlowController: ObvContactDeviceViewActions {
    
    func userWantsToRestartChannelCreationWithContactDevice(_ view: ObvContactDeviceView, contactDeviceIdentifier: ObvContactDeviceIdentifier) async throws {
        try await obvEngine.recreateChannelWithContactDevice(contactIdentifier: contactDeviceIdentifier.contactIdentifier, contactDeviceIdentifier: contactDeviceIdentifier.deviceUID.raw)
    }
    
}


// MARK: - Implementing ObvListOfContactDevicesViewActions

extension ObvFlowController: ObvListOfContactDevicesViewActions {
    
    func userWantsToSearchForNewContactDevices(_ view: ObvListOfContactDevicesView, contactIdentifier: ObvContactIdentifier) async throws {
        try await obvEngine.performContactDeviceDiscovery(contactIdentifier: contactIdentifier)
    }
    
    func userWantsToClearAllContactDevices(_ view: ObvListOfContactDevicesView, contactIdentifier: ObvContactIdentifier) async throws {
        try await obvEngine.deleteAllContactDevicesAndChannelsThenPerformContactDeviceDiscovery(contactIdentifier: contactIdentifier)
    }

}


// MARK: - Implementing ObvPresentedNavigationStackActions

extension ObvFlowController: ObvPresentedNavigationStackActions {
    
    // Other protocol conformances are enough

}


// MARK: - Implementing ObvAppNavigationRouterNavigation

extension ObvFlowController: ObvAppNavigationRouterNavigation {
    
    func userWantsToNavigateToOneToOneDiscussionWithContact(_ router: ObvAppNavigationRouter, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        try self.userWantsToNavigateToOneToOneDiscussionWithContact(contactIdentifier: contactIdentifier)
    }
    
    func userWantsToNavigateToGroupDiscussion(_ router: ObvAppNavigationRouter, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) {
        Task { await self.userWantsToNavigateToDiscussion(groupIdentifier: groupIdentifier, messageToShowObjectID: nil) }
    }
    
    func userWantsToCallContact(_ router: ObvAppNavigationRouter, contactIdentifier: ObvTypes.ObvContactIdentifier) {
        self.userWantsToCallContact(contactIdentifier: contactIdentifier)
    }
    
    func userWantsToCall(_ router: ObvAppNavigationRouter, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) {
        self.userWantsToCall(groupIdentifier: groupIdentifier)
    }
    
    func userWantsToEditContactNicknameAndCustomPicture(_ router: ObvAppNavigationRouter, contactIdentifier: ObvTypes.ObvContactIdentifier) {
        self.userWantsToEditContactNicknameAndCustomPicture(contactIdentifier: contactIdentifier)
    }
    
    func userWantsToEditGroupNicknameAndCustomPicture(_ router: ObvAppNavigationRouter, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) {
        self.userWantsToEditGroupNicknameAndCustomPicture(groupIdentifier: groupIdentifier)
    }
    
    func userWantsToIntroduceOneContactToAnother(_ router: ObvAppNavigationRouter, contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        Task { await presentContactsPresentationViewController(contactIdentifier: contactIdentifier) }
    }
    
    func userWantsToCreateNewGroupWithContact(_ router: ObvAppNavigationRouter, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        try await userWantsToCreateNewGroupWithContact(contactIdentifier: contactIdentifier)
    }
    
    func userWantsToCloneGroup(_ router: ObvAppNavigationRouter, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) async throws {
        try await self.userWantsToCloneGroup(groupIdentifier: groupIdentifier)
    }

}


// MARK: - Implementing EditNicknameAndCustomPictureViewControllerDelegate

extension ObvFlowController: EditNicknameAndCustomPictureViewControllerDelegate {
    
    func userWantsToSaveNicknameAndCustomPicture(controller: EditNicknameAndCustomPictureViewController, identifier: EditNicknameAndCustomPictureView.Model.IdentifierKind, nickname: String, customPhoto: UIImage?) async {
        
        let ownedCryptoId: ObvCryptoId = self.currentOwnedCryptoId
        
        switch identifier {
        case .contact(contactIdentifier: let contactIdentifier):
            guard let persistedContact = try? PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                return
            }
            let sanitizedNickname = nickname.trimmingWhitespacesAndNewlines()
            let newNickname = sanitizedNickname.isEmpty ? nil : sanitizedNickname
            ObvMessengerInternalNotification.userWantsToEditContactNicknameAndPicture(
                persistedContactObjectID: persistedContact.objectID,
                customDisplayName: newNickname,
                customPhoto: customPhoto)
            .postOnDispatchQueue()
            
        case .groupV2(let groupV2Identifier):
            guard let group = try? PersistedGroupV2.getWithPrimaryKey(ownCryptoId: ownedCryptoId, groupIdentifier: groupV2Identifier, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                return
            }
            guard group.groupIdentifier == groupV2Identifier else { assertionFailure(); return }
            let sanitizedNickname = nickname.trimmingWhitespacesAndNewlines()
            ObvMessengerInternalNotification.userWantsToUpdateCustomNameAndGroupV2Photo(
                ownedCryptoId: ownedCryptoId,
                groupIdentifier: groupV2Identifier,
                customName: sanitizedNickname,
                customPhoto: customPhoto)
            .postOnDispatchQueue()
            
        case .groupV1(groupV1Identifier: let groupV1Identifier):
            let groupIdentifier = ObvGroupV1Identifier(ownedCryptoId: ownedCryptoId, groupV1Identifier: groupV1Identifier)
            guard (try? PersistedContactGroup.getContactGroup(groupIdentifier: groupIdentifier, within: ObvStack.shared.viewContext)) != nil else {
                assertionFailure()
                return
            }
            let sanitizedNickname = nickname.trimmingWhitespacesAndNewlines()
            ObvMessengerInternalNotification.userWantsToUpdateCustomNameAndGroupV1Photo(
                groupIdentifier: groupIdentifier,
                customName: sanitizedNickname,
                customPhoto: customPhoto)
            .postOnDispatchQueue()
        }
        
        controller.dismiss(animated: true)
        
    }
    
    
    func userWantsToDismissEditNicknameAndCustomPictureViewController(controller: EditNicknameAndCustomPictureViewController) async {
        controller.dismiss(animated: true)
    }

}


// MARK: - Implementing SingleDiscussionViewControllerDelegate

extension ObvFlowController: SingleDiscussionViewControllerDelegate {
    
    func userTappedTitleOfDiscussion(_ vc: NewSingleDiscussionViewController, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) {
        guard let flowDelegate else { assertionFailure(); return }
        do {
            
            guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectID.objectID, within: ObvStack.shared.viewContext) else {
                throw ObvFlowControllerError.couldNotFindDiscussion
            }
            
            let root: ObvPresentedNavigationStack.NavigationStackRootView
            
            switch try discussion.kind {
                
            case .oneToOne(withContactIdentity: let contactIdentity):
                
                // In case the title tapped is the one of a one2one discussion, we display the contact sheet of the contact
                guard let contactIdentifier = try? contactIdentity?.obvContactIdentifier else {
                    os_log("Could not determine contact identifier. This is ok if it has just been deleted.", log: log, type: .error)
                    return
                }
                
                root = .contactDetails(contactIdentifier: contactIdentifier)
                
            case .groupV1(withContactGroup: let contactGroup):
                
                guard let groupV1Identifier = try? contactGroup?.obvGroupIdentifier else {
                    Self.logger.error("Could not determine contact group identifier (this is ok if it was just deleted)")
                    return
                }
                
                root = .groupV1Details(groupV1Identifier: groupV1Identifier)
                
            case .groupV2(withGroup: let group):
                
                guard let groupV2Identifier = try? group?.obvGroupIdentifier else {
                    os_log("Could find group V2 (this is ok if it was just deleted)", log: log, type: .error)
                    return
                }
                
                root = .groupV2Details(groupV2Identifier: groupV2Identifier)
                
            }
            
            // On macOS, the discussion flow may become inactive if the user switches tabs (e.g., to Contacts)
            // while in a discussion. Since the `NavigationStackRootView` cannot be presented off-screen,
            // we request the active navigation controller from our delegate to ensure proper presentation.
            // This call is unnecessary on iOS, where the view hierarchy remains consistent.
            let presentingViewController = try flowDelegate.appropriateViewControllerToPresentViewController(self)
            
            appNavigationRouter.presentNavigationStack(root: root, on: presentingViewController)
            
        } catch {
            assertionFailure()
        }
    }
        
    
    func userDidTapOnContactImage(contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>) {
        
        assert(Thread.isMainThread)
        
        guard let contactIdentity = try? PersistedObvContactIdentity.get(objectID: contactObjectID, within: ObvStack.shared.viewContext) else {
            os_log("Could not find contact identity. This is ok if it has just been deleted.", log: log, type: .error)
            return
        }
        
        guard let contactIdentifier = try? contactIdentity.obvContactIdentifier else { assertionFailure(); return }
        
        appNavigationRouter.presentNavigationStack(root: .contactDetails(contactIdentifier: contactIdentifier), on: self)
        
    }
    

    /// Called when the user taps on a mention in a single discussion view controller. In that case, we present the appropriate detail view controller, depending on the ``mentionableIdentity`` that was tapped.
    func singleDiscussionViewController(_ viewController: any SomeSingleDiscussionViewController, userDidTapOn mentionableIdentity: ObvMentionableIdentityAttribute.Value) async {
        
        switch mentionableIdentity {
            
        case .ownedIdentity(ownedCryptoId: let ownedCryptoId):
            
            userWantsToPresentMyId(ownedCryptoId: ownedCryptoId)
            
        case .contact(let contactIdentifier):
            
            let root: ObvPresentedNavigationStack.NavigationStackRootView = .contactDetails(contactIdentifier: contactIdentifier)
            appNavigationRouter.presentNavigationStack(root: root, on: self)
            
        case .groupV2Member(groupIdentifier: let groupIdentifier, memberId: _):
            
            let root: ObvPresentedNavigationStack.NavigationStackRootView = .groupV2Details(groupV2Identifier: groupIdentifier)
            appNavigationRouter.presentNavigationStack(root: root, on: self)
            
        }
    }

    
    func userWantsToSendDraft(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, textBody: String, mentions: Set<MessageJSON.UserMention>) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToSendDraft(self, draftObjectID: draftObjectID, textBody: textBody, mentions: mentions)
    }
    

    func userWantsToAddAttachmentsToDraft(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, itemProviders: [NSItemProvider], source: LoadItemProviderHelper.ItemProviderProviderSource) async throws -> [LoadedItemProviderToPaste] {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        return try await flowDelegate.userWantsToAddAttachmentsToDraft(self, draftObjectID: draftObjectID, itemProviders: itemProviders, source: source)
    }

    
    func userWantsToAddAttachmentsToDraftFromURLs(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, urls: [URL]) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToAddAttachmentsToDraftFromURLs(self, draftObjectID: draftObjectID, urls: urls)
    }

    
    func userWantsToUpdateDraftBodyAndMentions(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, body: String, mentions: Set<MessageJSON.UserMention>) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToUpdateDraftBodyAndMentions(self, draftObjectID: draftObjectID, body: body, mentions: mentions)
    }

    
    func userWantsToDeleteAttachmentsFromDraft(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, draftTypeToDelete: DeleteAllDraftFyleJoinOfDraftOperation.DraftType) async {
        guard let flowDelegate else { assertionFailure(); return }
        await flowDelegate.userWantsToDeleteAttachmentsFromDraft(self, draftObjectID: draftObjectID, draftTypeToDelete: draftTypeToDelete)
    }

    
    func userWantsToReplyToMessage(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToReplyToMessage(self, messageObjectID: messageObjectID, draftObjectID: draftObjectID)
    }

    
    func userWantsToDownloadReceivedFyleMessageJoinWithStatus(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToDownloadReceivedFyleMessageJoinWithStatus(self, receivedJoinObjectID: receivedJoinObjectID)
    }

    
    func userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(self, receivedJoinObjectID: receivedJoinObjectID)
    }

    
    func userWantsToDownloadSentFyleMessageJoinWithStatusFromOtherOwnedDevice(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToDownloadSentFyleMessageJoinWithStatusFromOtherOwnedDevice(self, sentJoinObjectID: sentJoinObjectID)
    }

    
    func userWantsToPauseSentFyleMessageJoinWithStatusFromOtherOwnedDevice(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToPauseSentFyleMessageJoinWithStatusFromOtherOwnedDevice(self, sentJoinObjectID: sentJoinObjectID)
    }

    
    func userWantsToRemoveReplyToMessage(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToRemoveReplyToMessage(self, draftObjectID: draftObjectID)
    }

    
    func insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, markAsRead: Bool) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(self, discussionObjectID: discussionObjectID, markAsRead: markAsRead)
    }

    
    func userWantsToUpdateDraftExpiration(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, value: PersistedDiscussionSharedConfigurationValue?) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToUpdateDraftExpiration(self, draftObjectID: draftObjectID, value: value)
    }

    
    func userWantsToReadReceivedMessageThatRequiresUserAction(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageId: ReceivedMessageIdentifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToReadReceivedMessageThatRequiresUserAction(self, ownedCryptoId: ownedCryptoId, discussionId: discussionId, messageId: messageId)
    }

    
    func updatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentIDs: Set<ObvManagedObjectPermanentID<PersistedMessage>>) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.updatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(self, discussionPermanentID: discussionPermanentID, messagePermanentIDs: messagePermanentIDs)
    }

    
    func messagesAreNotNewAnymore(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageIds: [MessageIdentifier]) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.messagesAreNotNewAnymore(self, ownedCryptoId: ownedCryptoId, discussionId: discussionId, messageIds: messageIds)
    }

    
    func userWantsToUpdateReaction(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, newEmoji: String?) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToUpdateReaction(self, ownedCryptoId: ownedCryptoId, messageObjectID: messageObjectID, newEmoji: newEmoji)
    }

    
    func userWantsToUpdatePollVote(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, pollVoteCandidateUuid: UUID, voted: Bool, version: Int) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToUpdatePollVote(self, ownedCryptoId: ownedCryptoId, messageObjectID: messageObjectID, pollVoteCandidateUuid: pollVoteCandidateUuid, voted: voted, version: version)
    }

    
    /// Called when the user taps on a message representing `PersistedLocationContinuous`.
    func userWantsToShowMapToConsultLocationSharedContinously(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToShowMapToConsultLocationSharedContinously(self, presentingViewController: singleDiscussionViewController, messageObjectID: messageObjectID)
    }

    
    func userWantsToShowMapToSendOrShareLocationContinuously(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToShowMapToSendOrShareLocationContinuously(self, presentingViewController: singleDiscussionViewController, discussionIdentifier: discussionIdentifier)
    }

    
    func userWantsToCreatePoll(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToCreatePoll(self, presentingViewController: singleDiscussionViewController, discussionIdentifier: discussionIdentifier)
    }

    
    func userWantsToDisplayPollView(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, pollObjectID: TypeSafeManagedObjectID<PersistedPoll>) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToDisplayPollView(self, presentingViewController: singleDiscussionViewController, pollObjectID: pollObjectID)
    }

    
    func userWantsToStopSharingLocationInDiscussion(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToStopSharingLocationInDiscussion(self, discussionIdentifier: discussionIdentifier)
    }

    
    func userWantsToProcessReceiptsStoredForLater(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, ownedCryptoId: ObvCryptoId, returnReceiptElements: Set<ObvReturnReceiptElements>) async {
        guard let flowDelegate else { assertionFailure(); return }
        await flowDelegate.userWantsToProcessReceiptsStoredForLater(self, ownedCryptoId: ownedCryptoId, returnReceiptElements: returnReceiptElements)
    }

    
    func discussionViewWillAppear(_ singleDiscussionViewController: any SomeSingleDiscussionViewController) {
        guard let discussionId = singleDiscussionViewController.discussionId else { return }
        OlvidUserActivitySingleton.shared.switchCurrentDiscussion(to: discussionId, viewController: self)
    }

    
    func discussionViewWillDisappear(_ singleDiscussionViewController: any SomeSingleDiscussionViewController) {
        guard let discussionId = singleDiscussionViewController.discussionId else { return }
        guard let currentUserActivity = OlvidUserActivitySingleton.shared.currentUserActivity else { return }
        if currentUserActivity.currentDiscussion == discussionId {
            OlvidUserActivitySingleton.shared.switchCurrentDiscussion(to: nil, viewController: self)
        }
    }

    
    func userWantsToDisplayContactIntroductionScreen(_ singleDiscussionViewController: any SomeSingleDiscussionViewController, contactIdentifier: ObvContactIdentifier) {
        Task { await presentContactsPresentationViewController(contactIdentifier: contactIdentifier) }
    }

}


// MARK: - Implementing UnlockingHiddenProfileDelegate

extension ObvFlowController: UnlockingHiddenProfileDelegate {
    
    func showAlertForUnlockingHiddenOwnedIdentity() {
        guard let flowDelegate else { assertionFailure(); return }
        flowDelegate.showAlertForUnlockingHiddenOwnedIdentity(self)
    }

}


// MARK: - Implementing ObvGroupsListViewNavigation

extension ObvFlowController: ObvGroupsListViewNavigation {
    
    func userDidPressOnObvGroupCellView(_ view: ObvGroupCellView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, expectedNavigation: ObvGroupCellView.ExpectedNavigation) throws {
        
        guard let displayedContactGroup = try? DisplayedContactGroup.getDisplayedContactGroup(groupIdentifier: groupIdentifier, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            return
        }
        
        switch expectedNavigation {
            
        case .groupDiscussion:
            
            guard let discussionIdentifier = displayedContactGroup.discussionIdentifier else { assertionFailure(); return }
            let deepLink = ObvDeepLink.singleDiscussion(discussionIdentifier: discussionIdentifier)
            ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                .postOnDispatchQueue()
            
        case .groupDetails:
            
            let navigation = (self.presentedViewController as? UINavigationController) ?? self
            
            do {
                let groupIdentifier = try displayedContactGroup.groupIdentifier
                self.userWantsToNavigateToSingleGroupView(groupIdentifier: groupIdentifier, within: navigation)
            } catch {
                assertionFailure()
            }
            
        }
        
    }
    
}


// MARK: - Helper methods for subclasses or other classes

extension ObvFlowController {

    func userWantsToDisplay(persistedMessage message: PersistedMessage) {
        guard let discussion = message.discussion else { assertionFailure(); return }
        Task {
            await userWantsToNavigateToDiscussion(discussionObjectID: discussion.typedObjectID, messageToShowObjectID: message.typedObjectID)
        }
    }

    
    func userWantsToNavigateToSingleGroupView(_ group: DisplayedContactGroup, within nav: UINavigationController?) {
        assert(group.groupV1 == nil || group.groupV2 == nil)
        let appropriateNav = nav ?? self
        do {
            let groupIdentifier = try group.groupIdentifier
            userWantsToNavigateToSingleGroupView(groupIdentifier: groupIdentifier, within: appropriateNav)
        } catch {
            assertionFailure()
        }
    }

    
    /// Helper method when a discussion gets deleted.
    func refreshAllSingleDiscussionViewControllerForDiscussion(_ discussion: PersistedDiscussion) async throws {
        let newStack = try self.viewControllers.compactMap { viewController in
            guard let someSingleDiscussionVC = viewController as? SomeSingleDiscussionViewController else { return viewController }
            if someSingleDiscussionVC.discussionPermanentID != discussion.discussionPermanentID {
                return someSingleDiscussionVC
            } else {
                return try getNewSingleDiscussionViewController(discussionObjectID: discussion.typedObjectID, initialScroll: .newMessageSystemOrLastMessage)
            }
        }
        self.setViewControllers(newStack, animated: false)
    }

    
    func userWantsToDisplay(persistedDiscussion discussion: PersistedDiscussion) {
        Task {
            await userWantsToNavigateToDiscussion(discussionObjectID: discussion.typedObjectID, messageToShowObjectID: nil)
        }
    }
    
    
    func removeAllSomeSingleDiscussionViewControllerForDiscussionWithPermanentID(_ discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) async {
        let newStack = self.viewControllers.compactMap { viewController in
            guard let someSingleDiscussionVC = viewController as? SomeSingleDiscussionViewController else { return viewController }
            return (someSingleDiscussionVC.discussionPermanentID == discussionPermanentID) ? nil : someSingleDiscussionVC
        }
        self.setViewControllers(newStack, animated: true)
    }

    
    func getNewSingleDiscussionViewController(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, initialScroll: NewSingleDiscussionViewController.InitialScroll) throws -> NewSingleDiscussionViewController {
        guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectID, within: ObvStack.shared.viewContext) else {
            throw ObvFlowControllerError.couldNotFindDiscussion
        }
        assert(Thread.isMainThread)
        let singleDiscussionVC = try NewSingleDiscussionViewController(
            discussion: discussion,
            delegate: self,
            initialScroll: initialScroll,
            avatarViewDataSource: self.dataSources.avatarViewDataSource,
            messageReactionsViewDataSource: self.dataSources.messageReactionsViewDataSource)
        singleDiscussionVC.hidesBottomBarWhenPushed = true
        return singleDiscussionVC
    }

}


// MARK: - Private helper functions

extension ObvFlowController {
    
    /// Called during the cloning of an existing group, to get all the initial values of the new group.
    private func getValuesOfGroupToClone(identifierOfGroupToClone: ObvGroupIdentifier) throws -> ObvUIGroupV2.ObvGroupV2CreationRouter.ValuesOfClonedGroup {
        assert(Thread.isMainThread)
        switch identifierOfGroupToClone {
        case .groupV1(let groupV1Identifier):
            guard let groupV1 = try? PersistedContactGroup.getContactGroup(groupIdentifier: groupV1Identifier, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                throw ObvFlowControllerError.groupIsNil
            }
            let valuesOfClonedGroup = try ObvUIGroupV2.ObvGroupV2CreationRouter.ValuesOfClonedGroup(persistedContactGroup: groupV1)
            return valuesOfClonedGroup
        case .groupV2(let groupV2Identifier):
            guard let persistedGroup = try PersistedGroupV2.get(ownIdentity: identifierOfGroupToClone.ownedCryptoId, appGroupIdentifier: groupV2Identifier.identifier.appGroupIdentifier, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                throw ObvFlowControllerError.groupIsNil
            }
            let valuesOfClonedGroup = try ObvUIGroupV2.ObvGroupV2CreationRouter.ValuesOfClonedGroup(persistedGroup: persistedGroup)
            return valuesOfClonedGroup
        }
        
    }

    
    private func userWantsToCreateNewGroupWithContact(contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        // We simulate a group clone to start a group creation process with an initial selected user
        guard let contact = try? PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) else {
            throw ObvFlowControllerError.couldNotFindContact
        }
        let initialValues = ObvGroupV2CreationRouter.ValuesOfClonedGroup(
            userIdentifiersOfAddedUsers: [.objectIDOfPersistedObvContactIdentity(objectID: contact.objectID)],
            selectedAdmins: [.objectIDOfPersistedContact(objectID: contact.objectID, usageContext: .groupCreation)],
            selectedGroupType: .standard,
            selectedPhoto: nil,
            selectedGroupName: nil,
            selectedGroupDescription: nil)
        try await flowDelegate.userWantsToCloneGroup(self, valuesOfGroupToClone: initialValues)
    }

    
    private func userWantsToEditContactNicknameAndCustomPicture(contactIdentifier: ObvContactIdentifier) {
        guard let persistedContact = try? PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            return
        }
        guard let contactInitial = persistedContact.circledInitialsConfiguration.initials?.text else { assertionFailure(); return }
        let contactPhoto: UIImage?
        if let url = persistedContact.photoURL {
            contactPhoto = UIImage(contentsOfFile: url.path)
        } else {
            contactPhoto = nil
        }
        let currentCustomPhoto: UIImage?
        if let url = persistedContact.customPhotoURL {
            currentCustomPhoto = UIImage(contentsOfFile: url.path)
        } else {
            currentCustomPhoto = nil
        }
        let currentNickname = persistedContact.customDisplayName ?? ""
        let vc = EditNicknameAndCustomPictureViewController(
            model: .init(identifier: .contact(contactIdentifier: contactIdentifier),
                         currentInitials: contactInitial,
                         defaultPhoto: contactPhoto,
                         currentCustomPhoto: currentCustomPhoto,
                         currentNickname: currentNickname),
            delegate: self)
        presentOnTop(vc, animated: true)
    }

    
    private func userWantsToCallContact(contactIdentifier: ObvTypes.ObvContactIdentifier) {
        let ownedCryptoId = contactIdentifier.ownedCryptoId
        let contactCryptoId = contactIdentifier.contactCryptoId
        ObvMessengerInternalNotification.userWantsToCallOrUpdateCallCapabilityButWeShouldCheckSheIsAllowedTo(ownedCryptoId: ownedCryptoId, contactCryptoIds: Set([contactCryptoId]), groupId: nil, startCallIntent: nil)
            .postOnDispatchQueue()
    }

    
    private func getContactIdentifiers(identifiers: [ObvUIGroupSharedBetweenV1AndV2.OnetoOneInvitableGroupMembersViewModel.Identifier]) throws -> [ObvTypes.ObvContactIdentifier] {
        var contactIdentifiers = [ObvTypes.ObvContactIdentifier]()
        for identifier in identifiers {
            switch identifier {
            case .contactIdentifier(contactIdentifier: let contactIdentifier):
                contactIdentifiers.append(contactIdentifier)
            case .objectIDOfPersistedGroupV2Member(objectID: let objectID):
                guard let groupMember = try PersistedGroupV2Member.get(objectID: objectID, within: ObvStack.shared.viewContext) else {
                    assertionFailure()
                    continue
                }
                if let contactIdentifier: ObvContactIdentifier = try groupMember.contact?.obvContactIdentifier {
                    contactIdentifiers.append(contactIdentifier)
                }
            case .objectIDOfPersistedObvContactIdentity(objectID: let objectID):
                guard let contact = try PersistedObvContactIdentity.get(objectID: objectID, within: ObvStack.shared.viewContext) else {
                    assertionFailure()
                    continue
                }
                let contactIdentifier: ObvContactIdentifier = try contact.obvContactIdentifier
                contactIdentifiers.append(contactIdentifier)
            case .objectIDOfPersistedPendingGroupMember(objectID: let objectID):
                do {
                    let objectID = TypeSafeManagedObjectID<PersistedPendingGroupMember>(objectID: objectID)
                    guard let pendingMember = try PersistedPendingGroupMember.get(objectID: objectID, within: ObvStack.shared.viewContext) else {
                        assertionFailure()
                        continue
                    }
                    let contactIdentifier = ObvContactIdentifier(contactCryptoId: pendingMember.cryptoId, ownedCryptoId: try pendingMember.ownedCryptoId)
                    // We want to make sure the pending member is indeed a contact before returning the contact identifier
                    guard try PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) != nil else {
                        // The pending members is not a contact, we do not return a contact identifier for them
                        continue
                    }
                    contactIdentifiers.append(contactIdentifier)
                } catch {
                    assertionFailure()
                    continue
                }
            }
        }
        return contactIdentifiers
    }

    
    private func userWantsToSaveImageToTempFile(image: UIImage) async throws -> URL {
        guard let jpegData = image.jpegData(compressionQuality: 1.0) else { assertionFailure(); throw ObvFlowControllerError.couldNotGenerateJPEGData }
        let filename = [UUID().uuidString, UTType.jpeg.preferredFilenameExtension ?? "jpeg"].joined(separator: ".")
        let directoryForTempFiles = ObvUICoreDataConstants.ContainerURL.forTempFiles.url
        let filepath = directoryForTempFiles.appendingPathComponent(filename)
        try jpegData.write(to: filepath)
        return filepath
    }

    
    private func userWantsObtainAvatar(avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        return try await flowDelegate.userWantsObtainAvatar(self, avatarSource: avatarSource, avatarSize: avatarSize)
    }

    
    private func userWantsToUpdateGroupV2(groupIdentifier: ObvGroupV2Identifier, changeset: ObvGroupV2.Changeset) async throws {
        
        guard !changeset.isEmpty else { return }
        
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        
        guard let persistedGroup = try PersistedGroupV2.get(ownIdentity: groupIdentifier.ownedCryptoId, appGroupIdentifier: groupIdentifier.identifier.appGroupIdentifier, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            throw ObvFlowControllerError.couldNotFindGRoup
        }
        
        let groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2> = .init(objectID: persistedGroup.objectID)
        
        try await flowDelegate.userWantsToPublishGroupV2Modification(self, groupObjectID: groupObjectID, changeset: changeset)
        
    }

    
    private func getContactIdentifierOfUser(contactIdentifier: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier) async throws -> ObvTypes.ObvContactIdentifier {
        switch contactIdentifier {
        case .contactIdentifier(let contactIdentifier):
            return contactIdentifier
        case .objectIDOfPersistedObvContactIdentity(let objectID):
            guard let persistedContact = try PersistedObvContactIdentity.get(objectID: objectID, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                throw ObvFlowControllerError.couldNotFindContact
            }
            return try persistedContact.obvContactIdentifier
        }
    }

    
    private func getGroupType(groupIdentifier: ObvGroupV2Identifier) async throws -> ObvGroupType {
        guard let persistedGroup = try PersistedGroupV2.getWithPrimaryKey(ownCryptoId: groupIdentifier.ownedCryptoId, groupIdentifier: groupIdentifier.identifier.appGroupIdentifier, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            throw ObvFlowControllerError.couldNotFindGRoup
        }
        let groupType = persistedGroup.getOrInferGroupType()
        return groupType
    }

    
    private func userWantsToPresentMyId(ownedCryptoId: ObvCryptoId) {
        let deepLink = ObvDeepLink.myId(ownedCryptoId: ownedCryptoId)
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
            .postOnDispatchQueue()

//        guard let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else {
//            os_log("Could not find owned identity. This is ok if it has just been deleted.", log: log, type: .error)
//            assertionFailure()
//            return
//        }
//        
//        let vcToPresent = SingleOwnedIdentityFlowViewController(ownedIdentity: ownedIdentity, obvEngine: obvEngine, delegate: flowDelegate)
//        
//        let closeButton = BlockBarButtonItem.forClosing { [weak self] in self?.presentedViewController?.dismiss(animated: true) }
//        vcToPresent.navigationItem.setLeftBarButton(closeButton, animated: false)
//        if let presentedViewController {
//            presentedViewController.dismiss(animated: true) { [weak self] in
//                self?.present(UINavigationController(rootViewController: vcToPresent), animated: true)
//            }
//        } else {
//            present(UINavigationController(rootViewController: vcToPresent), animated: true)
//        }
        
    }
    

    private func cancelSentInviteContactToOneToOne(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) async throws {
        let log = self.log
        let obvEngine = self.obvEngine
        let dialog = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ObvDialog?, any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    guard let oneToOneInvitationSent = try PersistedInvitationOneToOneInvitationSent.get(fromOwnedIdentity: ownedCryptoId,
                                                                                                         toContact: contactCryptoId,
                                                                                                         within: context) else {
                        assertionFailure()
                        return continuation.resume(returning: nil)
                    }
                    let dialog = oneToOneInvitationSent.obvDialog
                    return continuation.resume(returning: dialog)
                } catch {
                    os_log("Could not cancel OneToOne invitation: %{public}@", log: log, type: .fault, error.localizedDescription)
                    return continuation.resume(throwing: error)
                }
            }
        }
        guard var dialog else { return }
        try dialog.cancelOneToOneInvitationSent()
        let dialogForEngine = dialog
        try await obvEngine.respondTo(dialogForEngine)
    }

    
    private func userWantsToSendOneToOneInvitationToContact(contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        let ownedCryptoId = contactIdentifier.ownedCryptoId
        let contactCryptoId = contactIdentifier.contactCryptoId
        Task { [weak self] in
            guard let self else { return }
            do {
                assert(flowDelegate != nil)
                try await flowDelegate?.userWantsToInviteContactsToOneToOne(self, ownedCryptoId: ownedCryptoId, users: [(contactCryptoId, nil)])
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }

    
    private func userWantsToCloneGroup(groupIdentifier: ObvGroupIdentifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        let valuesOfGroupToClone = try self.getValuesOfGroupToClone(identifierOfGroupToClone: groupIdentifier)
        try await flowDelegate.userWantsToCloneGroup(self, valuesOfGroupToClone: valuesOfGroupToClone)
    }

    
    private func userWantsToNavigateToOneToOneDiscussionWithContact(contactIdentifier: ObvTypes.ObvContactIdentifier) throws {
        assert(Thread.isMainThread)
        guard let persistedDiscussion = try PersistedOneToOneDiscussion.getPersistedDiscussionOneToOne(contactId: contactIdentifier, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            return
        }
        Task {
            await self.userWantsToNavigateToDiscussion(discussionObjectID: persistedDiscussion.typedObjectID.downcast, messageToShowObjectID: nil)
        }
    }
    
    
    private func userWantsToCall(groupIdentifier: ObvGroupIdentifier) {
        guard let flowDelegate else { assertionFailure(); return }
        switch groupIdentifier {
        case .groupV1(let groupV1Identifier):
            guard let group = try? PersistedContactGroup.getContactGroup(groupIdentifier: groupV1Identifier.groupV1Identifier, ownedCryptoId: groupV1Identifier.ownedCryptoId, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                return
            }
            let contactCryptoIds = Set(group.contactIdentities.compactMap(\.cryptoId))
            flowDelegate.userWantsToSelectAndCallContacts(flowController: self,
                                                          ownedCryptoId: groupIdentifier.ownedCryptoId,
                                                          contactCryptoIds: contactCryptoIds,
                                                          groupId: .groupV1(groupV1Identifier: groupV1Identifier.groupV1Identifier))
        case .groupV2(let groupV2Identifier):
            guard let persistedGroup = try? PersistedGroupV2.get(ownIdentity: groupIdentifier.ownedCryptoId, appGroupIdentifier: groupV2Identifier.identifier.appGroupIdentifier, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                return
            }
            let contactCryptoIds = Set(persistedGroup.otherMembers
                .filter({ !$0.isPending })
                .compactMap(\.cryptoId))
            flowDelegate.userWantsToSelectAndCallContacts(flowController: self,
                                                          ownedCryptoId: groupIdentifier.ownedCryptoId,
                                                          contactCryptoIds: contactCryptoIds,
                                                          groupId: .groupV2(groupV2Identifier: groupV2Identifier.identifier.appGroupIdentifier))
        }
    }
    
    
    private func userWantsToNavigateToDiscussion(groupIdentifier: ObvGroupIdentifier, messageToShowObjectID: TypeSafeManagedObjectID<PersistedMessage>?) async {
        let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
        switch groupIdentifier {
        case .groupV1(let groupV1Identifier):
            guard let groupV1 = try? PersistedContactGroup.getContactGroup(groupIdentifier: groupV1Identifier, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
            discussionObjectID = groupV1.discussion.typedObjectID.downcast
        case .groupV2(let groupV2Identifier):
            guard let groupV2 = try? PersistedGroupV2.get(groupIdentifier: groupV2Identifier, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
            guard let _discussionObjectID = groupV2.discussion?.typedObjectID.downcast else { assertionFailure(); return }
            discussionObjectID = _discussionObjectID
        }
        await self.userWantsToNavigateToDiscussion(discussionObjectID: discussionObjectID, messageToShowObjectID: messageToShowObjectID)
    }
    
    
    private func userWantsToNavigateToDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, messageToShowObjectID: TypeSafeManagedObjectID<PersistedMessage>?) async {
        await self.presentedViewController?.dismissAndAwaitCompletion(animated: true)
        do {
            try popOrPushDiscussionViewController(discussionObjectID: discussionObjectID, messageToShowObjectID: messageToShowObjectID)
        } catch {
            Self.logger.fault("Could not pop or push discussion view controller: \(error)")
        }
    }

    
    private func userWantsToEditGroupNicknameAndCustomPicture(groupIdentifier: ObvGroupIdentifier) {
        
        let vc: EditNicknameAndCustomPictureViewController
        
        switch groupIdentifier {

        case .groupV1(let groupIdentifier):
            
            guard let groupJoined = try? PersistedContactGroupJoined.getContactGroup(groupIdentifier: groupIdentifier, within: ObvStack.shared.viewContext) as? PersistedContactGroupJoined else {
                assertionFailure("Note that if the group is owned, we do not allow nickname nor custom picture.")
                return
            }
            
            let defaultPhoto: UIImage?
            if let url = groupJoined.photoURL {
                defaultPhoto = UIImage(contentsOfFile: url.path)
            } else {
                defaultPhoto = nil
            }

            let currentCustomPhoto: UIImage?
            if let url = groupJoined.customPhotoURL {
                currentCustomPhoto = UIImage(contentsOfFile: url.path)
            } else {
                currentCustomPhoto = nil
            }

            let currentNickname = groupJoined.groupNameCustom ?? ""

            vc = EditNicknameAndCustomPictureViewController(
                model: .init(identifier: .groupV1(groupV1Identifier: groupIdentifier.groupV1Identifier),
                             currentInitials: "", // No initials needed for groups
                             defaultPhoto: defaultPhoto,
                             currentCustomPhoto: currentCustomPhoto,
                             currentNickname: currentNickname),
                delegate: self)
            
        case .groupV2(let groupIdentifier):
            
            guard let group = try? PersistedGroupV2.getWithPrimaryKey(ownCryptoId: groupIdentifier.ownedCryptoId, groupIdentifier: groupIdentifier.identifier.appGroupIdentifier, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                return
            }
            let groupV2Identifier = group.groupIdentifier
            let defaultPhoto: UIImage?
            if let url = group.trustedPhotoURL {
                defaultPhoto = UIImage(contentsOfFile: url.path)
            } else {
                defaultPhoto = nil
            }
            let currentCustomPhoto: UIImage?
            if let url = group.customPhotoURL {
                currentCustomPhoto = UIImage(contentsOfFile: url.path)
            } else {
                currentCustomPhoto = nil
            }
            let currentNickname = group.customNameSanitized ?? ""
            vc = EditNicknameAndCustomPictureViewController(
                model: .init(identifier: .groupV2(groupV2Identifier: groupV2Identifier),
                             currentInitials: "", // No initials needed for groups
                             defaultPhoto: defaultPhoto,
                             currentCustomPhoto: currentCustomPhoto,
                             currentNickname: currentNickname),
                delegate: self)
        }

        presentOnTop(vc, animated: true)

    }

    
    @MainActor
    func userWantsToNavigateToSingleGroupView(groupIdentifier: ObvGroupIdentifier, within navigationController: UINavigationController?) {
        assert(navigationController == nil || navigationController == self, "The navigation controller is discarded, so this should not happen")
        appNavigationRouter.pushSingleGroupViewController(groupIdentifier: groupIdentifier)
    }

    
    func userWantsToNavigateToSingleContactView(contactIdentifier: ObvContactIdentifier) {
        appNavigationRouter.pushSingleContactViewController(contactIdentifier: contactIdentifier)
    }
    
    
    private func presentContactsPresentationViewController(contactIdentifier: ObvContactIdentifier) async {
        assert(Thread.isMainThread)
        let contactsPresentationVC = ContactsPresentationViewController(ownedCryptoId: contactIdentifier.ownedCryptoId, presentedContactCryptoId: contactIdentifier.contactCryptoId) {
            self.presentedViewController?.dismiss(animated: true)
        }
        guard let contact = try? PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            return
        }
        guard let contactFromEngine = try? obvEngine.getContactIdentity(with: contactIdentifier.contactCryptoId, ofOwnedIdentityWith: contactIdentifier.ownedCryptoId) else {
            assertionFailure()
            return
        }
        contactsPresentationVC.title = CommonString.Title.introduceTo(contactFromEngine.publishedIdentityDetails?.coreDetails.getDisplayNameWithStyle(.short) ?? contact.shortOriginalName)
        await self.presentedViewController?.dismissAndAwaitCompletion(animated: true)
        present(contactsPresentationVC, animated: true)
    }
 
    
    /// Presents the discussion view controller for the specified discussion on the appropriate navigation stack.
    ///
    /// Use this method whenever you need to push a discussion view controller.
    /// It ensures the discussion is displayed in the correct navigation context based on the current environment.
    private func popOrPushDiscussionViewController(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, messageToShowObjectID: TypeSafeManagedObjectID<PersistedMessage>?) throws {
        
        guard let flowDelegate else { assertionFailure(); return }
        
        // Requests the appropriate `UINavigationController` from the delegate to display the discussion view controller.
        // The delegate (typically `MainFlowViewController`, a `UISplitViewController`)
        // returns the primary navigation controller in compact environments,
        // or the secondary ("details") navigation controller in expanded environments.
        
        let nav = try flowDelegate.appropriateUINavigationControllerToPushOrPopDiscussion(self)
        
        // If a discussion view controller for the requested discussion exists in the navigation stack,
        // pop to it. Otherwise, create and push a new `SomeSingleDiscussionViewController`.
        
        let existingDiscussionVC = nav.children
            .compactMap { $0 as? SomeSingleDiscussionViewController }
            .filter { $0.discussionObjectID == discussionObjectID }
            .first
        
        if let existingDiscussionVC {
            nav.popToViewController(existingDiscussionVC, animated: true)
            if let messageToShowObjectID {
                existingDiscussionVC.scrollTo(messageObjectID: messageToShowObjectID)
            }
        } else {
            let discussionVC = try buildSingleDiscussionVC(discussionObjectID: discussionObjectID, messageToShowObjectID: messageToShowObjectID)
            nav.pushViewController(discussionVC, animated: true)
            // No need to explicitely scroll to the messageToShow, this is automatically done during during the discussion initialisation.
        }
        
        // At this point, the top view controller of the navigation stack is the requested `SomeSingleDiscussionViewController`.
        
        // There might be some AirDrop'ed files, add them to the discussion draft
        let airDroppedFileURLs = flowDelegate.getAndRemoveAirDroppedFileURLs()
        if !airDroppedFileURLs.isEmpty {
            DispatchQueue.main.async {
                guard let discussionVC = nav.children.last as? SomeSingleDiscussionViewController, discussionVC.discussionObjectID == discussionObjectID else { return }
                for url in airDroppedFileURLs {
                    discussionVC.addAttachmentFromAirDropFile(at: url)
                }
            }
        }
        
    }

    
    private func buildSingleDiscussionVC(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, messageToShowObjectID: TypeSafeManagedObjectID<PersistedMessage>?) throws -> SomeSingleDiscussionViewController {
        let initialScroll: NewSingleDiscussionViewController.InitialScroll
        if let messageToShowObjectID {
            initialScroll = .specificMessage(messageToShowObjectID)
        } else {
            initialScroll = .newMessageSystemOrLastMessage
        }
        let singleDiscussionVC = try getNewSingleDiscussionViewController(discussionObjectID: discussionObjectID, initialScroll: initialScroll)
        return singleDiscussionVC
    }

}


// MARK: - Errors

enum ObvFlowControllerError: Error {
    case couldNotFindOwnedIdentity
    case delegateIsNil
    case couldNotFindGRoup
    case unexpectedOwnedCryptoId
    case unexpectedGroupIdentifier
    case groupMemberNotFound
    case couldNotGenerateJPEGData
    case unexpectedIdentifier
    case couldNotFindDiscussion
    case couldNotFindContact
    case couldNotFindDisplayedContactGroup
    case couldNotFindConcreteGroup
    case inappropriateContactDeletionType
    case cannotDeleteUserPartOfCommonGroup
    case groupIsNil
    case cannotRemoveMemberForJoinedGroupV1
    case couldNotFindPendingGroupMember
    case failedToDeleteDiscussion
}
    
// MARK: - ObvUIGroupV2.ObvGroupV2CreationRouter.ValuesOfClonedGroup from PersistedGroupV2

extension ObvUIGroupV2.ObvGroupV2CreationRouter.ValuesOfClonedGroup {
    
    init(persistedGroup: PersistedGroupV2) throws {
        
        // We only keep persisted contacts (instances of PersistedObvContactIdentity)
        let contactsAmongMembers: [PersistedObvContactIdentity] = persistedGroup.otherMembers.compactMap(\.contact)
        let userIdentifiersOfAddedUsers: [SelectUsersToAddViewModel.User.Identifier] = contactsAmongMembers.map({ .objectIDOfPersistedObvContactIdentity(objectID: $0.objectID) })
        
        let admins: [PersistedObvContactIdentity] = persistedGroup.otherMembers.filter({ $0.isAnAdmin }).compactMap(\.contact)
        let selectedAdmins: [SingleGroupMemberView.Model.Identifier] = admins.map({ .objectIDOfPersistedContact(objectID: $0.objectID, usageContext: .groupCreation) })
        
        let selectedPhoto: UIImage?
        if let trustedPhotoURL = persistedGroup.trustedPhotoURL {
            selectedPhoto = UIImage(contentsOfFile: trustedPhotoURL.path)
        } else {
            selectedPhoto = nil
        }
        
        self.init(userIdentifiersOfAddedUsers: userIdentifiersOfAddedUsers,
                  selectedAdmins: Set(selectedAdmins),
                  selectedGroupType: persistedGroup.getOrInferGroupType(),
                  selectedPhoto: selectedPhoto,
                  selectedGroupName: persistedGroup.trustedName,
                  selectedGroupDescription: persistedGroup.trustedDescription)
        
    }
    
}


// MARK: - ObvUIGroupV2.ObvGroupV2CreationRouter.ValuesOfClonedGroup from PersistedContactGroup

extension ObvUIGroupV2.ObvGroupV2CreationRouter.ValuesOfClonedGroup {
    
    init(persistedContactGroup: PersistedContactGroup) throws {
        
        guard let ownedIdentity = persistedContactGroup.ownedIdentity else { assertionFailure(); throw ObvErrorForInitBaseOnPersistedContactGroup.ownedIdentityIsNil }
        
        // userIdentifiersOfAddedUsers
        
        let contactsAmongPendingMembers = Set(persistedContactGroup.pendingMembers
            .map({ $0.cryptoId })
            .compactMap({ try? PersistedObvContactIdentity.get(cryptoId: $0, ownedIdentity: ownedIdentity, whereOneToOneStatusIs: .any) }))
        let candidates = persistedContactGroup.contactIdentities.union(contactsAmongPendingMembers)
        
        let userIdentifiersOfAddedUsers: [SelectUsersToAddViewModel.User.Identifier] = candidates
            .map({ .objectIDOfPersistedObvContactIdentity(objectID: $0.objectID) })
        
        // selectedPhoto
        
        let selectedPhoto: UIImage?
        if let trustedPhotoURL = persistedContactGroup.displayPhotoURL {
            selectedPhoto = UIImage(contentsOfFile: trustedPhotoURL.path)
        } else {
            selectedPhoto = nil
        }
        
        self.init(userIdentifiersOfAddedUsers: userIdentifiersOfAddedUsers,
                  selectedAdmins: Set<SingleGroupMemberView.Model.Identifier>(),
                  selectedGroupType: .standard,
                  selectedPhoto: selectedPhoto,
                  selectedGroupName: persistedContactGroup.groupNameSanitized,
                  selectedGroupDescription: nil) // The description of a group v1 is only available at the engine level, we don't fetch it here
        
    }
    
    enum ObvErrorForInitBaseOnPersistedContactGroup: Error {
        case ownedIdentityIsNil
    }
    
}


// MARK: -
// MARK: - ObvFlowControllerDelegate
// MARK: -

protocol ObvFlowControllerDelegate: AnyObject {

    func getAndRemoveAirDroppedFileURLs() -> [URL]
    func userWantsToUpdateTrustedIdentityDetailsOfContactIdentity(_ flowController: ObvFlowController, contactIdentifier: ObvTypes.ObvContactIdentifier, using: ObvIdentityDetails) async throws
    func userAskedToRefreshDiscussions() async throws
    func userWantsToInviteContactsToOneToOne(_ flowController: ObvFlowController, ownedCryptoId: ObvCryptoId, users: [(cryptoId: ObvCryptoId, keycloakDetails: ObvKeycloakUserDetails?)]) async throws
    func userWantsToRemoveOneToOneInvitationSent(_ flowController: ObvFlowController, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws
    func userWantsToSendDraft(_ flowController: ObvFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, textBody: String, mentions: Set<MessageJSON.UserMention>) async throws
    func userWantsToAddAttachmentsToDraft(_ flowController: ObvFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, itemProviders: [NSItemProvider], source: LoadItemProviderHelper.ItemProviderProviderSource) async throws -> [LoadedItemProviderToPaste]
    func userWantsToAddAttachmentsToDraftFromURLs(_ flowController: ObvFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, urls: [URL]) async throws
    func userWantsToUpdateDraftBodyAndMentions(_ flowController: ObvFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, body: String, mentions: Set<MessageJSON.UserMention>) async throws
    func userWantsToDeleteAttachmentsFromDraft(_ flowController: ObvFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, draftTypeToDelete: DeleteAllDraftFyleJoinOfDraftOperation.DraftType) async
    func userWantsToReplyToMessage(_ flowController: ObvFlowController, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws
    func userWantsToDownloadReceivedFyleMessageJoinWithStatus(_ flowController: ObvFlowController, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws
    func userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(_ flowController: ObvFlowController, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws
    func userWantsToPauseSentFyleMessageJoinWithStatusFromOtherOwnedDevice(_ flowController: ObvFlowController, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws
    func userWantsToDownloadSentFyleMessageJoinWithStatusFromOtherOwnedDevice(_ flowController: ObvFlowController, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws
    func userWantsToRemoveReplyToMessage(_ flowController: ObvFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws
    func insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(_ flowController: ObvFlowController, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, markAsRead: Bool) async throws
    func userWantsToUpdateDraftExpiration(_ flowController: ObvFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, value: PersistedDiscussionSharedConfigurationValue?) async throws
    func userWantsToReadReceivedMessageThatRequiresUserAction(_ flowController: ObvFlowController, ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageId: ReceivedMessageIdentifier) async throws
    func updatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(_ flowController: ObvFlowController, discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentIDs: Set<ObvManagedObjectPermanentID<PersistedMessage>>) async throws
    func messagesAreNotNewAnymore(_ flowController: ObvFlowController, ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageIds: [MessageIdentifier]) async throws
    func userWantsToUpdateReaction(_ flowController: ObvFlowController, ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, newEmoji: String?) async throws
    func userWantsToUpdatePollVote(_ flowController: ObvFlowController, ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, pollVoteCandidateUuid: UUID, voted: Bool, version: Int) async throws
    func userWantsToStopSharingLocationInDiscussion(_ flowController: ObvFlowController, discussionIdentifier: ObvDiscussionIdentifier) async throws
    func userWantsToSetupNewBackups(_ flowController: ObvFlowController)
    func userWantsToDisplayBackupKey(_ flowController: ObvFlowController)
    func userWantsToSelectAndCallContacts(flowController: ObvFlowController, ownedCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>, groupId: GroupIdentifier?)
    func userWantsObtainAvatar(_ flowController: ObvFlowController, avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?

    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice(_ flowController: ObvFlowController) async throws
    func userWantsToShowMapToConsultLocationSharedContinously(_ flowController: ObvFlowController, presentingViewController: UIViewController, ownedCryptoId: ObvTypes.ObvCryptoId) async throws
    func userWantsToShowMapToSendOrShareLocationContinuously(_ flowController: ObvFlowController, presentingViewController: UIViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws
    func userWantsToShowMapToConsultLocationSharedContinously(_ flowController: ObvFlowController, presentingViewController: UIViewController, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>) async throws

    func userWantsToCreatePoll(_ flowController: ObvFlowController, presentingViewController: UIViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws
    func userWantsToDisplayPollView(_ flowController: ObvFlowController, presentingViewController: UIViewController, pollObjectID: TypeSafeManagedObjectID<PersistedPoll>) async throws
    func userWantsToMarkAllMessagesAsReadInDiscussion(_ flowController: ObvFlowController, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) async throws
    func userWantsToReorderPinnedDiscussions(_ flowController: ObvFlowController, ownedCryptoId: ObvCryptoId, objectIDOfPinnedDiscussions: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws
    
    func userWantsToArchiveDiscussions(_ flowController: ObvFlowController, discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws
    func userWantsToUnarchiveDiscussions(_ flowController: ObvFlowController, discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws

    func userWantsToDeleteDiscussionsAndHasConfirmed(_ flowController: ObvFlowController, discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>], deletionType: DeletionType) async throws
    @MainActor func floatingButtonTapped(flow: ObvFlowController)
    
    func showAlertForUnlockingHiddenOwnedIdentity(_ flowController: ObvFlowController)
    
    func userWantsToProcessReceiptsStoredForLater(_ flowController: ObvFlowController, ownedCryptoId: ObvCryptoId, returnReceiptElements: Set<ObvReturnReceiptElements>) async
    func userTappedObvPlusButton(_ flowController: ObvFlowController)
    
    func appropriateUINavigationControllerToPushOrPopDiscussion(_ flowController: ObvFlowController) throws -> UINavigationController
    func appropriateViewControllerToPresentViewController(_ flowController: ObvFlowController) throws -> UIViewController
    
    func userWantsToCreateNewGroup(_ flowController: ObvFlowController, ownedCryptoId: ObvTypes.ObvCryptoId)

    // Delegate methods required during the implementation of ObvUIGroupV2RouterDelegateForEdition
    func userWantsToPublishGroupV2Modification(_ flowController: ObvFlowController, groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2>, changeset: ObvGroupV2.Changeset) async throws
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ flowController: ObvFlowController, groupIdentifier: ObvGroupV2Identifier) async throws
    func userWantsToLeaveGroup(_ flowController: ObvFlowController, groupIdentifier: ObvGroupIdentifier) async throws
    func userWantsToDisbandGroup(_ flowController: ObvFlowController, groupIdentifier: ObvGroupIdentifier) async throws
    func userWantsToCloneGroup(_ flowController: ObvFlowController, valuesOfGroupToClone: ObvGroupV2CreationRouter.ValuesOfClonedGroup) async throws

    func userWantsToReblockContact(_ flowController: ObvFlowController, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws
    
    func userWantsToUpdatePersonalNote(_ flowController: ObvFlowController, with newText: String?, about: PersonalNoteEditorView.Model.About) async throws
    func userDidSeeNewDetailsOfContact(_ flowController: ObvFlowController, contactIdentifier: ObvContactIdentifier)

    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ flowController: ObvFlowController, groupIdentifier: ObvGroupV1Identifier) async throws

    func userHasSeenPublishedDetails(_ flowController: ObvFlowController, publishedDetails: PublishedDetailsValidationViewModel) async throws

    func userWantsToRemoveMembersFromGroupV1(_ flowController: ObvFlowController, groupV1Identifier: ObvGroupV1Identifier, removedGroupMembers: Set<ObvCryptoId>) async throws
    
    func userWantsToAddSelectedUsersToExistingGroup(_ flowController: ObvFlowController, groupV1Identifier: ObvTypes.ObvGroupV1Identifier, newGroupMembers: Set<ObvCryptoId>) async throws

    func userWantsToUpdateGroupNameAndPicture(_ flowController: ObvFlowController, groupV1Identifier: ObvTypes.ObvGroupV1Identifier, changes: Set<EditGroupNameAndPictureView.Change>) async throws

    func userWantsToDiscoverOlvidPlus(_ flowController: ObvFlowController)
    func userWantsToDismissOlvidPlusSuccessfulSubscriptionView(_ flowController: ObvFlowController)

}
