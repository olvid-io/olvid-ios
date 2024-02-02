/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import os.log
import ObvEngine
import ObvTypes
import ObvCrypto
import ObvUI
import ObvUICoreData
import ObvSettings
import ObvDesignSystem


final class GroupEditionFlowViewController: UIViewController {
    
    enum EditionType {
        case createGroupV2
        case createGroupV1
        case addGroupV1Members(groupUid: UID, currentGroupMembers: Set<ObvCryptoId>)
        case removeGroupV1Members(groupUid: UID, currentGroupMembers: Set<ObvCryptoId>)
        case editGroupV1Details(obvContactGroup: ObvContactGroup)
        case editGroupV2AsAdmin(groupIdentifier: Data)
        case cloneGroup(initialGroupMembers: Set<ObvCryptoId>, initialGroupName: String?, initialGroupDescription: String?, initialPhotoURL: URL?)
        
        var initialGroupName: String? {
            switch self {
            case .cloneGroup(initialGroupMembers: _, initialGroupName: let initialGroupName, initialGroupDescription: _, initialPhotoURL: _):
                return initialGroupName
            default:
                return nil
            }
        }
        
        var initialGroupDescription: String? {
            switch self {
            case .cloneGroup(initialGroupMembers: _, initialGroupName: _, initialGroupDescription: let initialGroupDescription, initialPhotoURL: _):
                return initialGroupDescription
            default:
                return nil
            }
        }
        
        var initialPhotoURL: URL? {
            switch self {
            case .cloneGroup(initialGroupMembers: _, initialGroupName: _, initialGroupDescription: _, initialPhotoURL: let initialPhotoURL):
                return initialPhotoURL
            default:
                return nil
            }
        }
        
    }
    
    // Variables
    
    let ownedCryptoId: ObvCryptoId
    let editionType: EditionType
    let obvEngine: ObvEngine

    private var selectedGroupMembers = Set<PersistedObvContactIdentity>()
    private var groupName: String?
    private var groupDescription: String?
    private var photoURL: URL?
    
    private var initialValuesWereSet = false

    private var createButtonItem: UIBarButtonItem?
    private var doneButtonItem: UIBarButtonItem?

    private(set) var flowNavigationController: UINavigationController!
        
    // Constants
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: GroupEditionFlowViewController.self))

    // MARK: - Initializer

    init(ownedCryptoId: ObvCryptoId, editionType: EditionType, obvEngine: ObvEngine) {
        self.ownedCryptoId = ownedCryptoId
        self.editionType = editionType
        self.obvEngine = obvEngine
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


// MARK: - View controller lifecycle

extension GroupEditionFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
                
        switch editionType {
        case .createGroupV1:
            let mode = MultipleContactsMode.all(oneToOneStatus: .any, requiredCapabilitites: nil)
            let button: MultipleContactsButton = .floating(title: CommonString.Word.Next, systemIcon: .personCropCircleFillBadgeCheckmark)

            let groupEditionMembersChooserVC = MultipleContactsViewController(ownedCryptoId: ownedCryptoId, mode: mode, button: button, disableContactsWithoutDevice: true, allowMultipleSelection: true, showExplanation: false, allowEmptySetOfContacts: false, textAboveContactList: nil) { [weak self] selectedContacts in
                self?.selectedGroupMembers = selectedContacts
                self?.nextButtonTapped()
            } dismissAction: {
                self.cancelButtonTapped()
            }
            groupEditionMembersChooserVC.title = Strings.newGroupTitle
            flowNavigationController = ObvNavigationController(rootViewController: groupEditionMembersChooserVC)

        case .createGroupV2:
            let mode = MultipleContactsMode.all(oneToOneStatus: .any, requiredCapabilitites: [.groupsV2])
            let button: MultipleContactsButton = .floating(title: CommonString.Word.Next, systemIcon: .personCropCircleFillBadgeCheckmark)

            let groupEditionMembersChooserVC = MultipleContactsViewController(ownedCryptoId: ownedCryptoId, mode: mode, button: button, disableContactsWithoutDevice: true, allowMultipleSelection: true, showExplanation: false, allowEmptySetOfContacts: true, textAboveContactList: CommonString.someOfYourContactsMayNotAppearAsGroupV2Candidates) { [weak self] selectedContacts in
                self?.selectedGroupMembers = selectedContacts
                self?.nextButtonTapped()
            } dismissAction: { [weak self] in
                self?.cancelButtonTapped()
            }
            groupEditionMembersChooserVC.title = Strings.newGroupTitle
            flowNavigationController = ObvNavigationController(rootViewController: groupEditionMembersChooserVC)

        case .addGroupV1Members(groupUid: _, currentGroupMembers: let currentGroupMembers):
            let mode = MultipleContactsMode.excluded(from: currentGroupMembers, oneToOneStatus: .any, requiredCapabilitites: nil)
            let button: MultipleContactsButton = .floating(title: CommonString.Word.Ok, systemIcon: .personCropCircleFillBadgeCheckmark)

            let groupEditionMembersChooserVC = MultipleContactsViewController(ownedCryptoId: ownedCryptoId, mode: mode, button: button, disableContactsWithoutDevice: true, allowMultipleSelection: true, showExplanation: false, allowEmptySetOfContacts: false, textAboveContactList: nil) { [weak self] selectedContacts in
                self?.selectedGroupMembers = selectedContacts
                self?.doneButtonTapped()
            } dismissAction: { [weak self] in
                self?.cancelButtonTapped()
            }
            flowNavigationController = ObvNavigationController(rootViewController: groupEditionMembersChooserVC)

        case .removeGroupV1Members(groupUid: _, currentGroupMembers: let currentGroupMembers):
            let mode = MultipleContactsMode.restricted(to: currentGroupMembers, oneToOneStatus: .any)

            let button: MultipleContactsButton = .floating(title: CommonString.Word.Ok, systemIcon: .personCropCircleFillBadgeMinus)

            let groupEditionMembersChooserVC = MultipleContactsViewController(ownedCryptoId: ownedCryptoId, mode: mode, button: button, disableContactsWithoutDevice: false, allowMultipleSelection: true, showExplanation: false, allowEmptySetOfContacts: false, textAboveContactList: nil, selectionStyle: .multiply) { [weak self] selectedContacts in
                self?.selectedGroupMembers = selectedContacts
                self?.doneButtonTapped()
            } dismissAction: { [weak self] in
                self?.cancelButtonTapped()
            }
            flowNavigationController = ObvNavigationController(rootViewController: groupEditionMembersChooserVC)
            
        case .editGroupV1Details(obvContactGroup: let obvContactGroup):
            let contactGroup = ContactGroup(obvContactGroup: obvContactGroup)
            let groupEditionVC = GroupEditionFlowViewHostingController(contactGroup: contactGroup, editionType: .editGroupV1) { [weak self] in
                // REMARK no done button here, we publish in one step unlike doneButtonTapped()
                self?.userWantsToPublishEditedOwnedContactGroup(contactGroup: contactGroup, groupUid: obvContactGroup.groupUid)
                self?.flowNavigationController.dismiss(animated: true)
            }
            groupEditionVC.title = Strings.groupEditionTitle
            let cancelButtonItem = UIBarButtonItem.forClosing(target: self, action: #selector(cancelButtonTapped))
            groupEditionVC.navigationItem.setLeftBarButton(cancelButtonItem, animated: false)
            flowNavigationController = ObvNavigationController(rootViewController: groupEditionVC)
            
        case .editGroupV2AsAdmin(groupIdentifier: let groupIdentifier):
            
            guard let group = try? PersistedGroupV2.getWithPrimaryKey(ownCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                dismiss(animated: true)
                return
            }
            let circleConfig = group.circledInitialsConfiguration
            let groupColors = (circleConfig.backgroundColor(appTheme: AppTheme.shared, using: ObvMessengerSettings.Interface.identityColorStyle), circleConfig.foregroundColor(appTheme: AppTheme.shared, using: ObvMessengerSettings.Interface.identityColorStyle))
            
            guard group.ownedIdentityIsAdmin else { assertionFailure(); return }
            
            let contactGroup = ContactGroup(name: group.trustedName ?? "",
                                            description: group.trustedDescription ?? "",
                                            members: [],
                                            photoURL: group.trustedPhotoURL,
                                            groupColors: groupColors)
            let groupEditionVC = GroupEditionFlowViewHostingController(contactGroup: contactGroup, editionType: .editGroupV2AsAdmin) { [weak self] in
                // Compute an `ObvGroupV2.Changeset` given the differences between the contactGroup and the group
                let changeset: ObvGroupV2.Changeset
                do {
                    changeset = try group.computeChangesetForGroupPhotoAndGroupDetails(with: contactGroup)
                } catch {
                    os_log("Failed to compute changeset: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    return
                }
                guard !changeset.isEmpty else { return }
                ObvMessengerInternalNotification.userWantsToUpdateGroupV2(groupObjectID: group.typedObjectID, changeset: changeset)
                    .postOnDispatchQueue()
                self?.flowNavigationController.dismiss(animated: true)
            }

            groupEditionVC.title = Strings.groupEditionTitle
            let cancelButtonItem = UIBarButtonItem.forClosing(target: self, action: #selector(cancelButtonTapped))
            groupEditionVC.navigationItem.setLeftBarButton(cancelButtonItem, animated: false)
            flowNavigationController = ObvNavigationController(rootViewController: groupEditionVC)

        case .cloneGroup(initialGroupMembers: let initialGroupMembers, initialGroupName: _, initialGroupDescription: _, initialPhotoURL: _):
            
            let mode = MultipleContactsMode.all(oneToOneStatus: .any, requiredCapabilitites: [.groupsV2])
            let button: MultipleContactsButton = .floating(title: CommonString.Word.Next, systemIcon: .personCropCircleFillBadgeCheckmark)
            
            for member in initialGroupMembers {
                if let contact = try? PersistedObvContactIdentity.get(contactCryptoId: member, ownedIdentityCryptoId: ownedCryptoId, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext), contact.supportsCapability(.groupsV2) {
                    self.selectedGroupMembers.insert(contact)
                } else {
                    assertionFailure()
                }
            }

            let groupEditionMembersChooserVC = MultipleContactsViewController(ownedCryptoId: ownedCryptoId, mode: mode, button: button, defaultSelectedContacts: self.selectedGroupMembers, disableContactsWithoutDevice: true, allowMultipleSelection: true, showExplanation: false, allowEmptySetOfContacts: true, textAboveContactList: CommonString.someOfYourContactsMayNotAppearAsGroupV2Candidates) { [weak self] selectedContacts in
                self?.selectedGroupMembers = selectedContacts
                self?.nextButtonTapped()
            } dismissAction: { [weak self] in
                self?.cancelButtonTapped()
            }
            groupEditionMembersChooserVC.title = Strings.newGroupTitle
            flowNavigationController = ObvNavigationController(rootViewController: groupEditionMembersChooserVC)

            // Go directely to the next screen, allowinf to specify the title and description of the group
            
            nextButtonTapped()
            
        }
        
        displayContentController(content: flowNavigationController)
        
    }
    
}

// MARK: - GroupEditionDetailsChooserViewControlllerDelegate

extension GroupEditionFlowViewController: GroupEditionDetailsChooserViewControllerDelegate {
    
    /// Called, e.g., when the user chooses a photo during a group creation or each time a character is typed for the group name
    func groupDescriptionDidChange(groupName: String?, groupDescription: String?, photoURL: URL?) {
        self.groupName = groupName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.groupDescription = groupDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.photoURL = photoURL
        evaluateInfosAndUpdateUI()
    }
    
}

// MARK: - Handling events and navigation

extension GroupEditionFlowViewController {
    
    private func evaluateInfosAndUpdateUI() {
        
        switch editionType {
        case .createGroupV1, .createGroupV2, .cloneGroup:
            createButtonItem?.isEnabled = groupName != nil && !groupName!.isEmpty
        case .addGroupV1Members:
            break
        case .removeGroupV1Members:
            break
        case .editGroupV1Details:
            doneButtonItem?.isEnabled = groupName != nil && !groupName!.isEmpty
        case .editGroupV2AsAdmin:
            break
        }
        
    }
    
    
    @objc func nextButtonTapped() {
        
        switch editionType {
        case .createGroupV1:
            
            let contactGroup = ContactGroup()
            contactGroup.members = selectedGroupMembers.map({ SingleIdentity(contactIdentity: $0) })
            let groupEditionVC = GroupEditionFlowViewHostingController(contactGroup: contactGroup, editionType: .createGroupV1) {
                self.createButtonTapped()
            }
            groupEditionVC.delegate = self
            flowNavigationController.pushViewController(groupEditionVC, animated: true)
            
        case .createGroupV2, .cloneGroup:
            
            // We use the initial values of the cloned group to populate the title, description and photo of the cloned group.
            // We only do this once, preventing a weird behaviour if the user decides to update the group members during the process.
            
            if !initialValuesWereSet {
                self.groupName = editionType.initialGroupName
                self.groupDescription = editionType.initialGroupDescription
                self.photoURL = editionType.initialPhotoURL
                initialValuesWereSet = true
            }

            let contactGroup = ContactGroup(name: self.groupName ?? "",
                                            description: self.groupDescription ?? "",
                                            members: selectedGroupMembers.map({ SingleIdentity(contactIdentity: $0) }),
                                            photoURL: self.photoURL,
                                            groupColors: nil)

            let groupEditionVC = GroupEditionFlowViewHostingController(contactGroup: contactGroup, editionType: .createGroupV2) {
                self.createButtonTapped()
            }
            groupEditionVC.delegate = self
            flowNavigationController.pushViewController(groupEditionVC, animated: true)
            
        case .addGroupV1Members:
            break
        case .removeGroupV1Members:
            break
        case .editGroupV1Details:
            break
        case .editGroupV2AsAdmin:
            break
        }
        
    }
    
    
    @objc func doneButtonTapped() {
        
        switch editionType {
        case .createGroupV1, .createGroupV2, .cloneGroup:
            
            break
            
        case .addGroupV1Members(groupUid: let groupUid, currentGroupMembers: _):

            flowNavigationController.dismiss(animated: true)
            
            let newGroupMembers = Set(selectedGroupMembers.map { $0.cryptoId })
            
            guard !newGroupMembers.isEmpty else { return }
            
            ObvMessengerInternalNotification.inviteContactsToGroupOwned(groupUid: groupUid, ownedCryptoId: ownedCryptoId, newGroupMembers: newGroupMembers)
                .postOnDispatchQueue()

        case .removeGroupV1Members(groupUid: let groupUid, currentGroupMembers: _):
            
            flowNavigationController.dismiss(animated: true)
            
            let removedContacts = Set(selectedGroupMembers.map { $0.cryptoId })
            
            guard !removedContacts.isEmpty else { return }
            
            ObvMessengerInternalNotification.removeContactsFromGroupOwned(groupUid: groupUid, ownedCryptoId: ownedCryptoId, removedContacts: removedContacts)
                .postOnDispatchQueue()
                        
        case .editGroupV1Details:

            assertionFailure()
            return
            
        case .editGroupV2AsAdmin:
            
            assertionFailure()
            return

        }

    }

    // REMARK we do the publication in one step, thus the code differs with doneButtonTapped
    private func userWantsToPublishEditedOwnedContactGroup(contactGroup: ContactGroup, groupUid: UID) {
        DispatchQueue(label: "Queue for publishing new owned Id").async { [weak self] in
            guard let _self = self else { return }
            do {
                let obvGroupCoreDetails = ObvGroupCoreDetails(name: contactGroup.name,
                                                              description: contactGroup.description)
                let obvGroupDetails = ObvGroupDetails(coreDetails: obvGroupCoreDetails,
                                                      photoURL: contactGroup.photoURL)
                try _self.obvEngine.updateLatestDetailsOfOwnedContactGroup(using: obvGroupDetails,
                                                                           ownedCryptoId: _self.ownedCryptoId,
                                                                           groupUid: groupUid)
            } catch {
                DispatchQueue.main.async {
                    _self.showHUD(type: .text(text: "Failed"))
                    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { self?.hideHUD() }
                }
                return
            }

                do {
                    try _self.obvEngine.publishLatestDetailsOfOwnedContactGroup(ownedCryptoId: _self.ownedCryptoId, groupUid: groupUid)
                } catch {
                    DispatchQueue.main.async {
                        _self.showHUD(type: .text(text: "Failed"))
                        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { self?.hideHUD() }
                    }
                    return
                }
                
                DispatchQueue.main.sync {
                    _self.showHUD(type: .checkmark)
                    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { self?.hideHUD() }
                }
                
        }
    }

    
    
    @objc func cancelButtonTapped() {
        flowNavigationController.dismiss(animated: true)
    }
    
    
    @objc func createButtonTapped() {
        
        switch editionType {
            
        case .createGroupV1:
            
            let groupMembersCryptoIds = Set(selectedGroupMembers.map { $0.cryptoId })
            guard !groupMembersCryptoIds.isEmpty else { return }
            guard let groupName = self.groupName else { return }
            guard !groupName.isEmpty else { return }

            ObvMessengerInternalNotification.userWantsToCreateNewGroupV1(
                groupName: groupName,
                groupDescription: self.groupDescription,
                groupMembersCryptoIds: groupMembersCryptoIds,
                ownedCryptoId: ownedCryptoId,
                photoURL: self.photoURL)
            .postOnDispatchQueue()
            
            flowNavigationController.dismiss(animated: true)

        case .createGroupV2, .cloneGroup:
            
            let groupCoreDetails = GroupV2CoreDetails(groupName: self.groupName, groupDescription: self.groupDescription)
            let ownPermissions = ObvUICoreDataConstants.defaultObvGroupV2PermissionsForAdmin
            let otherGroupMembers = Set(selectedGroupMembers
                .map({ $0.cryptoId })
                .map({ ObvGroupV2.IdentityAndPermissions(identity: $0, permissions: ObvUICoreDataConstants.defaultObvGroupV2PermissionsForNewGroupMembers) }))
            let ownedCryptoId = self.ownedCryptoId
            let photoURL = self.photoURL
            
            ObvMessengerInternalNotification.userWantsToCreateNewGroupV2(groupCoreDetails: groupCoreDetails,
                                                                         ownPermissions: ownPermissions,
                                                                         otherGroupMembers: otherGroupMembers,
                                                                         ownedCryptoId: ownedCryptoId,
                                                                         photoURL: photoURL)
                .postOnDispatchQueue()
            
            flowNavigationController.dismiss(animated: true)

        case .addGroupV1Members,
             .removeGroupV1Members,
             .editGroupV1Details,
             .editGroupV2AsAdmin:
            break
        }
        
    }

}


extension GroupEditionFlowViewController {
    
    struct Strings {
        
        static let newGroupTitle = NSLocalizedString("CHOOSE_GROUP_MEMBERS", comment: "View controller title")
        static let groupEditionTitle = NSLocalizedString("EDIT_GROUP", comment: "View controller title")
        static let groupV2CustomNameAndPhotoEditionTitle = NSLocalizedString("CHOOSE_GROUP_CUSTOM_NAME_AND_PHOTO_TITLE", comment: "View controller title")
        
    }
    
}
