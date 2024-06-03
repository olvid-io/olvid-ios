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
import os.log
import ObvEngine
import ObvTypes
import ObvCrypto
import ObvUI
import ObvUICoreData
import ObvSettings
import ObvDesignSystem

/// Use to edit a GroupV1. Until may 2024, this view controller was also used to create/edit and clone groups V2. It is not replaced by a new flow (see ``NewGroupEditionFlowViewController``)
final class GroupEditionFlowViewController: UIViewController {
    
    enum EditionType {
        case createGroupV1
        case addGroupV1Members(groupUid: UID, currentGroupMembers: Set<ObvCryptoId>)
        case removeGroupV1Members(groupUid: UID, currentGroupMembers: Set<ObvCryptoId>)
        case editGroupV1Details(obvContactGroup: ObvContactGroup)
    }
    
    // Variables
    
    let ownedCryptoId: ObvCryptoId
    let editionType: EditionType
    let obvEngine: ObvEngine

    private var selectedGroupMembers = Set<PersistedObvContactIdentity>()
    private var groupName: String?
    private var groupDescription: String?
    private var photoURL: URL?
    private var groupType: PersistedGroupV2.GroupType?
    
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
        case .createGroupV1:
            createButtonItem?.isEnabled = groupName != nil && !groupName!.isEmpty
        case .addGroupV1Members:
            break
        case .removeGroupV1Members:
            break
        case .editGroupV1Details:
            doneButtonItem?.isEnabled = groupName != nil && !groupName!.isEmpty
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
            
        case .addGroupV1Members:
            break
        case .removeGroupV1Members:
            break
        case .editGroupV1Details:
            break
        }
        
    }
    
    
    @objc func doneButtonTapped() {
        
        switch editionType {
        case .createGroupV1:
            
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

        case .addGroupV1Members,
             .removeGroupV1Members,
             .editGroupV1Details:
            break
        }
        
    }

}


extension GroupEditionFlowViewController {
    
    struct Strings {
        
        static let newGroupTitle = NSLocalizedString("CHOOSE_GROUP_MEMBERS", comment: "View controller title")
        static let groupEditionTitle = NSLocalizedString("EDIT_GROUP", comment: "View controller title")
        
    }
    
}
