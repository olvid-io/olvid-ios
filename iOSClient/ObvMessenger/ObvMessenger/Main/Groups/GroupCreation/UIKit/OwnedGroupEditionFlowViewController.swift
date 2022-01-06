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


final class OwnedGroupEditionFlowViewController: UIViewController {
    
    enum EditionType {
        case create
        case addGroupMembers(groupUid: UID, currentGroupMembers: Set<ObvCryptoId>)
        case removeGroupMembers(groupUid: UID, currentGroupMembers: Set<ObvCryptoId>)
        case editGroupDetails(obvContactGroup: ObvContactGroup)
    }
    
    // Variables
    
    let ownedCryptoId: ObvCryptoId
    let editionType: EditionType

    private var selectedGroupMembers = Set<PersistedObvContactIdentity>()
    private var groupName: String?
    private var groupDescription: String?
    private var photoURL: URL?

    private var createButtonItem: UIBarButtonItem?
    private var doneButtonItem: UIBarButtonItem?

    private(set) var flowNavigationController: UINavigationController!
        
    // Constants
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    // MARK: - Initializer

    init(ownedCryptoId: ObvCryptoId, editionType: EditionType) {
        self.ownedCryptoId = ownedCryptoId
        self.editionType = editionType
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


// MARK: - View controller lifecycle

extension OwnedGroupEditionFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
                
        switch editionType {
        case .create:
            let mode = MultipleContactsMode.all
            let button: MultipleContactsButton
            if #available(iOS 13.0, *) {
                button = .floating(title: CommonString.Word.Next, systemIcon: .personCropCircleFillBadgeCheckmark)
            } else {
                button = .done(CommonString.Word.Next)
            }

            let groupEditionMembersChooserVC = MultipleContactsViewController(ownedCryptoId: ownedCryptoId, mode: mode, button: button, disableContactsWithoutDevice: true, allowMultipleSelection: true, showExplanation: false) { selectedContacts in
                self.selectedGroupMembers = selectedContacts
                self.nextButtonTapped()
            } dismissAction: {
                self.cancelButtonTapped()
            }
            groupEditionMembersChooserVC.title = Strings.newGroupTitle
            flowNavigationController = ObvNavigationController(rootViewController: groupEditionMembersChooserVC)

        case .addGroupMembers(groupUid: _, currentGroupMembers: let currentGroupMembers):
            let mode = MultipleContactsMode.excluded(from: currentGroupMembers)
            let button: MultipleContactsButton
            if #available(iOS 13.0, *) {
                button = .floating(title: CommonString.Word.Ok, systemIcon: .personCropCircleFillBadgeCheckmark)
            } else {
                button = .done()
            }

            let groupEditionMembersChooserVC = MultipleContactsViewController(ownedCryptoId: ownedCryptoId, mode: mode, button: button, disableContactsWithoutDevice: true, allowMultipleSelection: true, showExplanation: false) { selectedContacts in
                self.selectedGroupMembers = selectedContacts
                self.doneButtonTapped()
            } dismissAction: {
                self.cancelButtonTapped()
            }
            flowNavigationController = ObvNavigationController(rootViewController: groupEditionMembersChooserVC)

        case .removeGroupMembers(groupUid: _, currentGroupMembers: let currentGroupMembers):
            let mode = MultipleContactsMode.restricted(to: currentGroupMembers)

            let button: MultipleContactsButton
            if #available(iOS 13.0, *) {
                button = .floating(title: CommonString.Word.Ok, systemIcon: .personCropCircleFillBadgeMinus)
            } else {
                button = .done()
            }

            let groupEditionMembersChooserVC = MultipleContactsViewController(ownedCryptoId: ownedCryptoId, mode: mode, button: button, disableContactsWithoutDevice: false, allowMultipleSelection: true, showExplanation: false, selectionStyle: .multiply) { selectedContacts in
                self.selectedGroupMembers = selectedContacts
                self.doneButtonTapped()
            } dismissAction: {
                self.cancelButtonTapped()
            }
            flowNavigationController = ObvNavigationController(rootViewController: groupEditionMembersChooserVC)
            
        case .editGroupDetails(obvContactGroup: let obvContactGroup):
            let groupEditionVC: UIViewController
            if #available(iOS 13.0, *) {
                let contactGroup = ContactGroup(obvContactGroup: obvContactGroup)
                let ownedGroupEditionFlowVC = OwnedGroupEditionFlowViewHostingController(contactGroup: contactGroup, editionType: .edit) {
                    // REMARK no done button here, we publish in one step unlike doneButtonTapped()
                    self.userWantsToPublishEditedOwnedContactGroup(contactGroup: contactGroup, groupUid: obvContactGroup.groupUid)
                }
                groupEditionVC = ownedGroupEditionFlowVC
            } else {
                let groupEditionDetailsChooserVC = GroupEditionDetailsChooserViewController(ownedCryptoId: ownedCryptoId)
                groupEditionDetailsChooserVC.delegate = self
                groupEditionVC = groupEditionDetailsChooserVC
                let coreDetails = obvContactGroup.trustedOrLatestCoreDetails
                groupEditionDetailsChooserVC.set(groupName: coreDetails.name, groupDescription: coreDetails.description)
                doneButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneButtonTapped))
                doneButtonItem!.isEnabled = false
                groupEditionVC.navigationItem.setRightBarButton(doneButtonItem!, animated: false)
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

extension OwnedGroupEditionFlowViewController: GroupEditionDetailsChooserViewControllerDelegate {
    
    func groupDescriptionDidChange(groupName: String?, groupDescription: String?, photoURL: URL?) {
        self.groupName = groupName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.groupDescription = groupDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.photoURL = photoURL
        evaluateInfosAndUpdateUI()
    }
    
}

// MARK: - Handling events and navigation

extension OwnedGroupEditionFlowViewController {
    
    private func evaluateInfosAndUpdateUI() {
        
        switch editionType {
        case .create:
            createButtonItem?.isEnabled = groupName != nil && !groupName!.isEmpty
        case .addGroupMembers:
            break
        case .removeGroupMembers:
            break
        case .editGroupDetails:
            doneButtonItem?.isEnabled = groupName != nil && !groupName!.isEmpty
        }
        
    }
    
    
    @objc func nextButtonTapped() {
        
        switch editionType {
        case .create:
            let groupEditionVC: UIViewController
            if #available(iOS 13.0, *) {
                let contactGroup = ContactGroup()
                let ownedGroupEditionFlowVC = OwnedGroupEditionFlowViewHostingController(contactGroup: contactGroup, editionType: .create) {
                    self.createButtonTapped()
                }
                ownedGroupEditionFlowVC.delegate = self
                groupEditionVC = ownedGroupEditionFlowVC
            } else {
                let groupEditionDetailsChooserVC = GroupEditionDetailsChooserViewController(ownedCryptoId: ownedCryptoId)
                groupEditionDetailsChooserVC.delegate = self
                groupEditionVC = groupEditionDetailsChooserVC
                createButtonItem = UIBarButtonItem(title: CommonString.Word.Create, style: UIBarButtonItem.Style.done, target: self, action: #selector(createButtonTapped))
                createButtonItem!.isEnabled = false
                groupEditionDetailsChooserVC.navigationItem.setRightBarButton(createButtonItem!, animated: false)
            }
            flowNavigationController.pushViewController(groupEditionVC, animated: true)
        case .addGroupMembers:
            break
        case .removeGroupMembers:
            break
        case .editGroupDetails:
            break
        }
        
    }
    
    
    @objc func doneButtonTapped() {
        
        switch editionType {
        case .create:
            break
        case .addGroupMembers(groupUid: let groupUid, currentGroupMembers: _):

            flowNavigationController.dismiss(animated: true)
            
            let newGroupMembers = Set(selectedGroupMembers.map { $0.cryptoId })
            
            guard !newGroupMembers.isEmpty else { return }
            
            let NotificationType = MessengerInternalNotification.InviteContactsToGroupOwned.self
            let userInfo = [NotificationType.Key.ownedCryptoId: ownedCryptoId,
                            NotificationType.Key.groupUid: groupUid,
                            NotificationType.Key.newGroupMembers: newGroupMembers] as [String: Any]
            NotificationCenter.default.post(name: NotificationType.name, object: nil, userInfo: userInfo)
            
        case .removeGroupMembers(groupUid: let groupUid, currentGroupMembers: _):
            
            flowNavigationController.dismiss(animated: true)
            
            let removedContacts = Set(selectedGroupMembers.map { $0.cryptoId })
            
            guard !removedContacts.isEmpty else { return }
            
            let NotificationType = MessengerInternalNotification.RemoveContactsFromGroupOwned.self
            let userInfo = [NotificationType.Key.ownedCryptoId: ownedCryptoId,
                            NotificationType.Key.groupUid: groupUid,
                            NotificationType.Key.removedContacts: removedContacts] as [String: Any]
            NotificationCenter.default.post(name: NotificationType.name, object: nil, userInfo: userInfo)
            
        case .editGroupDetails(obvContactGroup: let obvContactGroup):

            guard let groupName = self.groupName else { return }
            guard !groupName.isEmpty else { return }
            
            flowNavigationController.dismiss(animated: true)
            
            let NotificationType = MessengerInternalNotification.EditOwnedGroupDetails.self
            let userInfo = [NotificationType.Key.ownedCryptoId: ownedCryptoId,
                            NotificationType.Key.groupUid: obvContactGroup.groupUid,
                            NotificationType.Key.groupName: groupName,
                            NotificationType.Key.groupDescription: groupDescription as Any] as [String: Any]
            NotificationCenter.default.post(name: NotificationType.name, object: nil, userInfo: userInfo)
            
        }

    }

    @available(iOS 13.0, *)
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
        case .create:
            
            let groupMembersCryptoIds = Set(selectedGroupMembers.map { $0.cryptoId })
            guard !groupMembersCryptoIds.isEmpty else { return }
            guard let groupName = self.groupName else { return }
            guard !groupName.isEmpty else { return }
            
            flowNavigationController.dismiss(animated: true)

            let NotificationType = MessengerInternalNotification.CreateNewGroup.self
            let userInfo = [NotificationType.Key.groupName: groupName,
                            NotificationType.Key.groupDescription: groupDescription as Any,
                            NotificationType.Key.groupMembersCryptoIds: groupMembersCryptoIds,
                            NotificationType.Key.ownedCryptoId: ownedCryptoId,
                            NotificationType.Key.photoURL: self.photoURL as Any] as [String: Any]
            NotificationCenter.default.post(name: NotificationType.name, object: nil, userInfo: userInfo)

        case .addGroupMembers,
             .removeGroupMembers,
             .editGroupDetails:
            break
        }
        
    }

}
