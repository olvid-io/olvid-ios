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
import ObvAppCoreConstants
import ObvAppTypes


/// Use to edit a GroupV1. Until may 2024, this view controller was also used to create/edit and clone groups V2. It is not replaced by a new flow (see ``NewGroupEditionFlowViewController``)
final class GroupEditionFlowViewController: UINavigationController {
    
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
    private var groupType: ObvAppTypes.ObvGroupType?
    
    private var initialValuesWereSet = false

    private var createButtonItem: UIBarButtonItem?
    private var doneButtonItem: UIBarButtonItem?

    // Constants
    
    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: GroupEditionFlowViewController.self))

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
                
        let editionType = self.editionType
                
        switch editionType {
        case .createGroupV1:
            
            let verticalConfiguration = VerticalUsersViewConfiguration(
                showExplanation: false,
                disableUsersWithoutDevice: true,
                allowMultipleSelection: true,
                textAboveUserList: nil,
                selectionStyle: .checkmark)
            let buttonConfiguration = HorizontalAndVerticalUsersViewButtonConfiguration(
                title: CommonString.Word.Next,
                systemIcon: .personCropCircleFillBadgeCheckmark,
                action: { [weak self] selectedContacts in self?.userDidSelectGroupMembers(selectedContacts, editionType: editionType) },
                allowEmptySetOfContacts: false)
            let configuration = HorizontalAndVerticalUsersViewConfiguration(
                verticalConfiguration: verticalConfiguration,
                horizontalConfiguration: nil,
                buttonConfiguration: buttonConfiguration)
            let multipleContactsVC = MultipleUsersHostingViewController(
                ownedCryptoId: ownedCryptoId,
                mode: .all(oneToOneStatus: .any, requiredCapabilitites: nil),
                configuration: configuration,
                delegate: nil)
            multipleContactsVC.title = Strings.newGroupTitle
            self.viewControllers = [multipleContactsVC]

        case .addGroupV1Members(groupUid: _, currentGroupMembers: let currentGroupMembers):
            
            let verticalConfiguration = VerticalUsersViewConfiguration(
                showExplanation: false,
                disableUsersWithoutDevice: true,
                allowMultipleSelection: true,
                textAboveUserList: nil,
                selectionStyle: .checkmark)
            let buttonConfiguration = HorizontalAndVerticalUsersViewButtonConfiguration(
                title: CommonString.Word.Ok,
                systemIcon: .personCropCircleFillBadgeCheckmark,
                action: { [weak self] selectedContacts in self?.userDidSelectGroupMembers(selectedContacts, editionType: editionType) },
                allowEmptySetOfContacts: false)
            let configuration = HorizontalAndVerticalUsersViewConfiguration(
                verticalConfiguration: verticalConfiguration,
                horizontalConfiguration: nil,
                buttonConfiguration: buttonConfiguration)
            let multipleContactsVC = MultipleUsersHostingViewController(
                ownedCryptoId: ownedCryptoId,
                mode: .excluded(from: currentGroupMembers, oneToOneStatus: .any, requiredCapabilitites: nil),
                configuration: configuration,
                delegate: nil)
            multipleContactsVC.title = Strings.addNewGroupMembers
            self.viewControllers = [multipleContactsVC]

        case .removeGroupV1Members(groupUid: _, currentGroupMembers: let currentGroupMembers):
            
            let verticalConfiguration = VerticalUsersViewConfiguration(
                showExplanation: false,
                disableUsersWithoutDevice: false,
                allowMultipleSelection: true,
                textAboveUserList: nil,
                selectionStyle: .multiply)
            let buttonConfiguration = HorizontalAndVerticalUsersViewButtonConfiguration(
                title: CommonString.Word.Ok,
                systemIcon: .personCropCircleFillBadgeMinus,
                action: { [weak self] selectedContacts in self?.userDidSelectGroupMembers(selectedContacts, editionType: editionType) },
                allowEmptySetOfContacts: false)
            let configuration = HorizontalAndVerticalUsersViewConfiguration(
                verticalConfiguration: verticalConfiguration,
                horizontalConfiguration: nil,
                buttonConfiguration: buttonConfiguration)
            let multipleContactsVC = MultipleUsersHostingViewController(
                ownedCryptoId: ownedCryptoId,
                mode: .restricted(to: currentGroupMembers, oneToOneStatus: .any),
                configuration: configuration,
                delegate: nil)
            multipleContactsVC.title = Strings.removeGroupMembers
            self.viewControllers = [multipleContactsVC]
            
        case .editGroupV1Details(obvContactGroup: let obvContactGroup):
            let contactGroup = ContactGroup(obvContactGroup: obvContactGroup)
            let groupEditionVC = GroupEditionFlowViewHostingController(contactGroup: contactGroup, editionType: .editGroupV1) { [weak self] in
                // REMARK no done button here, we publish in one step unlike doneButtonTapped()
                self?.userWantsToPublishEditedOwnedContactGroup(contactGroup: contactGroup, groupUid: obvContactGroup.groupUid)
                self?.dismiss(animated: true)
            }
            groupEditionVC.title = Strings.groupEditionTitle
            self.viewControllers = [groupEditionVC]
            
        }
        
        self.children.first?.navigationItem.rightBarButtonItem = .init(systemItem: .cancel, primaryAction: .init(handler: { [weak self] _ in
            guard let self else { return }
            cancelButtonTapped()
        }))

    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        guard let vc = self.children.compactMap({ $0 as? MultipleUsersHostingViewController }).first else { return }
        
        vc.navigationItem.searchController = vc.searchController
        vc.navigationItem.hidesSearchBarWhenScrolling = false
    }

    
    @MainActor
    private func userDidSelectGroupMembers(_ contactCryptoIds: Set<ObvCryptoId>, editionType: EditionType) {
        let selectedContacts = Set(contactCryptoIds.compactMap { cryptoId in
            try? PersistedObvContactIdentity.get(contactCryptoId: cryptoId, ownedIdentityCryptoId: ownedCryptoId, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext)
        })
        assert(selectedContacts.count == contactCryptoIds.count)
        self.selectedGroupMembers = selectedContacts
        switch editionType {
        case .createGroupV1:
            nextButtonTapped()
        case .addGroupV1Members, .removeGroupV1Members:
            doneButtonTapped()
        case .editGroupV1Details:
            assertionFailure("This method is not expected to be called in this case")
            return
        }
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
            self.pushViewController(groupEditionVC, animated: true)
            
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

            self.dismiss(animated: true)
            
            let newGroupMembers = Set(selectedGroupMembers.map { $0.cryptoId })
            
            guard !newGroupMembers.isEmpty else { return }
            
            ObvMessengerInternalNotification.inviteContactsToGroupOwned(groupUid: groupUid, ownedCryptoId: ownedCryptoId, newGroupMembers: newGroupMembers)
                .postOnDispatchQueue()

        case .removeGroupV1Members(groupUid: let groupUid, currentGroupMembers: _):
            
            self.dismiss(animated: true)
            
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
        self.dismiss(animated: true)
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
            
            self.dismiss(animated: true)

        case .addGroupV1Members,
             .removeGroupV1Members,
             .editGroupV1Details:
            break
        }
        
    }

}


extension GroupEditionFlowViewController {
    
    struct Strings {
        
        static let removeGroupMembers = NSLocalizedString("REMOVE_GROUP_MEMBERS", comment: "View controller title")
        static let addNewGroupMembers = NSLocalizedString("ADD_NEW_GROUP_MEMBERS", comment: "View controller title")
        static let newGroupTitle = NSLocalizedString("CHOOSE_GROUP_MEMBERS", comment: "View controller title")
        static let groupEditionTitle = NSLocalizedString("EDIT_GROUP", comment: "View controller title")
        
    }
    
}
